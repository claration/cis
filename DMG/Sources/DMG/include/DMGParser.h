#import <Foundation/Foundation.h>

#import "DMGLicense.h"

NS_ASSUME_NONNULL_BEGIN

FOUNDATION_EXPORT NSErrorDomain const DMGParserErrorDomain;

typedef NS_ERROR_ENUM(DMGParserErrorDomain, DMGParserError) {
    DMGParserErrorIO = 1,
    DMGParserErrorInvalidContainer,
    DMGParserErrorUnsupported,
    DMGParserErrorOutOfRange,
    DMGParserErrorDecompression,
    DMGParserErrorPasswordRequired,
    DMGParserErrorIncorrectPassword,
    DMGParserErrorCancelled,
};

typedef NSString * _Nullable (^DMGPasswordHandler)(NSUInteger attempt, NSError * _Nullable previousError);

/// Takes in a DMG path and reads its contents. Only the chunk table is held in memory.
@interface DMGParser : NSObject

/// Fails with `DMGParserErrorPasswordRequired` if the image is encrypted.
- (nullable instancetype)initWithContentsOfFile:(NSString *)path error:(NSError **)error;

/// Opens a possibly password-protected image. `passwordHandler` is only invoked for encrypted images.
- (nullable instancetype)initWithContentsOfFile:(NSString *)path
                                passwordHandler:(nullable DMGPasswordHandler)passwordHandler
                                          error:(NSError **)error NS_DESIGNATED_INITIALIZER;
- (instancetype)init NS_UNAVAILABLE;

/// Whether the image was password protected (and has been unlocked).
@property (nonatomic, readonly, getter=isEncrypted) BOOL encrypted;

/// The size of the virtual disk in bytes.
@property (nonatomic, readonly) uint64_t virtualSize;

/// Reads `length` bytes of the virtual disk starting at `offset`.
/// Holes in the image read back as zeros.
- (BOOL)readBytes:(void *)buffer atOffset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error;
- (nullable NSData *)readDataAtOffset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error;

/// The DMG's software agreement.
- (nullable NSArray<DMGLicense *> *)licenseAgreementsWithError:(NSError **)error NS_SWIFT_NAME(licenseAgreements());

@end

NS_ASSUME_NONNULL_END
