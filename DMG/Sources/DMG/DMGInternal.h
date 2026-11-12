#import "DMGParser.h"

#import <Foundation/Foundation.h>

static inline uint16_t be16(const uint8_t *p) {
    return (uint16_t)((p[0] << 8) | p[1]);
}

static inline uint32_t be32(const uint8_t *p) {
    return ((uint32_t)p[0] << 24) | ((uint32_t)p[1] << 16) |
           ((uint32_t)p[2] << 8) | (uint32_t)p[3];
}

static inline uint64_t be64(const uint8_t *p) {
    return ((uint64_t)be32(p) << 32) | be32(p + 4);
}

static inline uint16_t le16(const uint8_t *p) {
    return (uint16_t)(p[0] | (p[1] << 8));
}

static inline uint32_t le32(const uint8_t *p) {
    return ((uint32_t)p[3] << 24) | ((uint32_t)p[2] << 16) |
           ((uint32_t)p[1] << 8) | (uint32_t)p[0];
}

static inline uint64_t le64(const uint8_t *p) {
    return ((uint64_t)le32(p + 4) << 32) | le32(p);
}

NS_FORMAT_FUNCTION(2, 3)
static inline NSError *DMGMakeError(DMGParserError code, NSString *format,
                                    ...) {
      va_list args;
      va_start(args, format);
      NSString *message = [[NSString alloc] initWithFormat:format arguments:args];
      va_end(args);
      return [NSError errorWithDomain:DMGParserErrorDomain
                                 code:code
                             userInfo:@{NSLocalizedDescriptionKey : message}];
}
