#import "DMGParser.h"
#import "DMGInternal.h"

#import <zlib.h>
#import <bzlib.h>
#import <compression.h>
#import <CommonCrypto/CommonCrypto.h>
#import <fcntl.h>
#import <os/lock.h>
#import <sys/stat.h>
#import <unistd.h>

NSErrorDomain const DMGParserErrorDomain = @"DMGParserErrorDomain";

// UDIF block chunk types
enum : uint32_t {
    kChunkZero    = 0x00000000,
    kChunkRaw     = 0x00000001,
    kChunkIgnore  = 0x00000002,
    kChunkComment = 0x7FFFFFFE,
    kChunkADC     = 0x80000004,
    kChunkZlib    = 0x80000005,
    kChunkBzip2   = 0x80000006,
    kChunkLZFSE   = 0x80000007,
    kChunkLZMA    = 0x80000008,
    kChunkEnd     = 0xFFFFFFFF,
};

// 'koly' trailer: everything is big-endian
//   +24 dataForkOffset (8)   +216 xmlOffset (8)   +224 xmlLength (8)
// 'mish' BLKX table header (204 bytes) by 40-byte chunk descriptors
//   +8 firstSector (8)  +16 sectorCount (8)  +24 dataOffset (8)  +200 chunkCount (4)
static const size_t kMishHeaderSize = 204;
static const size_t kMishChunkSize = 40;

static const uint64_t kMaxPlistBytes = 256ull << 20;
static const uint64_t kMaxDecodedChunkBytes = 64ull << 20;
static const uint64_t kMaxPackedChunkBytes = 128ull << 20;
enum { kCacheSlots = 4 };

// encrcdsa
//   +0 sig(8)  +8 version  +12 ivSize  +24 keyBits  +52 blockSize  +56 dataSize(8)  +64 dataOffset(8)
//   +80 keyRecordOffset(8)  (96 in the images seen so far)
//
//   +0 kdfAlgorithm (103 = PBKDF2)  +8 iterations  +12 saltLen  +16 salt(32)
//   +48 blobIVSize  +52 blobIV(32)  +84 blobKeyBits (192 = 3DES)  +100 blobSize  +104 wrapped key blob
// The blob is 3DES-CBC wrapped under PBKDF2-HMAC-SHA1(password, salt) and holds the AES key followed by a
// 20-byte HMAC-SHA1 key. Each data block N is AES-CBC with IV = HMAC-SHA1(hmacKey, be32(N))[0..16).
enum { kEncHeaderSize = 88 };
enum { kEncRecordFixedSize = 104 };
static const uint32_t kEncKDFPBKDF2 = 103;
static const size_t kEncHMACKeySize = 20;
static const uint32_t kEncMaxIterations = 100000000;
enum { kEncMaxBlobSize = 256 };
static const uint64_t kEncSpanBytes = 1ull << 20;

typedef struct {
    uint64_t sectorStart; // absolute virtual sector
    uint64_t sectorCount;
    uint64_t fileOffset;  // absolute offset in the .dmg file
    uint64_t fileLength;
    uint32_t type;
} DMGChunk;

typedef struct {
    NSUInteger chunkIndex;
    uint8_t *buffer;
    size_t capacity;
    uint64_t lastUse;
} DMGCacheSlot;

static int compareChunks(const void *a, const void *b) {
    const DMGChunk *x = a, *y = b;
    return (x->sectorStart > y->sectorStart) - (x->sectorStart < y->sectorStart);
}

/// Apple Data Compression decoder, because Apple loves their stupid formats.
static size_t decodeADC(const uint8_t *src, size_t srcLen, uint8_t *dst, size_t dstCap) {
    size_t in = 0, out = 0;
    while (in < srcLen && out < dstCap) {
        uint8_t b = src[in++];
        if (b & 0x80) {
            size_t n = (size_t)(b & 0x7F) + 1;
            if (in + n > srcLen || out + n > dstCap) return 0;
            memcpy(dst + out, src + in, n);
            in += n; out += n;
        } else {
            size_t n, off;
            if (b & 0x40) {
                if (in + 2 > srcLen) return 0;
                n = (size_t)(b & 0x3F) + 4;
                off = ((size_t)src[in] << 8) | src[in + 1];
                in += 2;
            } else {
                if (in + 1 > srcLen) return 0;
                n = (size_t)((b & 0x3F) >> 2) + 3;
                off = ((size_t)(b & 0x03) << 8) | src[in];
                in += 1;
            }
            if (off + 1 > out || out + n > dstCap) return 0;
            for (size_t i = 0; i < n; i++, out++) dst[out] = dst[out - off - 1];
        }
    }
    return out;
}

