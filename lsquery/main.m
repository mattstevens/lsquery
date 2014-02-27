#import <Foundation/Foundation.h>
#import "NSBundleAdditions.h"

extern OSStatus _LSCopyAllApplicationURLs(CFArrayRef *urls) __attribute__((weak_import));

/**
 * Returns an array of NSBundles for every application in the Launch Services database with the
 * given bundle identifier.
 *
 * Launch Services does not appear to have any API that can perform this search. Instead
 * the private _LSCopyAllApplicationURLs() is used to obtain the URLs of every application on
 * the system and they are searched for matching bundles. This is inefficient but preferable
 * to using another system like Spotlight to obtain this list, as Launch Services may be aware
 * of bundles that Spotlight is not.
 */
static NSArray *BundlesForBundleIdentifier(NSString *bundleIdentifier) {
    CFArrayRef urlRefs;
    NSMutableArray *bundles = [NSMutableArray array];

    if (_LSCopyAllApplicationURLs == NULL || _LSCopyAllApplicationURLs(&urlRefs) != 0) {
        return nil;
    }

    for (NSURL *url in (__bridge NSArray *)urlRefs) {
        NSBundle *bundle = [NSBundle bundleWithURL:url];
        if (bundle != nil) {
            if ([[bundle bundleIdentifier] isEqualToString:bundleIdentifier]) {
                [bundles addObject:bundle];
            }
        }
    }

    CFRelease(urlRefs);

    return bundles;
}

static void print_usage(void) {
    printf("Usage: lsquery <bundle identifier>\n");
}

int main(int argc, const char * argv[]) {
    @autoreleasepool {
        NSArray *arguments = [[NSProcessInfo processInfo] arguments];
        if ([arguments count] < 2) {
            print_usage();
            return 1;
        }

        NSString *bundleIdentifier = arguments[1];

        CFURLRef urlRef = NULL;
        LSFindApplicationForInfo(0, (__bridge CFStringRef)bundleIdentifier, NULL, NULL, &urlRef);
        if (urlRef == NULL) {
            printf("No application found for \"%s\"\n", [bundleIdentifier UTF8String]);
            return 1;
        }

        NSURL *bundleURL = CFBridgingRelease(urlRef);
        NSBundle *resultBundle = [NSBundle bundleWithURL:bundleURL];
        NSString *resultVersion = [resultBundle ms_bundleVersion];

        NSArray *bundles = BundlesForBundleIdentifier(bundleIdentifier);
        if (bundles == nil) {
            printf("Unable to query matching applications from Launch Services.\n");
            return 1;
        }

        bundles = [bundles sortedArrayUsingComparator:^NSComparisonResult(NSBundle *bundle1, NSBundle *bundle2) {
            NSString *version1 = [bundle1 ms_bundleVersion];
            NSString *version2 = [bundle2 ms_bundleVersion];
            NSComparisonResult result = [version2 compare:version1 options:NSNumericSearch];
            if (result == NSOrderedSame) {
                result = [[bundle1 bundlePath] compare:[bundle2 bundlePath]];
            }
            return result;
        }];

        int versionLength = 0;
        BOOL hasMultipleBundles = NO;

        for (NSBundle *bundle in bundles) {
            NSString *version = [bundle ms_bundleVersion];
            versionLength = MAX((int)[version length], versionLength);
            if ([version isEqualToString:resultVersion] && [[bundle bundlePath] isEqualToString:[resultBundle bundlePath]] == NO) {
                hasMultipleBundles = YES;
            }
        }

        printf("*%-*s %s\n", versionLength, [[resultVersion stringByAppendingString:@":"] UTF8String], [[resultBundle bundlePath] fileSystemRepresentation]);

        for (NSBundle *bundle in bundles) {
            if ([[bundle bundlePath] isEqualToString:[resultBundle bundlePath]]) {
                continue;
            }

            NSString *version = [bundle ms_bundleVersion];
            printf(" %-*s %s\n", versionLength + 1, [[version stringByAppendingString:@":"] UTF8String], [[bundle bundlePath] fileSystemRepresentation]);
        }

        if (hasMultipleBundles) {
            printf("\nWarning: Multiple bundles found with version %s.\n", [resultVersion UTF8String]);
            printf("The result of Launch Services queries for %s will be undefined.\n\n", [bundleIdentifier UTF8String]);
        }
    }
    return 0;
}
