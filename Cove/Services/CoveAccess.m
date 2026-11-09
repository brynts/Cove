// Cove access layer for worse_query.
// Copyright (C) 2026 Bryan Saputra
// SPDX-License-Identifier: GPL-3.0-or-later
//
// CoveLeakRange is the pathleak inode walk (Copyright (C) 2026 Taj C)
// limited to a caller-supplied range so the UI can report progress.

#import "CoveAccess.h"
#import "CoveConfig.h"
#import "worse_query.h"

#include <pthread.h>
#include <string.h>
#include <unistd.h>
#include <fcntl.h>
#include <errno.h>
#include <sys/stat.h>
#include <sys/mount.h>
#include <sys/fsgetpath.h>
#include <sys/xattr.h>

static pthread_mutex_t gLock;

__attribute__((constructor))
static void coveInitLock(void) {
    pthread_mutexattr_t attr;
    pthread_mutexattr_init(&attr);
    pthread_mutexattr_settype(&attr, PTHREAD_MUTEX_RECURSIVE);
    pthread_mutex_init(&gLock, &attr);
    pthread_mutexattr_destroy(&attr);
}

@implementation CoveListResult
- (instancetype)init {
    self = [super init];
    if (self) {
        _paths = @[];
        _errorText = @"";
        _code = -255;
    }
    return self;
}
@end

static int versionCode(void) {
    NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
    return (int)v.majorVersion * 10000 + (int)v.minorVersion * 100 + (int)v.patchVersion;
}

BOOL CoveOSIsSupported(void) {
    NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
    int code = versionCode();
    if (v.majorVersion == 26) return code >= 260000 && code <= 260702;
    if (v.majorVersion == 27) return code >= 270000 && code <= 270299;
    return NO;
}

NSString *CoveOSLabel(void) {
    NSOperatingSystemVersion v = NSProcessInfo.processInfo.operatingSystemVersion;
    return [NSString stringWithFormat:@"iOS %ld.%ld.%ld",
            (long)v.majorVersion, (long)v.minorVersion, (long)v.patchVersion];
}

NSString *CoveAppGroupID(void) {
    return @COVE_APP_GROUP;
}

NSString *CoveAppGroupContainer(void) {
    NSURL *url = [NSFileManager.defaultManager
        containerURLForSecurityApplicationGroupIdentifier:@COVE_APP_GROUP];
    return url.path;
}

NSString *CoveDescribeGrant(int64_t code) {
    switch (code) {
        case -1:
            return @"App Group container is not available. The signed app needs the application-groups entitlement.";
        case -2:
            return @"Could not resolve container-manager symbols on this iOS version.";
        case -3:
            return @"Could not create a container query.";
        case -4:
            return @"Could not create the App Group symlink.";
        case -5:
            return @"containermanagerd rejected the query.";
        case -6:
            return @"The kernel refused the sandbox extension.";
        case -100:
            return @"This iOS version is outside 26.0–26.7.2 and 27.0–27.2.";
        case -255:
            return @"The path is empty or not absolute.";
        default:
            if (code < 0) return [NSString stringWithFormat:@"Sandbox extension failed (%lld).", code];
            return @"OK";
    }
}

static NSString *coveLogPath(void) {
    NSString *docs = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
    if (docs.length == 0) return nil;
    return [docs stringByAppendingPathComponent:@"cove.log"];
}

void CoveWriteLog(NSString *message) {
    if (message.length == 0) return;
    NSString *path = coveLogPath();
    if (path.length == 0) return;
    NSString *stamp = [[NSISO8601DateFormatter new] stringFromDate:[NSDate date]];
    NSString *line = [NSString stringWithFormat:@"%@  %@\n", stamp, message];
    int fd = open(path.fileSystemRepresentation, O_WRONLY | O_CREAT | O_APPEND, 0644);
    if (fd < 0) return;
    NSData *data = [line dataUsingEncoding:NSUTF8StringEncoding];
    if (data.length) write(fd, data.bytes, data.length);
    fsync(fd);
    close(fd);
    NSLog(@"Cove %@", message);
}

NSString *CoveReadLog(void) {
    NSString *path = coveLogPath();
    if (path.length == 0) return @"";
    NSData *data = [NSData dataWithContentsOfFile:path];
    if (data.length == 0) return @"";
    if (data.length > 48000) data = [data subdataWithRange:NSMakeRange(data.length - 48000, 48000)];
    return [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding] ?: @"";
}