static NSDictionary<NSNumber *, NSData *> *resourcesByID(id list) {
    NSMutableDictionary<NSNumber *, NSData *> *out = [NSMutableDictionary dictionary];
    if (![list isKindOfClass:[NSArray class]]) return out;
    for (id entry in (NSArray *)list) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        id data = entry[@"Data"], ident = entry[@"ID"];
        if (![data isKindOfClass:[NSData class]] || ![ident respondsToSelector:@selector(integerValue)]) continue;
        out[@([ident integerValue])] = data;
    }
    return out;
}

@implementation DMGParser {
    int _fd;
    uint64_t _fileSize;
    uint64_t _virtualSize;

    DMGChunk *_chunks;
    NSUInteger _chunkCount;
    NSUInteger _chunkCapacity;

    os_unfair_lock _lock; // guards everything below
    DMGCacheSlot _cache[kCacheSlots];
    uint64_t _useCounter;
    uint8_t *_scratch;    // reusable buffer for compressed bytes
    size_t _scratchCapacity;

    uint64_t _xmlOffset;  // UDIF
    uint64_t _xmlLength;

    // Encryption
    BOOL _encrypted;
    uint64_t _physicalSize;
    uint64_t _cryptDataOffset;
    uint64_t _cryptCipherLength;
    uint32_t _cryptBlockSize;
    uint8_t _aesKey[32];
    size_t _aesKeyLength;
    uint8_t _hmacKey[20];
}

- (nullable instancetype)initWithContentsOfFile:(NSString *)path error:(NSError **)error {
    return [self initWithContentsOfFile:path passwordHandler:nil error:error];
}

- (nullable instancetype)initWithContentsOfFile:(NSString *)path passwordHandler:(nullable DMGPasswordHandler)passwordHandler error:(NSError **)error {
    self = [super init];
    if (!self) return nil;

    _fd = -1;
    _lock = OS_UNFAIR_LOCK_INIT;
    for (int i = 0; i < kCacheSlots; i++) _cache[i].chunkIndex = NSNotFound;

    _fd = open(path.fileSystemRepresentation, O_RDONLY | O_CLOEXEC);
    if (_fd < 0) {
        if (error) *error = DMGMakeError(DMGParserErrorIO, @"Cannot open file: %s", strerror(errno));
        return nil;
    }
    struct stat st;
    if (fstat(_fd, &st) != 0 || !S_ISREG(st.st_mode) || st.st_size < 512) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Not a disk image file.");
        return nil;
    }
    _physicalSize = (uint64_t)st.st_size;
    _fileSize = _physicalSize;

    if (![self unlockWithPasswordHandler:passwordHandler error:error] || ![self parseContainer:error]) {
        close(_fd);
        _fd = -1;
        return nil;
    }

    return self;
}

- (void)dealloc {
    free(_chunks);
    free(_scratch);
    for (int i = 0; i < kCacheSlots; i++) free(_cache[i].buffer);
    if (_fd >= 0) close(_fd);
    memset_s(_aesKey, sizeof _aesKey, 0, sizeof _aesKey);
    memset_s(_hmacKey, sizeof _hmacKey, 0, sizeof _hmacKey);
}

#pragma mark - Encryption

