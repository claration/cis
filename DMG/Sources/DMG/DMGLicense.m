#import "DMGLicense.h"
#import "DMGInternal.h"

typedef struct {
	uint16_t code;
	const char *name;
	const char *locale;
	CFStringEncoding encoding;
} DMGRegionInfo;

static const DMGRegionInfo kRegions[] = {
	{ 0,  "English (US)",           "en",      kCFStringEncodingMacRoman },
	{ 1,  "French",                 "fr",      kCFStringEncodingMacRoman },
	{ 2,  "English (UK)",           "en-GB",   kCFStringEncodingMacRoman },
	{ 3,  "German",                 "de",      kCFStringEncodingMacRoman },
	{ 4,  "Italian",                "it",      kCFStringEncodingMacRoman },
	{ 5,  "Dutch",                  "nl",      kCFStringEncodingMacRoman },
	{ 6,  "French (Belgium)",       "fr-BE",   kCFStringEncodingMacRoman },
	{ 7,  "Swedish",                "sv",      kCFStringEncodingMacRoman },
	{ 8,  "Spanish",                "es",      kCFStringEncodingMacRoman },
	{ 9,  "Danish",                 "da",      kCFStringEncodingMacRoman },
	{ 10, "Portuguese",             "pt",      kCFStringEncodingMacRoman },
	{ 11, "French (Canada)",        "fr-CA",   kCFStringEncodingMacRoman },
	{ 12, "Norwegian",              "nb",      kCFStringEncodingMacRoman },
	{ 13, "Hebrew",                 "he",      kCFStringEncodingMacHebrew },
	{ 14, "Japanese",               "ja",      kCFStringEncodingMacJapanese },
	{ 15, "English (Australia)",    "en-AU",   kCFStringEncodingMacRoman },
	{ 16, "Arabic",                 "ar",      kCFStringEncodingMacArabic },
	{ 17, "Finnish",                "fi",      kCFStringEncodingMacRoman },
	{ 18, "French (Switzerland)",   "fr-CH",   kCFStringEncodingMacRoman },
	{ 19, "German (Switzerland)",   "de-CH",   kCFStringEncodingMacRoman },
	{ 20, "Greek",                  "el",      kCFStringEncodingMacGreek },
	{ 21, "Icelandic",              "is",      kCFStringEncodingMacIcelandic },
	{ 24, "Turkish",                "tr",      kCFStringEncodingMacTurkish },
	{ 42, "Polish",                 "pl",      kCFStringEncodingMacCentralEurRoman },
	{ 43, "Hungarian",              "hu",      kCFStringEncodingMacCentralEurRoman },
	{ 49, "Russian",                "ru",      kCFStringEncodingMacCyrillic },
	{ 51, "Korean",                 "ko",      kCFStringEncodingMacKorean },
	{ 52, "Chinese (Simplified)",   "zh-Hans", kCFStringEncodingMacChineseSimp },
	{ 53, "Chinese (Traditional)",  "zh-Hant", kCFStringEncodingMacChineseTrad },
	{ 54, "Thai",                   "th",      kCFStringEncodingMacThai },
};

static const DMGRegionInfo *regionInfo(uint16_t code) {
	for (size_t i = 0; i < sizeof kRegions / sizeof kRegions[0]; i++) {
		if (kRegions[i].code == code) return &kRegions[i];
	}
	return NULL;
}

static NSString *decodeBytes(NSData *data, NSStringEncoding macEncoding) {
	NSString *s = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
	if (!s) s = [[NSString alloc] initWithData:data encoding:macEncoding];
	if (!s) s = [[NSString alloc] initWithData:data encoding:NSMacOSRomanStringEncoding];
	return s;
}

@implementation DMGLicense

- (instancetype)initWithRegionCode:(uint16_t)regionCode
						  textData:(NSData *)textData
						   rtfData:(NSData *)rtfData
						buttonData:(NSData *)buttonData {
	self = [super init];
	if (!self) return nil;

	const DMGRegionInfo *info = regionInfo(regionCode);
	NSStringEncoding macEncoding = CFStringConvertEncodingToNSStringEncoding(info ? info->encoding : kCFStringEncodingMacRoman);

	_regionCode = regionCode;
	_languageName = info ? @(info->name) : [NSString stringWithFormat:@"Region %u", regionCode];
	_localeIdentifier = info ? @(info->locale) : @"und";

	if (textData) {
		NSString *s = decodeBytes(textData, macEncoding);
		s = [s stringByReplacingOccurrencesOfString:@"\r\n" withString:@"\n"];
		_text = [s stringByReplacingOccurrencesOfString:@"\r" withString:@"\n"];
	}

	_rtfData = [rtfData copy];

	NSMutableArray<NSString *> *labels = [NSMutableArray array];
	if (buttonData.length >= 2) {
		const uint8_t *d = buttonData.bytes;
		NSUInteger count = be16(d), pos = 2;
		for (NSUInteger i = 0; i < count && pos < buttonData.length; i++) {
			NSUInteger len = d[pos++];
			if (pos + len > buttonData.length) break;
			NSString *label = decodeBytes([NSData dataWithBytes:d + pos length:len], macEncoding);
			[labels addObject:label ?: @""];
			pos += len;
		}
	}

	_buttonLabels = labels;
	return self;
}

@end
