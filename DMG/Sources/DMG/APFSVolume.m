#import "APFSVolume.h"
#import "DMGInternal.h"

// All APFS on-disk integers are little-endian.
//
// Object header (32 bytes): +0 cksum(8) +8 oid(8) +16 xid(8) +24 type(4) +28 subtype(4)
// nx_superblock: +32 magic 'NXSB', +36 block_size, +40 block_count, +104 xp_desc_blocks, +112 xp_desc_base,
//                +160 omap_oid, +180 max_file_systems, +184 fs_oid[100]
// apfs_superblock: +32 magic 'APSB', +56 incompat features, +128 omap_oid, +136 root_tree_oid,
//                  +264 fs_flags, +704 volname[256]
// omap_phys: +48 tree_oid
// btree node: +32 flags, +34 level, +36 nkeys, +40 table_space(off,len), +56 data; root nodes end with a 40-byte btree_info

static const uint32_t kNXMagic = 0x4253584E;      // 'NXSB'
static const uint32_t kAPSBMagic = 0x42535041;    // 'APSB'
static const uint64_t kRootDirID = 2;
static const uint64_t kPrivateDirID = 3;          // "private-dir": hidden bookkeeping folder
static const uint64_t kIDMask = 0x0FFFFFFFFFFFFFFFull;

enum { kRecInode = 3, kRecXattr = 4, kRecFileExtent = 8, kRecDirRec = 9 };
enum { kDTDir = 4, kDTReg = 8, kDTLnk = 10 };
enum { kBTNodeRoot = 0x1, kBTNodeFixed = 0x4 };

typedef int  (^APFSKeyCompare)(const uint8_t *key, uint32_t keyLen); // -1: key before range, 0: in range, 1: after
typedef BOOL (^APFSVisitor)(const uint8_t *key, uint32_t keyLen, const uint8_t *val, uint32_t valLen);

@interface APFSDirEntry : NSObject
@property (nonatomic, copy) NSString *name;
@property (nonatomic) uint64_t fileID;
@property (nonatomic) uint16_t type;
@end
@implementation APFSDirEntry
@end

#pragma mark - Helpers

static BOOL isPowerOfTwo(uint32_t v) { return v && !(v & (v - 1)); }

/// Fletcher-64 over everything after the 8-byte checksum field.
static uint64_t objectChecksum(const uint8_t *block, size_t size) {
    uint64_t sum1 = 0, sum2 = 0;
    for (size_t i = 8; i + 4 <= size; i += 4) {
        sum1 += le32(block + i);
        sum2 += sum1;
    }
    uint64_t c1 = 0xFFFFFFFFull - ((sum1 + sum2) % 0xFFFFFFFFull);
    uint64_t c2 = 0xFFFFFFFFull - ((sum1 + c1) % 0xFFFFFFFFull);
    return (c2 << 32) | c1;
}

static BOOL isValidSuperblock(const uint8_t *b, uint32_t blockSize) {
    return (le32(b + 24) & 0xFFFF) == 1 && le32(b + 32) == kNXMagic && le64(b) == objectChecksum(b, blockSize);
}

typedef struct {
    const uint8_t *base;
    uint32_t blockSize, nkeys, keyBaseOff, valEndOff;
    uint16_t flags, level;
    const uint8_t *toc;
    BOOL fixed;
} APFSNode;

static BOOL nodeInit(APFSNode *n, const uint8_t *b, uint32_t blockSize) {
    uint32_t type = le32(b + 24) & 0xFFFF;
    if (type != 2 && type != 3) return NO; // OBJECT_TYPE_BTREE / BTREE_NODE
    n->base = b;
    n->blockSize = blockSize;
    n->flags = le16(b + 32);
    n->level = le16(b + 34);
    n->nkeys = le32(b + 36);
    uint32_t tocOff = le16(b + 40), tocLen = le16(b + 42);
    n->fixed = (n->flags & kBTNodeFixed) != 0;
    uint32_t entrySize = n->fixed ? 4 : 8;
    n->keyBaseOff = 56 + tocOff + tocLen;
    n->valEndOff = blockSize - ((n->flags & kBTNodeRoot) ? 40 : 0);
    if ((uint64_t)n->nkeys * entrySize > tocLen || n->keyBaseOff > n->valEndOff) return NO;
    n->toc = b + 56 + tocOff;
    return YES;
}