- (BOOL)unlockWithPasswordHandler:(nullable DMGPasswordHandler)handler error:(NSError **)error {
    if (_physicalSize < 512) return YES;

    uint8_t h[kEncHeaderSize];
    if (![self rawPreadFully:h length:sizeof h at:0 error:error]) return NO;
    if (memcmp(h, "encrcdsa", 8) != 0) return YES;

    uint32_t version = be32(h + 8), ivSize = be32(h + 12), keyBits = be32(h + 24), blockSize = be32(h + 52);
    uint64_t dataSize = be64(h + 56), dataOffset = be64(h + 64), recordOffset = be64(h + 80);

    if (version != 2 || ivSize != 16 || (keyBits != 128 && keyBits != 256)) {
        if (error) *error = DMGMakeError(DMGParserErrorUnsupported, @"Unsupported encryption (version %u, iv %u, %u-bit key).", version, ivSize, keyBits);
        return NO;
    }
    if (blockSize == 0) blockSize = 512;
    if (blockSize < 512 || blockSize > (1u << 20) || blockSize % 16 != 0 ||
        dataOffset > _physicalSize ||
        recordOffset < kEncHeaderSize || recordOffset > dataOffset ||
        dataOffset - recordOffset < kEncRecordFixedSize) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Invalid encryption header.");
        return NO;
    }
    uint64_t available = _physicalSize - dataOffset;
    if (dataSize < 512 || dataSize > available) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Encrypted data is truncated.");
        return NO;
    }

    uint8_t r[kEncRecordFixedSize];
    if (![self rawPreadFully:r length:sizeof r at:recordOffset error:error]) return NO;

    uint32_t kdfAlg = be32(r), iterations = be32(r + 8), saltLen = be32(r + 12);
    uint32_t blobIVSize = be32(r + 48), blobKeyBits = be32(r + 84), blobSize = be32(r + 100);

    if (kdfAlg != kEncKDFPBKDF2 || blobKeyBits != 192) {
        if (error) *error = DMGMakeError(DMGParserErrorUnsupported, @"Unsupported key wrapping (kdf %u, blob key bits %u).", kdfAlg, blobKeyBits);
        return NO;
    }
    if (iterations == 0 || iterations > kEncMaxIterations || saltLen == 0 || saltLen > 32 ||
        blobIVSize < 8 || blobIVSize > 32 ||
        blobSize < 8 || blobSize > kEncMaxBlobSize || blobSize % 8 != 0 ||
        dataOffset - recordOffset - kEncRecordFixedSize < blobSize) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Invalid key record.");
        return NO;
    }

    NSMutableData *blob = [NSMutableData dataWithLength:blobSize];
    if (![self rawPreadFully:blob.mutableBytes length:blobSize at:recordOffset + kEncRecordFixedSize error:error]) return NO;

    NSError *lastError = nil;
    for (NSUInteger attempt = 0;; attempt++) {
        if (!handler) {
            if (error) *error = DMGMakeError(DMGParserErrorPasswordRequired, @"This disk image is encrypted and needs a password.");
            return NO;
        }
        NSString *password = handler(attempt, lastError);
        if (!password) {
            if (error) *error = DMGMakeError(DMGParserErrorCancelled, @"Password entry was cancelled.");
            return NO;
        }

        BOOL incorrect = NO;
        if ([self deriveKeysFromPassword:password salt:r + 16 saltLength:saltLen iterations:iterations
                                  blobIV:r + 52 blob:blob aesKeyLength:keyBits / 8 incorrect:&incorrect error:error]) {
            break;
        }
        if (!incorrect) return NO;
        lastError = DMGMakeError(DMGParserErrorIncorrectPassword, @"The password is incorrect.");
    }

    uint64_t padded = ((dataSize + blockSize - 1) / blockSize) * blockSize;
    _cryptBlockSize = blockSize;
    _cryptDataOffset = dataOffset;
    _cryptCipherLength = MIN(available, padded);
    _fileSize = dataSize;
    _encrypted = YES;
    return YES;
}

