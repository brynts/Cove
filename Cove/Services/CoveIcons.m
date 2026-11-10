#import "CoveAccess.h"
#import <UIKit/UIKit.h>
#import <dlfcn.h>
#import <objc/message.h>

#include <string.h>
#include <sys/mount.h>
#include <sys/fsgetpath.h>

NSArray<NSString *> *CoveLeakAppInfoPlists(NSString *path, uint64_t startInode, uint64_t endInode) {
    if (path.length == 0 || endInode < startInode || startInode < 1) return @[];
    NSString *dir = path;
    while (dir.length > 1 && [dir hasSuffix:@"/"]) {
        dir = [dir substringToIndex:dir.length - 1];
    }
    struct statfs sfs;
    if (statfs(dir.fileSystemRepresentation, &sfs) != 0) return nil;

    fsid_t fsid = sfs.f_fsid;
    char prefix[PATH_MAX];
    if (![dir getFileSystemRepresentation:prefix maxLength:sizeof(prefix)]) return nil;
    const char *prefixPath = prefix;
    if (strncmp(prefixPath, "/private/var/", 13) == 0) prefixPath += 8;
    size_t prefixLength = strlen(prefixPath);

    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    char buffer[PATH_MAX];
    for (uint64_t inode = startInode; inode <= endInode; inode++) {
        ssize_t n = fsgetpath(buffer, sizeof(buffer), &fsid, inode);
        if (n <= 0) continue;
        const char *got = buffer;
        if (strncmp(got, "/private/var/", 13) == 0) got += 8;
        if (strncmp(got, prefixPath, prefixLength) != 0) continue;
        if (got[prefixLength] != '/') continue;
        const char *rel = got + prefixLength + 1;
        int slashes = 0;
        for (const char *p = rel; *p; p++) if (*p == '/') slashes++;
        if (slashes != 2) continue;
        size_t len = strlen(got);
        const char *suffix = ".app/Info.plist";
        size_t suffixLength = strlen(suffix);
        if (len < suffixLength || strcmp(got + len - suffixLength, suffix) != 0) continue;
        NSString *string = [files stringWithFileSystemRepresentation:buffer length:strlen(buffer)];
        if (string) [result addObject:string];
    }
    return result;
}

static void coveAddIconNames(NSMutableArray<NSString *> *names, id value) {
    if ([value isKindOfClass:[NSString class]] && [value length] > 0) {
        [names addObject:value];
    } else if ([value isKindOfClass:[NSArray class]]) {
        for (id item in (NSArray *)value) coveAddIconNames(names, item);
    }
}

static NSArray<NSString *> *coveIconNames(NSDictionary *info) {
    NSMutableArray<NSString *> *names = [NSMutableArray array];
    NSDictionary *icons = info[@"CFBundleIcons"];
    NSDictionary *primary = [icons isKindOfClass:[NSDictionary class]] ? icons[@"CFBundlePrimaryIcon"] : nil;
    if ([primary isKindOfClass:[NSDictionary class]]) {
        coveAddIconNames(names, primary[@"CFBundleIconFiles"]);
        coveAddIconNames(names, primary[@"CFBundleIconName"]);
    }
    NSDictionary *ipad = info[@"CFBundleIcons~ipad"];
    NSDictionary *ipadPrimary = [ipad isKindOfClass:[NSDictionary class]] ? ipad[@"CFBundlePrimaryIcon"] : nil;
    if ([ipadPrimary isKindOfClass:[NSDictionary class]]) {
        coveAddIconNames(names, ipadPrimary[@"CFBundleIconFiles"]);
        coveAddIconNames(names, ipadPrimary[@"CFBundleIconName"]);
    }
    coveAddIconNames(names, info[@"CFBundleIconFiles"]);
    coveAddIconNames(names, info[@"CFBundleIconFile"]);
    return names;
}

static UIImage *coveLooseIcon(NSString *appPath, NSArray<NSString *> *names) {
    NSArray<NSString *> *children = [NSFileManager.defaultManager contentsOfDirectoryAtPath:appPath error:nil];
    UIImage *best = nil;
    CGFloat bestSide = 0;
    for (NSString *file in children) {
        NSString *lower = file.lowercaseString;
        if (![lower hasSuffix:@".png"]) continue;
        BOOL match = [lower containsString:@"appicon"];
        if (!match) {
            for (NSString *name in names) {
                if (name.length && [file hasPrefix:name]) { match = YES; break; }
            }
        }
        if (!match) continue;
        UIImage *image = [UIImage imageWithContentsOfFile:[appPath stringByAppendingPathComponent:file]];
        CGFloat side = MAX(image.size.width, image.size.height) * MAX(image.scale, 1);
        if (side > bestSide) {
            best = image;
            bestSide = side;
        }
    }
    return bestSide >= 40 ? best : nil;
}

