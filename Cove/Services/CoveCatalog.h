#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

/// bundleID, name, and container when Launch Services provides one.
NSArray<NSDictionary<NSString *, NSString *> *> *CoveInstalledApplications(void);

NS_ASSUME_NONNULL_END