- (BOOL)deriveKeysFromPassword:(NSString *)password
                          salt:(const uint8_t *)salt
                    saltLength:(size_t)saltLen
                    iterations:(uint32_t)iterations
                        blobIV:(const uint8_t *)iv
                          blob:(NSData *)blob
                  aesKeyLength:(size_t)aesLen
                     incorrect:(BOOL *)incorrect
                         error:(NSError **)error {
    *incorrect = NO;

    NSData *pw = [password dataUsingEncoding:NSUTF8StringEncoding] ?: [NSData data];
    const char *pwBytes = pw.length ? pw.bytes : "";

    uint8_t kek[kCCKeySize3DES];
    if (CCKeyDerivationPBKDF(kCCPBKDF2, pwBytes, pw.length, salt, saltLen, kCCPRFHmacAlgSHA1,
                             iterations, kek, sizeof kek) != kCCSuccess) {
        if (error) *error = DMGMakeError(DMGParserErrorUnsupported, @"Key derivation failed.");
        return NO;
    }

    uint8_t plain[kEncMaxBlobSize + kCCBlockSize3DES];
    size_t plainLen = 0;
    CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithm3DES, kCCOptionPKCS7Padding, kek, sizeof kek, iv,
                                 blob.bytes, blob.length, plain, sizeof plain, &plainLen);
    memset_s(kek, sizeof kek, 0, sizeof kek);

    // A wrong password almost always shows up as bad padding.
    if (st != kCCSuccess || plainLen < aesLen + kEncHMACKeySize) {
        memset_s(plain, sizeof plain, 0, sizeof plain);
        *incorrect = YES;
        return NO;
    }
    memcpy(_aesKey, plain, aesLen);
    _aesKeyLength = aesLen;
    memcpy(_hmacKey, plain + aesLen, kEncHMACKeySize);
    memset_s(plain, sizeof plain, 0, sizeof plain);
    return YES;
}

- (BOOL)decryptedPreadFully:(void *)buf length:(size_t)len at:(uint64_t)off error:(NSError **)error {
    const uint64_t bs = _cryptBlockSize;
    const uint64_t maxSpanBlocks = MAX((uint64_t)1, kEncSpanBytes / bs);
    uint8_t *dst = buf;
    uint8_t *tmp = NULL;
    size_t tmpCap = 0;
    size_t done = 0;
    BOOL ok = YES;

    while (done < len && ok) {
        uint64_t pos = off + done;
        uint64_t firstBlock = pos / bs, blockOff = pos % bs;
        uint64_t needed = (blockOff + (len - done) + bs - 1) / bs;
        uint64_t blocks = MIN(needed, maxSpanBlocks);
        uint64_t cipherPos = firstBlock * bs;

        if (cipherPos >= _cryptCipherLength || firstBlock + blocks > (1ull << 32)) {
            if (error) *error = DMGMakeError(DMGParserErrorIO, @"Read beyond end of encrypted data.");
            ok = NO;
            break;
        }
        size_t cipherLen = (size_t)MIN(blocks * bs, _cryptCipherLength - cipherPos);
        if (tmpCap < cipherLen * 2) {
            free(tmp);
            tmp = malloc(cipherLen * 2);
            tmpCap = tmp ? cipherLen * 2 : 0;
            if (!tmp) {
                if (error) *error = DMGMakeError(DMGParserErrorIO, @"Out of memory.");
                ok = NO;
                break;
            }
        }
        uint8_t *cipher = tmp, *plain = tmp + cipherLen;
        if (![self rawPreadFully:cipher length:cipherLen at:_cryptDataOffset + cipherPos error:error]) {
            ok = NO;
            break;
        }

        for (size_t b = 0; (uint64_t)b * bs < cipherLen; b++) {
            size_t start = (size_t)(b * bs);
            size_t blockLen = (size_t)MIN(bs, (uint64_t)cipherLen - start);
            if (blockLen % kCCBlockSizeAES128 != 0) {
                if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Encrypted data is not block aligned.");
                ok = NO;
                break;
            }
            uint32_t n = (uint32_t)(firstBlock + b);
            uint8_t be[4] = { (uint8_t)(n >> 24), (uint8_t)(n >> 16), (uint8_t)(n >> 8), (uint8_t)n };
            uint8_t mac[CC_SHA1_DIGEST_LENGTH];
            CCHmac(kCCHmacAlgSHA1, _hmacKey, sizeof _hmacKey, be, sizeof be, mac);

            size_t moved = 0;
            CCCryptorStatus st = CCCrypt(kCCDecrypt, kCCAlgorithmAES, 0, _aesKey, _aesKeyLength, mac,
                                         cipher + start, blockLen, plain + start, blockLen, &moved);
            if (st != kCCSuccess || moved != blockLen) {
                if (error) *error = DMGMakeError(DMGParserErrorIO, @"Decryption failed.");
                ok = NO;
                break;
            }
        }
        if (!ok) break;

        if (blockOff >= cipherLen) {
            if (error) *error = DMGMakeError(DMGParserErrorIO, @"Read beyond end of encrypted data.");
            ok = NO;
            break;
        }
        size_t take = (size_t)MIN((uint64_t)(len - done), cipherLen - blockOff);
        memcpy(dst + done, plain + blockOff, take);
        done += take;
    }

    if (tmp) memset_s(tmp, tmpCap, 0, tmpCap);
    free(tmp);
    return ok;
}