/// Key offsets are relative to the end of the table of contents; value offsets count backwards from the end of the value area.
static BOOL nodeEntry(const APFSNode *n,
                      uint32_t i,
                      uint32_t fixedKeySize,
                      uint32_t fixedValSize,
                      const uint8_t **key,
                      uint32_t *keyLen,
                      const uint8_t **val,
                      uint32_t *valLen)
{
    uint32_t ko, kl, vo, vl;
    if (n->fixed) {
        ko = le16(n->toc + 4u * i);
        vo = le16(n->toc + 4u * i + 2);
        kl = fixedKeySize;
        vl = fixedValSize;
    } else {
        ko = le16(n->toc + 8u * i);
        kl = le16(n->toc + 8u * i + 2);
        vo = le16(n->toc + 8u * i + 4);
        vl = le16(n->toc + 8u * i + 6);
    }
    if ((uint64_t)n->keyBaseOff + ko + kl > n->valEndOff) return NO;
    *key = n->base + n->keyBaseOff + ko;
    *keyLen = kl;
    if (vl == 0) {
        *val = n->base + n->valEndOff;
        *valLen = 0;
        return YES;
    }
    if (vo > n->valEndOff || vl > vo || n->valEndOff - vo < n->keyBaseOff) return NO;
    *val = n->base + n->valEndOff - vo;
    *valLen = vl;
    return YES;
}

static int compareIDAndType(const uint8_t *key, uint32_t keyLen, uint64_t ident, uint8_t type) {
    if (keyLen < 8) return -1;
    uint64_t v = le64(key);
    uint64_t kid = v & kIDMask;
    uint8_t kt = (uint8_t)(v >> 60);
    if (kid != ident) return kid < ident ? -1 : 1;
    if (kt != type) return kt < type ? -1 : 1;
    return 0;
}

/// Size of the file's data stream, stored in the inode's INO_EXT_TYPE_DSTREAM extended field.
static uint64_t inodeDataSize(const uint8_t *v, size_t len) {
    if (len < 96) return 0;
    uint16_t count = le16(v + 92);
    size_t pos = 96 + 4u * count; // descriptors (type, flags, size) are followed by their 8-byte-aligned data
    if (pos > len) return 0;
    for (uint16_t i = 0; i < count; i++) {
        const uint8_t *d = v + 96 + 4u * i;
        uint16_t size = le16(d + 2);
        if (pos + size > len) return 0;
        if (d[0] == 8 && size >= 8) return le64(v + pos);
        pos += (size + 7u) & ~7u;
    }
    return 0;
}

/// Directory record keys come hashed (name_len_and_hash, name at +12) or plain (name_len, name at +10);
/// the key length tells them apart unambiguously.
static APFSDirEntry *parseDirRecord(const uint8_t *key, uint32_t keyLen, const uint8_t *val, uint32_t valLen) {
    if (valLen < 18 || keyLen < 10) return nil;
    const uint8_t *nameBytes = NULL;
    uint32_t nameLen = 0;
    if (keyLen >= 12 && 12 + (le32(key + 8) & 0x3FF) == keyLen) {
        nameLen = le32(key + 8) & 0x3FF;
        nameBytes = key + 12;
    } else if (10 + (uint32_t)le16(key + 8) == keyLen) {
        nameLen = le16(key + 8);
        nameBytes = key + 10;
    } else {
        return nil;
    }
    if (nameLen > 0 && nameBytes[nameLen - 1] == 0) nameLen--;
    if (nameLen == 0) return nil;
    NSString *name = [[NSString alloc] initWithBytes:nameBytes length:nameLen encoding:NSUTF8StringEncoding];
    if (!name) return nil;

    APFSDirEntry *entry = [APFSDirEntry new];
    entry.name = name;
    entry.fileID = le64(val) & kIDMask;
    entry.type = le16(val + 16) & 0xF;
    return entry;
}

