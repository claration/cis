#import <Foundation/Foundation.h>

#import "DMGParser.h"
#import "DMGNode.h"

NS_ASSUME_NONNULL_BEGIN

/// A read-only filesystem found inside a disk image.
@protocol DMGVolume <NSObject>

@property (nonatomic, readonly, copy) NSString *volumeName;
@property (nonatomic, readonly, copy) NSString *filesystemType;
@property (nonatomic, readonly) DMGNode *rootNode;

/// Direct children of a folder.
- (nullable NSArray<DMGNode *> *)childrenOfNode:(DMGNode *)node error:(NSError **)error NS_SWIFT_NAME(children(of:));

/// Reads a range of a file's data.
- (nullable NSData *)readDataOfNode:(DMGNode *)node offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error
NS_SWIFT_NAME(readData(of:offset:length:));

@end

/// Finds the partition holding a supported filesystem and opens it.
@interface DMGVolumeLoader : NSObject
+ (nullable id<DMGVolume>)openVolumeWithParser:(DMGParser *)parser error:(NSError **)error NS_SWIFT_NAME(open(parser:));
@end

NS_ASSUME_NONNULL_END