#pragma mark - Parser

- (BOOL)parseContainer:(NSError **)error {
    uint8_t koly[512];
    if (![self preadFully:koly length:sizeof koly at:_fileSize - 512 error:error]) return NO;

    // pure raw disk images without a koly
    if (be32(koly) != 0x6B6F6C79) { // koly
        _chunkCapacity = 1;
        _chunks = malloc(sizeof(DMGChunk));
        _chunks[0] = (DMGChunk){
            .type = kChunkRaw,
            .sectorStart = 0,
            .sectorCount = _fileSize / 512,
            .fileOffset = 0,
            .fileLength = _fileSize
        };
        _chunkCount = 1;
        _virtualSize = _fileSize;
        return YES;
    }

    uint64_t dataForkOffset = be64(koly + 24);
    uint64_t xmlOffset = be64(koly + 216);
    uint64_t xmlLength = be64(koly + 224);
    if (xmlLength == 0 || xmlLength > kMaxPlistBytes || xmlOffset > _fileSize || xmlLength > _fileSize - xmlOffset) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Invalid XML plist range in trailer.");
        return NO;
    }

    _xmlOffset = xmlOffset;
    _xmlLength = xmlLength;

    NSMutableData *xml = [NSMutableData dataWithLength:(NSUInteger)xmlLength];
    if (![self preadFully:xml.mutableBytes length:(size_t)xmlLength at:xmlOffset error:error]) return NO;

    NSError *plistError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:xml options:NSPropertyListImmutable format:NULL error:&plistError];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Plist is invalid: %@", plistError.localizedDescription);
        return NO;
    }
    id fork = plist[@"resource-fork"];
    id blkx = [fork isKindOfClass:[NSDictionary class]] ? fork[@"blkx"] : plist[@"blkx"];
    if (![blkx isKindOfClass:[NSArray class]]) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"'blkx' array missing from plist.");
        return NO;
    }

    uint64_t maxSector = 0;
    for (id entry in (NSArray *)blkx) {
        if (![entry isKindOfClass:[NSDictionary class]]) continue;
        NSData *table = entry[@"Data"];
        if (![table isKindOfClass:[NSData class]] || table.length < kMishHeaderSize) continue;

        const uint8_t *t = table.bytes;
        if (be32(t) != 0x6D697368) continue; // mish

        uint64_t firstSector = be64(t + 8);
        uint64_t tableDataOffset = be64(t + 24);
        uint32_t count = be32(t + 200);
        if ((uint64_t)count * kMishChunkSize > table.length - kMishHeaderSize) {
            if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Truncated BLKX table.");
            return NO;
        }

        for (uint32_t i = 0; i < count; i++) {
            const uint8_t *c = t + kMishHeaderSize + (size_t)i * kMishChunkSize;
            uint32_t type = be32(c);
            if (type == kChunkComment || type == kChunkEnd) continue;

            DMGChunk ch;
            ch.type = type;
            // chunk sector numbers are relative to the partition's firstSector
            ch.sectorStart = firstSector + be64(c + 8);
            ch.sectorCount = be64(c + 16);
            // chunk data offsets are relative to the table's dataOffset and the data fork start
            ch.fileOffset = dataForkOffset + tableDataOffset + be64(c + 24);
            ch.fileLength = be64(c + 32);
            if (ch.sectorCount == 0) continue;
            if (ch.sectorStart > (1ull << 50) || ch.sectorCount > (1ull << 50) || ch.fileOffset > _fileSize) {
                if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Chunk %u has an out-of-range value.", i);
                return NO;
            }

            BOOL ok = YES;
            switch (type) {
                case kChunkZero:
                case kChunkIgnore:
                    break;
                case kChunkRaw:
                    ok = ch.fileLength >= ch.sectorCount * 512 && ch.fileLength <= _fileSize - ch.fileOffset;
                    break;
                case kChunkADC:
                case kChunkZlib:
                case kChunkBzip2:
                case kChunkLZFSE:
                case kChunkLZMA:
                    ok = ch.fileLength > 0 && ch.fileLength <= kMaxPackedChunkBytes &&
                    ch.fileLength <= _fileSize - ch.fileOffset &&
                    ch.sectorCount * 512 <= kMaxDecodedChunkBytes;
                    break;
                default:
                    if (error) *error = DMGMakeError(DMGParserErrorUnsupported, @"Unsupported chunk type 0x%08X.", type);
                    return NO;
            }
            if (!ok) {
                if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Chunk %u has invalid sizes.", i);
                return NO;
            }

            if (_chunkCount == _chunkCapacity) {
                NSUInteger newCap = _chunkCapacity ? _chunkCapacity * 2 : 1024;
                DMGChunk *grown = realloc(_chunks, newCap * sizeof(DMGChunk));
                if (!grown) {
                    if (error) *error = DMGMakeError(DMGParserErrorIO, @"Out of memory.");
                    return NO;
                }
                _chunks = grown;
                _chunkCapacity = newCap;
            }
            _chunks[_chunkCount++] = ch;
            if (ch.sectorStart + ch.sectorCount > maxSector) maxSector = ch.sectorStart + ch.sectorCount;
        }
    }

    if (_chunkCount == 0) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Image contains no data chunks.");
        return NO;
    }
    qsort(_chunks, _chunkCount, sizeof(DMGChunk), compareChunks);
    _virtualSize = maxSector * 512;
    return YES;
}