#define APFS_CORRUPT(err) do { if (err) *(err) = DMGMakeError(DMGParserErrorInvalidContainer, @"Corrupt APFS B-tree."); return -1; } while (0)

#pragma mark - APFSVolume

@implementation APFSVolume {
    DMGParser *_parser;
    uint64_t _partitionOffset;
    uint32_t _blockSize;
    uint64_t _blockCount;
    uint64_t _xid;                   // transaction ID of the checkpoint we read
    uint64_t _containerOmapRoot;     // physical block of the container object-map B-tree root
    uint64_t _volumeOmapRoot;
    uint64_t _fsRootPaddr;           // physical block of the filesystem tree root
    NSCache<NSNumber *, NSData *> *_blockCache;   // bounded (~4 MB) cache of recently read tree nodes
}

- (nullable instancetype)initWithParser:(DMGParser *)parser partitionOffset:(uint64_t)offset error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    _parser = parser;
    _partitionOffset = offset;
    NSError *openError = nil;
    if ([self openContainer:&openError]) return self;
    if (error) *error = openError; // nil means "no APFS container here"
    return nil;
}

- (NSString *)filesystemType { return @"APFS"; }

#pragma mark Block access

- (nullable NSData *)readBlockUncached:(uint64_t)paddr error:(NSError **)error {
    if (paddr >= _blockCount) {
        if (error) *error = DMGMakeError(DMGParserErrorOutOfRange, @"APFS block %llu is outside the container.", paddr);
        return nil;
    }
    NSMutableData *data = [NSMutableData dataWithLength:_blockSize];
    if (![_parser readBytes:data.mutableBytes atOffset:_partitionOffset + paddr * _blockSize length:_blockSize error:error]) return nil;
    return data;
}

- (nullable NSData *)blockAtAddress:(uint64_t)paddr error:(NSError **)error {
    NSNumber *key = @(paddr);
    NSData *hit = [_blockCache objectForKey:key];
    if (hit) return hit;
    NSData *block = [self readBlockUncached:paddr error:error];
    if (block) [_blockCache setObject:block forKey:key];
    return block;
}

#pragma mark Opening

