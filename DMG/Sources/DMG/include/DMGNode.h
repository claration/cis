#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

typedef NS_ENUM(NSInteger, DMGNodeKind) {
    DMGNodeKindFile,
    DMGNodeKindDirectory,
    DMGNodeKindSymlink,
};

/// DMG node entry.
@interface DMGNode : NSObject

@property (nonatomic, readonly, copy) NSString *name;
@property (nonatomic, readonly) uint64_t identifier;        // HFS+ CNID / APFS inode ID
@property (nonatomic, readonly) uint64_t parentIdentifier;
@property (nonatomic, readonly) DMGNodeKind kind;
@property (nonatomic, readonly) uint16_t permissions;       // POSIX mode bits          (0 for unknown)
@property (nonatomic, readonly) uint64_t size;              // data fork logical size   (0 for folders)
@property (nonatomic, readonly) uint32_t childCount;        // folder valence           (0 for files)
@property (nonatomic, readonly, nullable) NSDate *modificationDate;
@property (nonatomic, readonly, nullable) NSData *forkDescriptor;

- (instancetype)initWithName:(NSString *)name
                  identifier:(uint64_t)identifier
            parentIdentifier:(uint64_t)parentIdentifier
                        kind:(DMGNodeKind)kind
                 permissions:(uint16_t)permissions
                        size:(uint64_t)size
                  childCount:(uint32_t)childCount
            modificationDate:(nullable NSDate *)modificationDate
              forkDescriptor:(nullable NSData *)forkDescriptor NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