#pragma mark - Reading

@synthesize virtualSize = _virtualSize;
@synthesize encrypted = _encrypted;

- (NSUInteger)chunkIndexForSector:(uint64_t)sector {
    NSInteger low = 0, high = (NSInteger)_chunkCount - 1, best = -1;
    while (low <= high) {
        NSInteger mid = low + (high - low) / 2;
        if (_chunks[mid].sectorStart <= sector) { best = mid; low = mid + 1; }
        else high = mid - 1;
    }
    if (best >= 0 && sector < _chunks[best].sectorStart + _chunks[best].sectorCount) return (NSUInteger)best;
    return NSNotFound;
}

- (BOOL)readBytes:(void *)buffer atOffset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {
    if (offset > _virtualSize || length > _virtualSize - offset) {
        if (error) *error = DMGMakeError(DMGParserErrorOutOfRange, @"Read beyond end of virtual disk.");
        return NO;
    }
    uint8_t *dst = buffer;
    NSUInteger done = 0;
    while (done < length) {
        uint64_t pos = offset + done;
        uint64_t sector = pos / 512;
        NSUInteger inSector = (NSUInteger)(pos % 512);
        NSUInteger remaining = length - done;

        NSUInteger idx = [self chunkIndexForSector:sector];
        if (idx == NSNotFound) { // hole
            NSUInteger n = MIN(remaining, 512 - inSector);
            memset(dst + done, 0, n);
            done += n;
            continue;
        }

        const DMGChunk *c = &_chunks[idx];
        uint64_t byteInChunk = (sector - c->sectorStart) * 512 + inSector;
        uint64_t chunkBytes = c->sectorCount * 512;
        NSUInteger n = (NSUInteger)MIN((uint64_t)remaining, chunkBytes - byteInChunk);

        switch (c->type) {
            case kChunkZero:
            case kChunkIgnore:
                memset(dst + done, 0, n);
                break;
            case kChunkRaw:
                if (![self preadFully:dst + done length:n at:c->fileOffset + byteInChunk error:error]) return NO;
                break;
            default: {
                os_unfair_lock_lock(&_lock);
                const uint8_t *plain = [self decodedBufferForChunk:idx error:error];
                if (plain) memcpy(dst + done, plain + byteInChunk, n);
                os_unfair_lock_unlock(&_lock);
                if (!plain) return NO;
            }
        }
        done += n;
    }
    return YES;
}