/// YES on success. NO with *error == nil means "not APFS"; NO with *error set means damaged/unsupported.
- (BOOL)openContainer:(NSError **)error {
    uint8_t head[1024];
    if (![_parser readBytes:head atOffset:_partitionOffset length:sizeof head error:NULL]) return NO;
    if (le32(head + 32) != kNXMagic) return NO;

    uint32_t blockSize = le32(head + 36);
    uint64_t blockCount = le64(head + 40);
    if (!isPowerOfTwo(blockSize) || blockSize < 4096 || blockSize > 65536 || blockCount == 0 || blockCount > (1ull << 40)) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Invalid APFS container geometry.");
        return NO;
    }
    _blockSize = blockSize;
    _blockCount = blockCount;
    _blockCache = [NSCache new];
    _blockCache.countLimit = MAX(16u, (4u << 20) / blockSize);

    // Block 0 may be stale: the newest valid superblock lives in the checkpoint descriptor area.
    NSData *best = nil;
    uint64_t bestXid = 0;
    NSData *block0 = [self readBlockUncached:0 error:NULL];
    if (block0 && isValidSuperblock(block0.bytes, blockSize)) {
        best = block0;
        bestXid = le64((const uint8_t *)block0.bytes + 16);
    }
    uint32_t descBlocks = le32(head + 104);
    uint64_t descBase = le64(head + 112);
    if (!(descBase >> 63) && !(descBlocks >> 31)) { // high bit set would mean a non-contiguous (tree) area
        descBlocks = MIN(descBlocks, 16384u);
        for (uint32_t i = 0; i < descBlocks; i++) {
            @autoreleasepool {
                NSData *b = [self readBlockUncached:descBase + i error:NULL];
                if (!b) continue;
                const uint8_t *p = b.bytes;
                uint64_t xid = le64(p + 16);
                if (isValidSuperblock(p, blockSize) && (!best || xid > bestXid)) { best = b; bestXid = xid; }
            }
        }
    }
    if (!best) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"No valid APFS container superblock.");
        return NO;
    }
    const uint8_t *sb = best.bytes;
    _xid = bestXid;

    NSData *omap = [self blockAtAddress:le64(sb + 160) error:error];
    if (!omap) return NO;
    _containerOmapRoot = le64((const uint8_t *)omap.bytes + 48);

    // first usable volume
    uint32_t maxFS = MIN(le32(sb + 180), 100u);
    NSData *volumeBlock = nil;
    NSError *firstProblem = nil;
    NSUInteger volumeCount = 0;
    for (uint32_t i = 0; i < maxFS; i++) {
        uint64_t oid = le64(sb + 184 + 8u * i);
        if (oid == 0) continue;
        volumeCount++;
        if (volumeBlock) continue;

        NSError *e = nil;
        uint64_t paddr = [self omapLookupRoot:_containerOmapRoot oid:oid error:&e];
        NSData *vb = paddr ? [self blockAtAddress:paddr error:&e] : nil;
        if (!vb || le32((const uint8_t *)vb.bytes + 32) != kAPSBMagic) {
            if (!firstProblem) firstProblem = e ?: DMGMakeError(DMGParserErrorInvalidContainer, @"Bad APFS volume superblock.");
            continue;
        }
        if (!(le64((const uint8_t *)vb.bytes + 264) & 1)) { // APFS_FS_UNENCRYPTED
            if (!firstProblem) firstProblem = DMGMakeError(DMGParserErrorUnsupported, @"The APFS volume is encrypted.");
            continue;
        }
        volumeBlock = vb;
    }
    _volumeCount = volumeCount;
    if (!volumeBlock) {
        if (error) *error = firstProblem ?: DMGMakeError(DMGParserErrorUnsupported, @"The APFS container has no volumes.");
        return NO;
    }

    const uint8_t *vb = volumeBlock.bytes;
    NSData *volOmap = [self blockAtAddress:le64(vb + 128) error:error];
    if (!volOmap) return NO;
    _volumeOmapRoot = le64((const uint8_t *)volOmap.bytes + 48);
    _fsRootPaddr = [self omapLookupRoot:_volumeOmapRoot oid:le64(vb + 136) error:error];
    if (!_fsRootPaddr) return NO;

    NSString *name = [[NSString alloc] initWithBytes:vb + 704 length:strnlen((const char *)vb + 704, 256) encoding:NSUTF8StringEncoding];
    _volumeName = name.length ? name : @"Untitled";
    _rootNode = [[DMGNode alloc] initWithName:_volumeName identifier:kRootDirID parentIdentifier:1
                                         kind:DMGNodeKindDirectory permissions:0755 size:0 childCount:0
                             modificationDate:nil forkDescriptor:nil];
    return YES;
}

#pragma mark Object map