void CoveClearLog(void) {
    NSString *path = coveLogPath();
    if (path.length == 0) return;
    [@"" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
}

int64_t CoveGrant(NSString *path) {
    if (!CoveOSIsSupported()) return -100;
    if (path.length == 0 || ![path hasPrefix:@"/"]) return -255;

    BOOL alt = NO;
    if ([path containsString:@"/Containers/Shared/AppGroup"] &&
        NSProcessInfo.processInfo.operatingSystemVersion.majorVersion == 26) {
        alt = YES;
    }

    pthread_mutex_lock(&gLock);
    CoveWriteLog([NSString stringWithFormat:@"grant alt=%d %@", alt, path]);
    // create_dir = true skips lstat. A sandboxed lstat hides foreign containers as ENOENT.
    int64_t handle = worse_query(path, @COVE_APP_GROUP, alt, true);
    CoveWriteLog([NSString stringWithFormat:@"grant result %lld %@", handle, CoveDescribeGrant(handle)]);
    pthread_mutex_unlock(&gLock);
    return handle;
}

void CoveRelease(int64_t handle) {
    if (handle < 0) return;
    pthread_mutex_lock(&gLock);
    worse_query_release(handle);
    pthread_mutex_unlock(&gLock);
}

CoveListResult *CoveListChildren(NSString *path) {
    CoveListResult *result = [CoveListResult new];
    int64_t handle = CoveGrant(path);
    result.code = handle;
    if (handle < 0) {
        result.errorText = CoveDescribeGrant(handle);
        return result;
    }
    NSError *error = nil;
    NSArray<NSString *> *names = [NSFileManager.defaultManager contentsOfDirectoryAtPath:path error:&error];
    CoveRelease(handle);
    if (!names) {
        result.code = -7;
        result.errorText = error.localizedDescription ?: @"Could not list that directory.";
        return result;
    }
    NSMutableArray<NSString *> *paths = [NSMutableArray arrayWithCapacity:names.count];
    for (NSString *name in names) {
        [paths addObject:[path stringByAppendingPathComponent:name]];
    }
    result.paths = paths;
    result.errorText = @"";
    return result;
}

uint64_t CoveBaselineInode(void) {
    NSString *path = [NSTemporaryDirectory() stringByAppendingPathComponent:[[NSUUID UUID] UUIDString]];
    [@"cove" writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
    struct stat st;
    uint64_t inode = 0;
    if (stat(path.fileSystemRepresentation, &st) == 0) inode = st.st_ino;
    unlink(path.fileSystemRepresentation);
    return inode;
}

NSArray<NSString *> *CoveLeakRange(NSString *path, uint64_t startInode, uint64_t endInode) {
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
    size_t prefixLength = strlen(prefix);
    if (prefixLength == 1 && prefix[0] == '/') prefixLength = 0;

    NSFileManager *files = [NSFileManager defaultManager];
    NSMutableArray<NSString *> *result = [NSMutableArray array];
    char buffer[PATH_MAX];
    for (uint64_t inode = startInode; inode <= endInode; inode++) {
        ssize_t n = fsgetpath(buffer, sizeof(buffer), &fsid, inode);
        if (n <= 0) continue;
        if (strncmp(buffer, prefix, prefixLength) != 0) continue;
        if (buffer[prefixLength] != '/') continue;
        if (strchr(buffer + prefixLength + 1, '/')) continue;
        NSString *string = [files stringWithFileSystemRepresentation:buffer length:strlen(buffer)];
        if (string) [result addObject:string];
    }
    return result;
}

static NSString *coveXattr(NSString *path) {
    char buf[512];
    memset(buf, 0, sizeof(buf));
    ssize_t len = getxattr(path.fileSystemRepresentation,
                            "com.apple.containermanager.identifier",
                            buf, sizeof(buf) - 1, 0, 0);
    if (len <= 0) return nil;
    buf[len] = 0;
    NSString *value = [NSString stringWithUTF8String:buf];
    if (value.length == 0 || ![value containsString:@"."]) return nil;
    return value;
}

static NSString *coveString(id value) {
    if ([value isKindOfClass:[NSString class]] && [value length] > 0 && [value containsString:@"."]) {
        return value;
    }
    return nil;
}

static NSString *coveMetaID(NSString *containerPath) {
    NSString *meta = [containerPath stringByAppendingPathComponent:
                      @".com.apple.mobile_container_manager.metadata.plist"];
    NSDictionary *dict = [NSDictionary dictionaryWithContentsOfFile:meta];
    if (![dict isKindOfClass:[NSDictionary class]]) return nil;
    NSString *ident = coveString(dict[@"MCMMetadataIdentifier"]);
    if (!ident) ident = coveString(dict[@"MCMApplicationIdentifier"]);
    NSDictionary *info = dict[@"MCMMetadataInfo"];
    if (!ident && [info isKindOfClass:[NSDictionary class]]) {
        ident = coveString(info[@"MCMApplicationIdentifier"]);
    }
    return ident;
}

NSString *CoveContainerIdentifier(NSString *containerPath) {
    NSString *ident = coveXattr(containerPath);
    if (ident) return ident;
    int64_t handle = CoveGrant(containerPath);
    if (handle < 0) return nil;
    ident = coveXattr(containerPath);
    if (!ident) ident = coveMetaID(containerPath);
    CoveRelease(handle);
    return ident;
}
