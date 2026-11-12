#import "DMGVolume.h"
#import "DMGInternal.h"
#import "HFSVolume.h"
#import "APFSVolume.h"

/// Byte offsets where a volume might start.
static NSArray<NSNumber *> *candidatePartitionOffsets(DMGParser *parser) {
    NSMutableArray<NSNumber *> *offsets = [NSMutableArray arrayWithObject:@0];
    uint8_t block[512];

    if ([parser readBytes:block atOffset:512 length:512 error:NULL] && memcmp(block, "EFI PART", 8) == 0) {
        uint64_t tableLBA = le64(block + 72);
        uint32_t count = le32(block + 80), entrySize = le32(block + 84);
        if (tableLBA < (1ull << 40) && count > 0 && count <= 256 && entrySize >= 128 && entrySize <= 1024) {
            NSMutableData *table = [NSMutableData dataWithLength:(NSUInteger)count * entrySize];
            if ([parser readBytes:table.mutableBytes atOffset:tableLBA * 512 length:table.length error:NULL]) {
                for (uint32_t i = 0; i < count; i++) {
                    const uint8_t *e = (const uint8_t *)table.bytes + (size_t)i * entrySize;
                    BOOL used = NO;
                    for (int b = 0; b < 16; b++) used |= (e[b] != 0);
                    uint64_t firstLBA = le64(e + 32);
                    if (used && firstLBA > 0 && firstLBA < (1ull << 40)) [offsets addObject:@(firstLBA * 512)];
                }
            }
        }
    }

    if ([parser readBytes:block atOffset:0 length:512 error:NULL] && be16(block) == 0x4552) { // ER
        uint32_t bs = be16(block + 2);
        if (bs < 512 || bs > 4096) bs = 512;
        if ([parser readBytes:block atOffset:bs length:512 error:NULL] && be16(block) == 0x504D) { // PM
            uint32_t count = MIN(be32(block + 4), 64u);
            for (uint32_t i = 0; i < count; i++) {
                if (![parser readBytes:block atOffset:(uint64_t)(i + 1) * bs length:512 error:NULL] || be16(block) != 0x504D) break;
                [offsets addObject:@((uint64_t)be32(block + 8) * bs)];
            }
        }
    }
    return offsets;
}

@implementation DMGVolumeLoader

+ (nullable id<DMGVolume>)openVolumeWithParser:(DMGParser *)parser error:(NSError **)error {
    NSError *firstError = nil;

    for (NSNumber *candidate in candidatePartitionOffsets(parser)) {
        uint64_t offset = candidate.unsignedLongLongValue;

        NSError *e = nil;
        id<DMGVolume> volume = [[HFSVolume alloc] initWithParser:parser partitionOffset:offset error:&e];
        if (volume) return volume;
        if (e && !firstError) firstError = e;

        e = nil;
        volume = [[APFSVolume alloc] initWithParser:parser partitionOffset:offset error:&e];
        if (volume) return volume;
        if (e && !firstError) firstError = e;
    }

    if (error) {
        *error = firstError ?: DMGMakeError(DMGParserErrorUnsupported, @"No HFS+ or APFS volume found in this image.");
    }

    return nil;
}

@end
