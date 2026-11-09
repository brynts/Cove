#import <Foundation/Foundation.h>
#include <stdint.h>

NS_ASSUME_NONNULL_BEGIN

@interface CoveListResult : NSObject
@property (nonatomic, copy) NSArray<NSString *> *paths;
@property (nonatomic, copy) NSString *errorText;
@property (nonatomic) int64_t code;
@end

BOOL CoveOSIsSupported(void);
NSString *CoveOSLabel(void);
NSString *CoveAppGroupID(void);
NSString * _Nullable CoveAppGroupContainer(void);
NSString *CoveProvisioningGroupsSummary(void);
NSString *CoveDescribeGrant(int64_t code);

/// Consume a worse_query sandbox extension. Caller must CoveRelease a handle >= 0.
int64_t CoveGrant(NSString *path);
void CoveRelease(int64_t handle);

CoveListResult *CoveListChildren(NSString *path);
uint64_t CoveBaselineInode(void);
NSArray<NSString *> * _Nullable CoveLeakRange(NSString *directory, uint64_t startInode, uint64_t endInode);
NSString * _Nullable CoveContainerIdentifier(NSString *containerPath);

void CoveWriteLog(NSString *message);
NSString *CoveReadLog(void);
void CoveClearLog(void);

NS_ASSUME_NONNULL_END