/// Maps a virtual object ID to a physical block (latest mapping at or before our checkpoint). Returns 0 on failure.
- (uint64_t)omapLookupRoot:(uint64_t)root oid:(uint64_t)oid error:(NSError **)error {
    uint64_t nodeAddr = root;

    for (int depth = 0; depth < 16; depth++) {
        NSData *block = [self blockAtAddress:nodeAddr error:error];
        if (!block) return 0;
        APFSNode n;
        if (!nodeInit(&n, block.bytes, _blockSize)) break;

        const uint8_t *key, *val;
        uint32_t kl, vl;
        uint32_t valSize = (n.level == 0) ? 16 : 8; // leaf: omap_val_t, index: child block address
        int pick = -1;
        BOOL bad = NO;
        // keys are (oid, xid), ascending; take the last one <= (oid, _xid)
        for (uint32_t i = 0; i < n.nkeys; i++) {
            if (!nodeEntry(&n, i, 16, valSize, &key, &kl, &val, &vl) || kl < 16) { bad = YES; break; }
            uint64_t ko = le64(key), kx = le64(key + 8);
            if (ko < oid || (ko == oid && kx <= _xid)) pick = (int)i; else break;
        }

        if (bad) break;

        if (pick < 0 || !nodeEntry(&n, (uint32_t)pick, 16, valSize, &key, &kl, &val, &vl)) {
            if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Object %llu not found in object map.", oid);
            return 0;
        }

        if (n.level == 0) {
            if (le64(key) != oid || vl < 16 || (le32(val) & 1 /* OMAP_VAL_DELETED */)) {
                if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Object %llu not found in object map.", oid);
                return 0;
            }
            return le64(val + 8);
        }

        if (vl < 8) break;
        nodeAddr = le64(val);
    }

    if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Corrupt APFS object map.");
    return 0;
}

#pragma mark Tree

/// In-order range scan. APFS leaves have no sibling links, so we recurse; `compare` classifies each key as
/// before / inside / after the wanted range, which lets us skip every subtree that can't contain matches.
/// Returns 0 to continue, 1 when finished (visitor stopped or range passed), and -1 on error.
- (int)scanPaddr:(uint64_t)paddr
           depth:(int)depth
         compare:(APFSKeyCompare)compare
           visit:(APFSVisitor)visit
           error:(NSError **)error
{
    if (depth > 16) APFS_CORRUPT(error);
    NSData *block = [self blockAtAddress:paddr error:error];
    if (!block) return -1;
    APFSNode n;
    if (!nodeInit(&n, block.bytes, _blockSize)) APFS_CORRUPT(error);

    const uint8_t *key, *val;
    uint32_t kl, vl;

    if (n.level == 0) {
        for (uint32_t i = 0; i < n.nkeys; i++) {
            if (!nodeEntry(&n, i, 0, 0, &key, &kl, &val, &vl)) APFS_CORRUPT(error);
            int c = compare(key, kl);
            if (c < 0) continue;
            if (c > 0) return 1;
            if (!visit(key, kl, val, vl)) return 1;
        }
        return 0;
    }

    for (uint32_t i = 0; i < n.nkeys; i++) {
        if (!nodeEntry(&n, i, 0, 0, &key, &kl, &val, &vl) || vl < 8) APFS_CORRUPT(error);
        if (compare(key, kl) > 0) return 1; // this child starts after the range
        uint64_t childOid = le64(val);

        // this child ends before the next child's first key
        if (i + 1 < n.nkeys) {
            const uint8_t *k2, *v2;
            uint32_t kl2, vl2;
            if (!nodeEntry(&n, i + 1, 0, 0, &k2, &kl2, &v2, &vl2)) APFS_CORRUPT(error);
            if (compare(k2, kl2) < 0) continue; // whole child is before the range
        }

        uint64_t childAddr = [self omapLookupRoot:_volumeOmapRoot oid:childOid error:error];
        if (!childAddr) return -1;

        int r = [self scanPaddr:childAddr depth:depth + 1 compare:compare visit:visit error:error];
        if (r != 0) return r;
    }
    return 0;
}

- (BOOL)scanFSWithCompare:(APFSKeyCompare)compare visit:(APFSVisitor)visit error:(NSError **)error {
    return [self scanPaddr:_fsRootPaddr depth:0 compare:compare visit:visit error:error] >= 0;
}

