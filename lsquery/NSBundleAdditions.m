#import "NSBundleAdditions.h"

@implementation NSBundle (LSQuery)

- (NSString *)ms_bundleVersion {
    return [[self infoDictionary] objectForKey:@"CFBundleVersion"];
}

@end