- (nullable NSData *)readDataAtOffset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {
    NSMutableData *data = [NSMutableData dataWithLength:length];
    if (![self readBytes:data.mutableBytes atOffset:offset length:length error:error]) return nil;
    return data;
}

/// Must be called with _lock held.
- (const uint8_t *)decodedBufferForChunk:(NSUInteger)idx error:(NSError **)error {
    DMGCacheSlot *victim = &_cache[0];
    for (int i = 0; i < kCacheSlots; i++) {
        if (_cache[i].chunkIndex == idx) {
            _cache[i].lastUse = ++_useCounter;
            return _cache[i].buffer;
        }
        if (_cache[i].lastUse < victim->lastUse) victim = &_cache[i];
    }

    const DMGChunk *c = &_chunks[idx];
    size_t outSize = (size_t)(c->sectorCount * 512);
    victim->chunkIndex = NSNotFound;
    if (victim->capacity < outSize) {
        free(victim->buffer);
        victim->buffer = malloc(outSize);
        victim->capacity = victim->buffer ? outSize : 0;
    }
    if (_scratchCapacity < c->fileLength) {
        free(_scratch);
        _scratch = malloc((size_t)c->fileLength);
        _scratchCapacity = _scratch ? (size_t)c->fileLength : 0;
    }
    if (!victim->buffer || !_scratch) {
        if (error) *error = DMGMakeError(DMGParserErrorIO, @"Out of memory.");
        return NULL;
    }
    if (![self preadFully:_scratch length:(size_t)c->fileLength at:c->fileOffset error:error]) return NULL;

    size_t produced = 0;
    switch (c->type) {
        case kChunkZlib: {
            uLongf destLen = (uLongf)outSize;
            if (uncompress(victim->buffer, &destLen, _scratch, (uLong)c->fileLength) == Z_OK) produced = destLen;
            break;
        }
        case kChunkBzip2: {
            unsigned int destLen = (unsigned int)outSize;
            if (BZ2_bzBuffToBuffDecompress((char *)victim->buffer, &destLen, (char *)_scratch,
                                           (unsigned int)c->fileLength, 0, 0) == BZ_OK) produced = destLen;
            break;
        }
        case kChunkLZFSE:
            produced = compression_decode_buffer(victim->buffer, outSize, _scratch, (size_t)c->fileLength, NULL, COMPRESSION_LZFSE);
            break;
        case kChunkLZMA:
            produced = compression_decode_buffer(victim->buffer, outSize, _scratch, (size_t)c->fileLength, NULL, COMPRESSION_LZMA);
            break;
        case kChunkADC:
            produced = decodeADC(_scratch, (size_t)c->fileLength, victim->buffer, outSize);
            break;
    }
    if (produced == 0) {
        if (error) *error = DMGMakeError(DMGParserErrorDecompression, @"Failed to decompress chunk %lu (type 0x%08X).", (unsigned long)idx, c->type);
        return NULL;
    }
    if (produced < outSize) memset(victim->buffer + produced, 0, outSize - produced);

    victim->chunkIndex = idx;
    victim->lastUse = ++_useCounter;
    return victim->buffer;
}

- (BOOL)preadFully:(void *)buf length:(size_t)len at:(uint64_t)off error:(NSError **)error {
    if (!_encrypted) return [self rawPreadFully:buf length:len at:off error:error];
    if (off > _fileSize || len > _fileSize - off) {
        if (error) *error = DMGMakeError(DMGParserErrorIO, @"Read beyond end of file (file truncated?).");
        return NO;
    }
    return [self decryptedPreadFully:buf length:len at:off error:error];
}