- (nullable NSData *)inodeValueForID:(uint64_t)ident error:(NSError **)error {
    __block NSData *found = nil;
    BOOL ok = [self scanFSWithCompare:^int(const uint8_t *key, uint32_t keyLen) {
        return compareIDAndType(key, keyLen, ident, kRecInode);
    } visit:^BOOL(const uint8_t *key, uint32_t keyLen, const uint8_t *val, uint32_t valLen) {
        found = [NSData dataWithBytes:val length:valLen];
        return NO;
    } error:error];
    return ok ? found : nil;
}

#pragma mark DMGVolume

- (nullable NSArray<DMGNode *> *)childrenOfNode:(DMGNode *)parent error:(NSError **)error {
    if (parent.kind != DMGNodeKindDirectory) return @[];
    const uint64_t parentID = parent.identifier;

    // collect (name, id, type) from the directory records. They carry no sizes or dates.
    NSMutableArray<APFSDirEntry *> *entries = [NSMutableArray arrayWithCapacity:MIN(parent.childCount, 4096u)];
    BOOL ok = [self scanFSWithCompare:^int(const uint8_t *key, uint32_t keyLen) {
        return compareIDAndType(key, keyLen, parentID, kRecDirRec);
    } visit:^BOOL(const uint8_t *key, uint32_t keyLen, const uint8_t *val, uint32_t valLen) {
        APFSDirEntry *e = parseDirRecord(key, keyLen, val, valLen);
        if (e) [entries addObject:e];
        return YES;
    } error:error];
    if (!ok) return nil;

    // one inode lookup per child (tree nodes are served from the small block cache).
    NSMutableArray<DMGNode *> *nodes = [NSMutableArray arrayWithCapacity:entries.count];
    for (APFSDirEntry *e in entries) {
        if (e.fileID == kPrivateDirID) continue;
        @autoreleasepool {
            NSError *inodeError = nil;
            NSData *inode = [self inodeValueForID:e.fileID error:&inodeError];
            if (!inode && inodeError) { if (error) *error = inodeError; return nil; }

            DMGNodeKind kind = e.type == kDTDir ? DMGNodeKindDirectory : (e.type == kDTLnk ? DMGNodeKindSymlink : DMGNodeKindFile);
            uint64_t privateID = e.fileID, size = 0;
            uint32_t childCount = 0;
            uint16_t permissions = 0;
            NSDate *modified = nil;
            if (inode.length >= 92) {
                const uint8_t *v = inode.bytes;
                privateID = le64(v + 8);
                permissions = le16(v + 80) & 07777;
                uint64_t modNs = le64(v + 24);
                if (modNs) modified = [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)modNs / 1e9];
                if (kind == DMGNodeKindDirectory) childCount = le32(v + 56);
                else size = inodeDataSize(v, inode.length);
            }
            NSData *descriptor = nil;
            if (kind != DMGNodeKindDirectory) {
                uint8_t raw[8];
                for (int i = 0; i < 8; i++) raw[i] = (uint8_t)(privateID >> (8 * i));
                descriptor = [NSData dataWithBytes:raw length:8];
            }
            [nodes addObject:[[DMGNode alloc] initWithName:e.name identifier:e.fileID parentIdentifier:parentID
                                                      kind:kind permissions:permissions size:size childCount:childCount
                                          modificationDate:modified forkDescriptor:descriptor]];
        }
    }

    // directory recrds are ordered by name hash
    [nodes sortUsingComparator:^NSComparisonResult(DMGNode *a, DMGNode *b) {
        return [a.name localizedStandardCompare:b.name];
    }];

    return nodes;
}