static UIImage *coveImageObject(id object) {
    if ([object isKindOfClass:[UIImage class]]) return object;
    if (!object) return nil;
    SEL ui = NSSelectorFromString(@"UIImage");
    if ([object respondsToSelector:ui]) {
        id image = ((id (*)(id, SEL))objc_msgSend)(object, ui);
        if ([image isKindOfClass:[UIImage class]]) return image;
    }
    SEL cg = NSSelectorFromString(@"image");
    if ([object respondsToSelector:cg]) {
        CGImageRef ref = ((CGImageRef (*)(id, SEL))objc_msgSend)(object, cg);
        if (ref) return [UIImage imageWithCGImage:ref scale:3 orientation:UIImageOrientationUp];
    }
    return nil;
}

static UIImage *coveCatalogIcon(NSString *appPath, NSArray<NSString *> *names) {
    NSString *car = [appPath stringByAppendingPathComponent:@"Assets.car"];
    if (![NSFileManager.defaultManager fileExistsAtPath:car]) return nil;
    dlopen("/System/Library/PrivateFrameworks/CoreUI.framework/CoreUI", RTLD_LAZY);
    Class cls = NSClassFromString(@"CUICatalog");
    if (!cls) return nil;
    SEL initSel = NSSelectorFromString(@"initWithURL:error:");
    if (![cls instancesRespondToSelector:initSel]) return nil;
    NSError *error = nil;
    id catalog = ((id (*)(id, SEL, NSURL *, NSError **))objc_msgSend)(
        [cls alloc], initSel, [NSURL fileURLWithPath:car], &error);
    if (!catalog) return nil;

    NSMutableArray<NSString *> *candidates = [names mutableCopy] ?: [NSMutableArray array];
    if (![candidates containsObject:@"AppIcon"]) [candidates addObject:@"AppIcon"];
    for (NSString *name in candidates) {
        SEL scaled = NSSelectorFromString(@"imageWithName:scaleFactor:");
        if ([catalog respondsToSelector:scaled]) {
            id image = ((id (*)(id, SEL, id, CGFloat))objc_msgSend)(catalog, scaled, name, (CGFloat)3);
            UIImage *ui = coveImageObject(image);
            if (ui.size.width >= 16) return ui;
        }
        SEL plain = NSSelectorFromString(@"imageWithName:");
        if ([catalog respondsToSelector:plain]) {
            id image = ((id (*)(id, SEL, id))objc_msgSend)(catalog, plain, name);
            UIImage *ui = coveImageObject(image);
            if (ui.size.width >= 16) return ui;
        }
    }
    return nil;
}

NSDictionary<NSString *, id> *CoveInspectBundle(NSString *appPath) {
    if (appPath.length == 0 || ![appPath hasSuffix:@".app"]) return nil;
    int64_t handle = CoveGrant(appPath);
    if (handle < 0) return nil;
    NSDictionary *info = [NSDictionary dictionaryWithContentsOfFile:
                          [appPath stringByAppendingPathComponent:@"Info.plist"]];
    NSMutableDictionary *out = [NSMutableDictionary dictionary];
    if ([info[@"CFBundleIdentifier"] isKindOfClass:[NSString class]]) {
        out[@"bundleID"] = info[@"CFBundleIdentifier"];
    }
    id display = info[@"CFBundleDisplayName"];
    if (![display isKindOfClass:[NSString class]] || [display length] == 0) display = info[@"CFBundleName"];
    if ([display isKindOfClass:[NSString class]] && [display length] > 0) out[@"name"] = display;
    NSArray<NSString *> *names = coveIconNames(info ?: @{});
    UIImage *icon = coveLooseIcon(appPath, names);
    if (!icon) icon = coveCatalogIcon(appPath, names);
    if (icon) {
        NSData *png = UIImagePNGRepresentation(icon);
        if (png.length) out[@"icon"] = png;
    }
    CoveRelease(handle);
    return out;
}

NSData *CoveSystemIconPNG(NSString *bundleID) {
    if (bundleID.length == 0) return nil;
    SEL sel = NSSelectorFromString(@"_applicationIconImageForBundleIdentifier:format:scale:");
    if (![UIImage respondsToSelector:sel]) return nil;
    UIImage *(*fn)(id, SEL, NSString *, NSInteger, CGFloat) = (void *)objc_msgSend;
    UIImage *image = fn([UIImage class], sel, bundleID, 0, 3);
    if (image.size.width < 16) image = fn([UIImage class], sel, bundleID, 2, 3);
    if (image.size.width < 16) return nil;
    return UIImagePNGRepresentation(image);
}
