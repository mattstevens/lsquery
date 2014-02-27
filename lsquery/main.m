#import <Foundation/Foundation.h>
#import "NSBundleAdditions.h"

static NSArray *BundlesForBundleIdentifier(NSString *bundleIdentifier) {
    NSMutableArray *bundles = [NSMutableArray array];

    NSString *queryString = [NSString stringWithFormat:@"kMDItemCFBundleIdentifier == '%@'c", bundleIdentifier];

    MDQueryRef query = MDQueryCreate(kCFAllocatorDefault, (__bridge CFStringRef)queryString, NULL, NULL);
    MDQueryExecute(query, kMDQuerySynchronous);
    MDQueryStop(query);

    CFIndex count = MDQueryGetResultCount(query);
    for (CFIndex i = 0; i < count; i++) {
        MDItemRef item = (MDItemRef)MDQueryGetResultAtIndex(query, i);
        NSString *path = CFBridgingRelease(MDItemCopyAttribute(item, kMDItemPath));
        NSBundle *bundle = [NSBundle bundleWithPath:path];
        if (bundle != nil) {
            [bundles addObject:bundle];
        }
    }

    CFRelease(query);

    return bundles;
}

static void print_usage(void) {
    printf("Usage: lsquery <bundle identifier>\n");
}

/**
 * This utility does not detect all conflicts. Launch Services does not expose an API to obtain the location of all
 * applications for a given bundle identifier, so Spotlight is used for this purpose. Further, not all data in a
 * CFBundleVersion is necessarily used by Launch Services as part of the version, so it is possible that two bundles
 * with different CFBundleVersion strings could have the same Launch Services version.
 */

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