/// Reads from a data stream identified by its private ID (the key of its file-extent records).
- (nullable NSData *)readStream:(uint64_t)privateID size:(uint64_t)size offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {
    if (offset >= size || length == 0) return [NSData data];
    length = (NSUInteger)MIN((uint64_t)length, size - offset);
    const uint64_t end = offset + length;

    // sparse extents stay zero
    NSMutableData *out = [NSMutableData dataWithLength:length];
    uint8_t *dst = out.mutableBytes;
    __block NSError *readError = nil;

    // (id, type 8, logical_addr) length(56 bits)+flags, phys_block_num, crypto_id.
    BOOL ok = [self scanFSWithCompare:^int(const uint8_t *key, uint32_t keyLen) {
        return compareIDAndType(key, keyLen, privateID, kRecFileExtent);
    } visit:^BOOL(const uint8_t *key, uint32_t keyLen, const uint8_t *val, uint32_t valLen) {
        if (keyLen < 16 || valLen < 24) return YES;
        uint64_t logical = le64(key + 8);
        if (logical >= end) return NO;
        uint64_t extLen = le64(val) & 0x00FFFFFFFFFFFFFFull;
        uint64_t physBlock = le64(val + 8);
        uint64_t start = MAX(logical, offset), stop = MIN(logical + extLen, end);
        if (start >= stop || physBlock == 0) return YES;
        uint64_t physical = self->_partitionOffset + physBlock * self->_blockSize + (start - logical);
        if (![self->_parser readBytes:dst + (start - offset) atOffset:physical length:(NSUInteger)(stop - start) error:&readError]) return NO;
        return YES;
    } error:error];
    if (readError) { if (error) *error = readError; return nil; }
    return ok ? out : nil;
}

/// APFS stores a symlink's target in the "com.apple.fs.symlink" extended attribute (key: id, type 4, name).
- (nullable NSData *)readSymlinkTargetOfNode:(DMGNode *)node error:(NSError **)error {
    const uint64_t ident = node.identifier;
    // name_len in the key includes the NUL
    static const char kName[] = "com.apple.fs.symlink";
    __block NSData *target = nil;
    __block uint64_t streamID = 0, streamSize = 0;

    BOOL ok = [self scanFSWithCompare:^int(const uint8_t *key, uint32_t keyLen) {
        return compareIDAndType(key, keyLen, ident, kRecXattr);
    } visit:^BOOL(const uint8_t *key, uint32_t keyLen, const uint8_t *val, uint32_t valLen) {
        if (keyLen < 10 || valLen < 4) return YES;
        uint32_t nameLen = le16(key + 8);
        if (10 + nameLen != keyLen || nameLen != sizeof kName || memcmp(key + 10, kName, sizeof kName) != 0) return YES;
        uint16_t flags = le16(val), len = le16(val + 2);
        if ((flags & 0x2) && 4u + len <= valLen) { // XATTR_DATA_EMBEDDED
            target = [NSData dataWithBytes:val + 4 length:len];
        } else if ((flags & 0x1) && valLen >= 4 + 8 + 8) { // XATTR_DATA_STREAM: obj id, dstream size
            streamID = le64(val + 4);
            streamSize = le64(val + 12);
        }
        return NO;
    } error:error];
    if (!ok) return nil;
    if (target) return target;
    if (streamID) {
        uint64_t n = MIN(streamSize, 4096ull);
        return [self readStream:streamID size:n offset:0 length:(NSUInteger)n error:error];
    }
    return [NSData data];
}

- (nullable NSData *)readDataOfNode:(DMGNode *)node offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {
    if (node.kind == DMGNodeKindDirectory || node.forkDescriptor.length < 8) {
        if (error) *error = DMGMakeError(DMGParserErrorUnsupported, @"Node has no data stream.");
        return nil;
    }
    if (node.kind == DMGNodeKindSymlink) {
        NSData *target = [self readSymlinkTargetOfNode:node error:error];
        if (!target || offset >= target.length) return target ? [NSData data] : nil;
        return [target subdataWithRange:NSMakeRange((NSUInteger)offset, MIN(length, target.length - (NSUInteger)offset))];
    }
    return [self readStream:le64(node.forkDescriptor.bytes) size:node.size offset:offset length:length error:error];
}

@end
