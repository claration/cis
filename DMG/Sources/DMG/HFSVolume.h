#import <Foundation/Foundation.h>

#import "DMGVolume.h"

NS_ASSUME_NONNULL_BEGIN

/// Read-only HFS+/HFSX filesystem.
@interface HFSVolume : NSObject <DMGVolume>

- (nullable instancetype)initWithParser:(DMGParser *)parser partitionOffset:(uint64_t)offset error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSString *volumeName;
@property (nonatomic, readonly) DMGNode *rootNode;

@end

NS_ASSUME_NONNULL_END
