#import "CoveCatalog.h"
#import <objc/message.h>

static NSString *coveString(id value) {
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    return nil;
}

static NSString *covePath(id value) {
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value path];
    return coveString(value);
}

NSArray<NSDictionary<NSString *, NSString *> *> *CoveInstalledApplications(void) {
    NSMutableArray<NSDictionary<NSString *, NSString *> *> *result = [NSMutableArray array];
    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
    if (!workspaceClass || ![workspaceClass respondsToSelector:defaultSel]) return result;
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSel);
    if (!workspace) return result;

    NSArray *apps = nil;
    for (NSString *selName in @[ @"allInstalledApplications", @"allApplications", @"installedApplications" ]) {
        SEL sel = NSSelectorFromString(selName);
        if (![workspace respondsToSelector:sel]) continue;
        id candidate = ((id (*)(id, SEL))objc_msgSend)(workspace, sel);
        if ([candidate isKindOfClass:[NSArray class]] && [candidate count] > 0) {
            apps = candidate;
            break;
        }
    }
    if (apps.count == 0) return result;

    for (id app in apps) {
        SEL bidSel = NSSelectorFromString(@"bundleIdentifier");
        if (![app respondsToSelector:bidSel]) continue;
        NSString *bundleID = coveString(((id (*)(id, SEL))objc_msgSend)(app, bidSel));
        if (bundleID.length == 0 || ![bundleID containsString:@"."]) continue;

        NSString *name = bundleID;
        SEL nameSel = NSSelectorFromString(@"localizedName");
        if ([app respondsToSelector:nameSel]) {
            NSString *localized = coveString(((id (*)(id, SEL))objc_msgSend)(app, nameSel));
            if (localized.length) name = localized;
        }

        NSString *container = nil;
        for (NSString *selName in @[ @"dataContainerURL", @"containerURL" ]) {
            SEL sel = NSSelectorFromString(selName);
            if (![app respondsToSelector:sel]) continue;
            container = covePath(((id (*)(id, SEL))objc_msgSend)(app, sel));
            if (container.length) break;
        }

        NSMutableDictionary<NSString *, NSString *> *entry = [NSMutableDictionary dictionary];
        entry[@"bundleID"] = bundleID;
        entry[@"name"] = name;
        if (container.length) entry[@"container"] = container;
        [result addObject:entry];
    }
    return result;
}
