#import <Foundation/Foundation.h>
#import <getopt.h>

extern OSStatus _LSCopyAllApplicationURLs(CFArrayRef *urls) __attribute__((weak_import));
extern uint64_t _LSGetVersionFromString(CFStringRef versionString) __attribute__((weak_import));
extern CFStringRef _LSVersionNumberCopyStringRepresentation(uint64_t version) __attribute__((weak_import));

/**
 * Returns an array of NSBundles for every application in the Launch Services database with the
 * given bundle identifier.
 *
 * Prior to OS X 10.10 Launch Services did not have an API to perform this search. On these systems
 * the private _LSCopyAllApplicationURLs() is used to obtain the URLs of every application on
 * the system and they are searched for matching bundles. This is inefficient but preferable
 * to using another system like Spotlight to obtain this list, as Launch Services may be aware
 * of bundles that Spotlight is not.
 */
static NSArray *BundlesForBundleIdentifier(NSString *bundleIdentifier) {
    CFArrayRef urlRefs = NULL;
    NSMutableSet *bundles = [NSMutableSet set];

    if (LSCopyApplicationURLsForBundleIdentifier != NULL) {
        urlRefs = LSCopyApplicationURLsForBundleIdentifier((__bridge CFStringRef)bundleIdentifier, NULL);
    } else if (_LSCopyAllApplicationURLs != NULL) {
        _LSCopyAllApplicationURLs(&urlRefs);
    }

    if (urlRefs == NULL) {
        return nil;
    }

    for (NSURL *url in (__bridge NSArray *)urlRefs) {
        NSBundle *bundle = [NSBundle bundleWithURL:url];
        if (bundle != nil && [bundle bundleIdentifier] != nil) {
            if ([[bundle bundleIdentifier] caseInsensitiveCompare:bundleIdentifier] == NSOrderedSame) {
                [bundles addObject:bundle];
            }
        }
    }

    CFRelease(urlRefs);

    return [bundles allObjects];
}

/**
 * Returns the default application for the given bundle identifier.
 */
static NSBundle *BundleForBundleIdentifier(NSString *bundleIdentifier) {
    NSBundle *bundle = nil;
    CFURLRef urlRef = NULL;
    LSFindApplicationForInfo(0, (__bridge CFStringRef)bundleIdentifier, NULL, NULL, &urlRef);
    if (urlRef != NULL) {
        NSURL *bundleURL = CFBridgingRelease(urlRef);
        bundle = [NSBundle bundleWithURL:bundleURL];
    }
    return bundle;
}

/**
 * Returns all applications capable of handling the specified URL.
 */
static NSArray *BundlesForURL(NSURL *url) {
    NSMutableSet *bundles = [NSMutableSet set];
    NSArray *urls = CFBridgingRelease(LSCopyApplicationURLsForURL((__bridge CFURLRef)url, kLSRolesAll));
    if (urls == nil) {
        return nil;
    }

    for (NSURL *url in urls) {
        NSBundle *bundle = [NSBundle bundleWithURL:url];
        if (bundle != nil) {
            [bundles addObject:bundle];
        }
    }

    return [bundles allObjects];
}

/**
 * Returns the default application for handling the specified URL.
 */
static NSBundle *BundleForURL(NSURL *url) {
    NSBundle *bundle = nil;
    CFURLRef urlRef = NULL;

    if (LSCopyDefaultApplicationURLForURL != NULL) {
        urlRef = LSCopyDefaultApplicationURLForURL((__bridge CFURLRef)url, kLSRolesAll, NULL);
    } else {
        LSGetApplicationForURL((__bridge CFURLRef)url, kLSRolesAll, NULL, &urlRef);
    }

    if (urlRef != NULL) {
        bundle = [NSBundle bundleWithURL:(__bridge NSURL *)urlRef];
        CFRelease(urlRef);
    }
    return bundle;
}

/**
 * Returns the Launch Services version number for the specified bundle.
 *
 * This uses the private _LSGetVersionFromString() function to obtain Launch Services's
 * intepretation of the bundle's version. This provides more accurate detection of duplicate
 * application bundles that lead to undefined launch behavior.
 */
static uint64_t VersionForBundle(NSBundle *bundle) {
    NSString *versionString = [bundle objectForInfoDictionaryKey:@"CFBundleVersion"];
    return _LSGetVersionFromString((__bridge CFStringRef)versionString);
}

/**
 * Returns a string representation of the specified Launch Services version number.
 */
static NSString *StringForVersion(uint64_t version) {
    if (_LSVersionNumberCopyStringRepresentation != NULL) {
        return CFBridgingRelease(_LSVersionNumberCopyStringRepresentation(version));
    }

    uint64_t major = version / 1000000;
    version -= major * 1000000;

    uint64_t minor = version / 1000;
    version -= minor * 1000;

    uint64_t patch = version;

    if (patch > 0) {
        return [NSString stringWithFormat:@"%llu.%llu.%llu", major, minor, patch];
    } else if (minor > 0) {
        return [NSString stringWithFormat:@"%llu.%llu", major, minor];
    } else {
        return [NSString stringWithFormat:@"%llu", major];
    }
}

