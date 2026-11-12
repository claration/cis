#import <Foundation/Foundation.h>

#import "DMGVolume.h"

NS_ASSUME_NONNULL_BEGIN

/// Read-only APFS filesystem.
@interface APFSVolume : NSObject <DMGVolume>

- (nullable instancetype)initWithParser:(DMGParser *)parser partitionOffset:(uint64_t)offset error:(NSError **)error;
- (instancetype)init NS_UNAVAILABLE;

@property (nonatomic, readonly, copy) NSString *volumeName;
@property (nonatomic, readonly) DMGNode *rootNode;
@property (nonatomic, readonly) NSUInteger volumeCount;

@end

NS_ASSUME_NONNULL_END
