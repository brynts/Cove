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
    const char *prefixPath = prefix;
    if (strncmp(prefixPath, "/private/var/", 13) == 0) prefixPath += 8;
    size_t prefixLength = strlen(prefixPath);
    if (prefixLength == 1 && prefixPath[0] == '/') prefixLength = 0;

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
        if (strchr(got + prefixLength + 1, '/')) continue;
        NSString *string = [files stringWithFileSystemRepresentation:buffer length:strlen(buffer)];
        if (string) [result addObject:string];
    }
    return result;
}