// TODO: Searching by URL may return different applications
static void PrintAllBundles(NSBundle *resultBundle, NSArray *bundles) {
    uint64_t resultVersion = VersionForBundle(resultBundle);
    NSString *resultVersionString = StringForVersion(resultVersion);

    bundles = [bundles sortedArrayUsingComparator:^NSComparisonResult(NSBundle *bundle1, NSBundle *bundle2) {
        uint64_t version1 = VersionForBundle(bundle1);
        uint64_t version2 = VersionForBundle(bundle2);

        if (version2 > version1) {
            return NSOrderedDescending;
        } else if (version2 < version1) {
            return NSOrderedAscending;
        } else {
            return [[bundle1 bundlePath] compare:[bundle2 bundlePath]];
        }
    }];

    int versionLength = 0;
    BOOL hasMultipleBundles = NO;

    for (NSBundle *bundle in bundles) {
        uint64_t version = VersionForBundle(bundle);
        versionLength = MAX((int)[StringForVersion(version) length], versionLength);
        if (version == resultVersion && [[bundle bundlePath] isEqualToString:[resultBundle bundlePath]] == NO) {
            hasMultipleBundles = YES;
        }
    }

    printf("*%-*s %s\n", versionLength + 1, [[resultVersionString stringByAppendingString:@":"] UTF8String], [[resultBundle bundlePath] fileSystemRepresentation]);

    for (NSBundle *bundle in bundles) {
        if ([[bundle bundlePath] isEqualToString:[resultBundle bundlePath]]) {
            continue;
        }

        NSString *version = StringForVersion(VersionForBundle(bundle));
        printf(" %-*s %s\n", versionLength + 1, [[version stringByAppendingString:@":"] UTF8String], [[bundle bundlePath] fileSystemRepresentation]);
    }

    if (hasMultipleBundles) {
        printf("\nWarning: Multiple bundles found with version %s.\n", [resultVersionString UTF8String]);
        printf("The result of Launch Services queries for this application will be undefined.\n\n");
    }
}

static void SearchForBundleIdentifier(NSString *bundleIdentifier, BOOL findAll) {
    NSBundle *resultBundle = BundleForBundleIdentifier(bundleIdentifier);
    if (resultBundle == nil) {
        fprintf(stderr, "No application found for \"%s\"\n", [bundleIdentifier UTF8String]);
        exit(1);
    }

    if (findAll) {
        NSArray *bundles = BundlesForBundleIdentifier(bundleIdentifier);
        if (bundles == nil) {
            fprintf(stderr, "Unable to query matching applications from Launch Services.\n");
            exit(1);
        }

        PrintAllBundles(resultBundle, bundles);
    } else {
        printf("%s\n", [[resultBundle bundlePath] UTF8String]);
    }
}

static void SearchForURL(NSURL *url, BOOL findAll) {
    NSBundle *resultBundle = BundleForURL(url);
    if (resultBundle == nil) {
        fprintf(stderr, "No application found for \"%s\"\n", [[url absoluteString] UTF8String]);
        exit(1);
    }

    if (findAll) {
        NSArray *bundles = BundlesForURL(url);
        if (bundles == nil) {
            fprintf(stderr, "Unable to query matching applications from Launch Services.\n");
            exit(1);
        }

        PrintAllBundles(resultBundle, bundles);
    } else {
        printf("%s\n", [[resultBundle bundlePath] UTF8String]);
    }
}

static void print_usage() {
    printf(
    "Usage: lsquery <options>\n"
    "\n"
    "Queries the Launch Services database for matching application bundles.\n"
    "\n"
    "Options:\n"
    "  -h, --help                 Show this help message and exit\n"
    "  -b, --bundleid <bundleid>  Search for the given bundle identifier\n"
    "  -u, --url <url>            Search for handlers of the given URL\n"
    "      --find-all             Show all matching bundles\n"
    "      --version              Show the version and exit \n");
}

int main(int argc, char *argv[]) {
    @autoreleasepool {
        NSString *bundleIdentifier = nil;
        NSURL *url = nil;
        BOOL findAll = NO;
        int optchar;

        static struct option longopts[] = {
            { "help",            no_argument,        NULL,              'h' },
            { "bundleid",        required_argument,  NULL,              'b' },
            { "url",             required_argument,  NULL,              'u' },
            { "find-all",        no_argument,        NULL,              'a' },
            { "version",         no_argument,        NULL,              'v' },
            { NULL,              0,                  NULL,               0  }
        };

        while ((optchar = getopt_long(argc, argv, "hb:u:", longopts, NULL)) != -1) {
            switch (optchar) {
                case 'h':
                    print_usage();
                    return 0;
                case 'b':
                    bundleIdentifier = @(optarg);
                    break;
                case 'u':
                    url = [NSURL URLWithString:@(optarg)];
                    if (url == nil) {
                        fprintf(stderr, "\"%s\" is not a valid URL\n", optarg);
                        exit(1);
                    }
                    break;
                case 'a':
                    findAll = YES;
                    break;
                case 'v':
                    printf("lsquery 0.1\n");
                    return 0;
                case '?':
                    return 1;
                default:
                    fprintf(stderr, "unhandled option -%c\n", optchar);
                    return 1;
            }
        }
        argc -= optind;
        argv += optind;

        if (bundleIdentifier != nil) {
            SearchForBundleIdentifier(bundleIdentifier, findAll);
        } else if (url != nil) {
            SearchForURL(url, findAll);
        } else {
            print_usage();
            return 1;
        }
    }

    return 0;
}
