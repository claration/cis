#import "DMGParser.h"
#import "DMGInternal.h"

#import <zlib.h>
#import <bzlib.h>
#import <compression.h>
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
    kChunkEnd     = 0xFFFFFFFF,
};

// 'koly' trailer: everything is big-endian
//   +24 dataForkOffset (8)   +216 xmlOffset (8)   +224 xmlLength (8)
// 'mish' BLKX table header (204 bytes) by 40-byte chunk descriptors
//   +8 firstSector (8)  +16 sectorCount (8)  +24 dataOffset (8)  +200 chunkCount (4)
static const size_t kMishHeaderSize = 204;
static const size_t kMishChunkSize = 40;

static const uint64_t kMaxPlistBytes = 256ull << 20;
static const uint64_t kMaxDecodedChunkBytes = 64ull << 20; // per-chunk decompressed cap
static const uint64_t kMaxPackedChunkBytes = 128ull << 20; // bounded memory: 4 decoded chunks
enum { kCacheSlots = 4 };

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
}

- (nullable instancetype)initWithContentsOfFile:(NSString *)path error:(NSError **)error {
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
    _fileSize = (uint64_t)st.st_size;

    if (![self parseContainer:error]) {
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

/// Must be called with _lock held. Returns the decoded chunk (valid until the lock is released).
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
    if (off > _fileSize || len > _fileSize - off) {
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

@end
