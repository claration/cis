#import <Foundation/Foundation.h>

NS_ASSUME_NONNULL_BEGIN

@interface DMGLicense : NSObject

@property (nonatomic, readonly) uint16_t regionCode;
@property (nonatomic, readonly, copy) NSString *languageName;     // "English (US)"
@property (nonatomic, readonly, copy) NSString *localeIdentifier; // "en", "fr", "zh-Hans", "und"

@property (nonatomic, readonly, copy, nullable) NSString *text;
@property (nonatomic, readonly, copy, nullable) NSData *rtfData;
@property (nonatomic, readonly, copy) NSArray<NSString *> *buttonLabels;

- (instancetype)initWithRegionCode:(uint16_t)regionCode
						  textData:(nullable NSData *)textData
						   rtfData:(nullable NSData *)rtfData
						buttonData:(nullable NSData *)buttonData NS_DESIGNATED_INITIALIZER;

- (instancetype)init NS_UNAVAILABLE;

@end

NS_ASSUME_NONNULL_END