- (BOOL)rawPreadFully:(void *)buf length:(size_t)len at:(uint64_t)off error:(NSError **)error {
    if (off > _physicalSize || len > _physicalSize - off) {
        if (error) *error = DMGMakeError(DMGParserErrorIO, @"Read beyond end of file (file truncated?).");
        return NO;
    }
    uint8_t *p = buf;
    size_t done = 0;
    while (done < len) {
        ssize_t r = pread(_fd, p + done, len - done, (off_t)(off + done));
        if (r < 0) {
            if (errno == EINTR) continue;
            if (error) *error = DMGMakeError(DMGParserErrorIO, @"Read failed: %s", strerror(errno));
            return NO;
        }
        if (r == 0) {
            if (error) *error = DMGMakeError(DMGParserErrorIO, @"Unexpected end of file.");
            return NO;
        }
        done += (size_t)r;
    }
    return YES;
}

#pragma mark - License

// 'LPic' 5000  language table: defaultRegion(2) count(2) then count x { region(2), idOffset(2), twoByte(2) }
// 'TEXT' / 'RTF ' 5000+idOffset  text
// 'STR#' 5000+idOffset           button labels
- (nullable NSArray<DMGLicense *> *)licenseAgreementsWithError:(NSError **)error {
    if (_xmlLength == 0) return @[];

    NSMutableData *xml = [NSMutableData dataWithLength:(NSUInteger)_xmlLength];
    if (![self preadFully:xml.mutableBytes length:(size_t)_xmlLength at:_xmlOffset error:error]) return nil;

    NSError *plistError = nil;
    id plist = [NSPropertyListSerialization propertyListWithData:xml options:NSPropertyListImmutable format:NULL error:&plistError];
    if (![plist isKindOfClass:[NSDictionary class]]) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Plist is invalid: %@", plistError.localizedDescription);
        return nil;
    }
    id fork = plist[@"resource-fork"];
    if (![fork isKindOfClass:[NSDictionary class]]) return @[];

    NSDictionary<NSNumber *, NSData *> *lpics = resourcesByID(fork[@"LPic"]);
    NSDictionary<NSNumber *, NSData *> *texts = resourcesByID(fork[@"TEXT"]);
    NSDictionary<NSNumber *, NSData *> *rtfs = resourcesByID(fork[@"RTF "]);
    NSDictionary<NSNumber *, NSData *> *strs = resourcesByID(fork[@"STR#"]);
    if (texts.count == 0 && rtfs.count == 0) return @[];

    NSMutableArray<NSArray<NSNumber *> *> *entries = [NSMutableArray array];
    uint16_t defaultRegion = 0;
    NSData *lpic = lpics[@5000] ?: lpics.allValues.firstObject;
    if (lpic.length >= 4) {
        const uint8_t *d = lpic.bytes;
        defaultRegion = be16(d);
        NSUInteger count = be16(d + 2);
        for (NSUInteger i = 0; i < count && 4 + 6 * (i + 1) <= lpic.length; i++) {
            const uint8_t *e = d + 4 + 6 * i;
            [entries addObject:@[@(be16(e)), @(5000 + (NSInteger)be16(e + 2))]];
        }
    }

    // treat every TEXT/RTF resource as an English license
    if (entries.count == 0) {
        NSMutableSet<NSNumber *> *ids = [NSMutableSet setWithArray:texts.allKeys];
        [ids addObjectsFromArray:rtfs.allKeys];
        for (NSNumber *rid in [ids.allObjects sortedArrayUsingSelector:@selector(compare:)]) [entries addObject:@[@0, rid]];
    }

    NSMutableArray<DMGLicense *> *licenses = [NSMutableArray array];
    BOOL placedDefault = NO;

    for (NSArray<NSNumber *> *entry in entries) {
        uint16_t region = entry[0].unsignedShortValue;
        NSNumber *rid = entry[1];
        NSData *textData = texts[rid], *rtfData = rtfs[rid];
        if (!textData && !rtfData) continue;

        DMGLicense *license = [[DMGLicense alloc] initWithRegionCode:region textData:textData rtfData:rtfData buttonData:strs[rid]];

        // default language goes first
        if (region == defaultRegion && !placedDefault) {
            [licenses insertObject:license atIndex:0];
            placedDefault = YES;
        } else {
            [licenses addObject:license];
        }
    }
    return licenses;
}

@end
