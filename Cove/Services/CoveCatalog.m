#import "CoveCatalog.h"
#import <dlfcn.h>
#import <objc/message.h>

static NSString *gStatus = @"not run";

NSString *CoveCatalogStatus(void) {
    return gStatus ?: @"";
}

static NSString *coveString(id value) {
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) return value;
    return nil;
}

static NSString *covePath(id value) {
    if ([value isKindOfClass:[NSURL class]]) return [(NSURL *)value path];
    return coveString(value);
}

static void coveLoadLaunchServices(void) {
    dlopen("/System/Library/Frameworks/CoreServices.framework/CoreServices", RTLD_LAZY);
    dlopen("/System/Library/Frameworks/MobileCoreServices.framework/MobileCoreServices", RTLD_LAZY);
}

static void coveAddProxy(NSMutableArray *result, NSMutableSet<NSString *> *seen, id app) {
    if (!app) return;
    SEL bidSel = NSSelectorFromString(@"bundleIdentifier");
    if (![app respondsToSelector:bidSel]) return;
    NSString *bundleID = coveString(((id (*)(id, SEL))objc_msgSend)(app, bidSel));
    if (bundleID.length == 0 || ![bundleID containsString:@"."]) return;
    if ([seen containsObject:bundleID]) return;

    // Leave name unset when localizedName is unavailable. Falling back to the
    // raw bundleID here used to make it into the UI as the app's "name" --
    // AppDiscovery.pretty(bundleID) is a nicer placeholder, and the real
    // CFBundleDisplayName/CFBundleName read from the .app bundle should win
    // over this once AppLibrary.enrichFromBundles() runs.
    NSString *name = nil;
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
    if (name.length) entry[@"name"] = name;
    if (container.length) entry[@"container"] = container;
    [seen addObject:bundleID];
    [result addObject:entry];
}

NSArray<NSDictionary<NSString *, NSString *> *> *CoveInstalledApplications(void) {
    NSMutableArray *result = [NSMutableArray array];
    NSMutableSet<NSString *> *seen = [NSMutableSet set];
    coveLoadLaunchServices();

    Class workspaceClass = NSClassFromString(@"LSApplicationWorkspace");
    if (!workspaceClass) {
        gStatus = @"LSApplicationWorkspace missing";
        return result;
    }
    SEL defaultSel = NSSelectorFromString(@"defaultWorkspace");
    if (![workspaceClass respondsToSelector:defaultSel]) {
        gStatus = @"defaultWorkspace missing";
        return result;
    }
    id workspace = ((id (*)(id, SEL))objc_msgSend)(workspaceClass, defaultSel);
    if (!workspace) {
        gStatus = @"defaultWorkspace nil";
        return result;
    }

    for (NSString *selName in @[
        @"allInstalledApplications",
        @"allApplications",
        @"installedApplications",
        @"applicationsOfType:"
    ]) {
        SEL sel = NSSelectorFromString(selName);
        if (![workspace respondsToSelector:sel]) continue;
        id candidate = nil;
        if ([selName hasSuffix:@":"]) {
            for (NSUInteger type = 0; type < 3; type++) {
                candidate = ((id (*)(id, SEL, NSUInteger))objc_msgSend)(workspace, sel, type);
                if ([candidate isKindOfClass:[NSArray class]] && [candidate count] > 0) break;
                candidate = nil;
            }
        } else {
            candidate = ((id (*)(id, SEL))objc_msgSend)(workspace, sel);
        }
        NSUInteger count = [candidate isKindOfClass:[NSArray class]] ? [candidate count] : 0;
        if (count == 0) continue;
        for (id app in candidate) coveAddProxy(result, seen, app);
        if (result.count) {
            gStatus = [NSString stringWithFormat:@"%@ count=%lu", selName, (unsigned long)result.count];
            return result;
        }
    }

    for (NSString *selName in @[
        @"enumerateApplicationsOfType:block:",
        @"enumerateApplicationsOfType:usingBlock:"
    ]) {
        SEL sel = NSSelectorFromString(selName);
        if (![workspace respondsToSelector:sel]) continue;
        void (*enumerate)(id, SEL, NSUInteger, void (^)(id)) = (void *)objc_msgSend;
        for (NSUInteger type = 0; type < 3 && result.count == 0; type++) {
            enumerate(workspace, sel, type, ^(id app) {
                coveAddProxy(result, seen, app);
            });
        }
        if (result.count) {
            gStatus = [NSString stringWithFormat:@"%@ count=%lu", selName, (unsigned long)result.count];
            return result;
        }
    }

    gStatus = @"workspace returned no applications";
    return result;
}
