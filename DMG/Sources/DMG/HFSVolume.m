#import "HFSVolume.h"
#import "DMGInternal.h"

typedef struct { uint32_t start; uint32_t count; } HFSExtent; // host byte order

typedef int  (^HFSKeyCompare)(const uint8_t *key, uint16_t keyLen); // <0: key sorts before target, 0: match, >0: after
typedef BOOL (^HFSRecordVisitor)(const uint8_t *key, uint16_t keyLen, const uint8_t *data, uint16_t dataLen);

static const uint32_t kExtentsFileID = 3;
static const uint32_t kCatalogFileID = 4;
static const uint32_t kRootFolderID = 2;
static const NSTimeInterval kHFSEpochToUnix = 2082844800.0;

@interface HFSBTree : NSObject
@property (nonatomic, strong) NSData *extents; // HFSExtent[]
@property (nonatomic) uint64_t logicalSize;
@property (nonatomic) uint32_t nodeSize;
@property (nonatomic) uint32_t rootNode;
@property (nonatomic) uint32_t totalNodes;
@end
@implementation HFSBTree
@end

static BOOL isPowerOfTwo(uint32_t v) { return v && !(v & (v - 1)); }

/// Locates record `i` in a B-tree node.
static BOOL nodeRecord(const uint8_t *node, uint32_t nodeSize, uint16_t numRecords, uint16_t i,
                       const uint8_t **key, uint16_t *keyLen, const uint8_t **data, uint16_t *dataLen)
{
    uint32_t tableStart = nodeSize - 2u * (numRecords + 1u);
    uint16_t start = be16(node + nodeSize - 2u * (i + 1u));
    uint16_t end = be16(node + nodeSize - 2u * (i + 2u));
    if (start < 14 || end < start + 2u || end > tableStart) return NO;
    uint16_t kl = be16(node + start);
    uint32_t dataStart = (uint32_t)start + 2u + kl;
    if (dataStart > end) return NO;
    if (dataStart & 1) dataStart++; // 2-byte aligned
    if (dataStart > end) dataStart = end;
    *key = node + start + 2;
    *keyLen = kl;
    *data = node + dataStart;
    *dataLen = (uint16_t)(end - dataStart);
    return YES;
}

@implementation HFSVolume {
    DMGParser *_parser;
    uint64_t _partitionOffset;
    uint32_t _blockSize;
    HFSBTree *_extentsTree;
    HFSBTree *_catalogTree;
}

- (nullable instancetype)initWithParser:(DMGParser *)parser partitionOffset:(uint64_t)offset error:(NSError **)error {
    self = [super init];
    if (!self) return nil;
    _parser = parser;
    NSError *openError = nil;
    if ([self openHFSAtOffset:offset error:&openError]) return self;
    if (error) *error = openError;
    return nil;
}

- (NSString *)filesystemType { return @"HFS+"; }

/// YES on success. NO with *error == nil means "no HFS+ signature here"; NO with *error set means a damaged HFS+ volume.
- (BOOL)openHFSAtOffset:(uint64_t)base error:(NSError **)error {
    uint8_t vh[512];
    if (![_parser readBytes:vh atOffset:base + 1024 length:512 error:NULL]) return NO;
    uint16_t sig = be16(vh);
    if (sig != 0x482B /* 'H+' */ && sig != 0x4858 /* 'HX' */) return NO;

    uint32_t blockSize = be32(vh + 40);
    if (!isPowerOfTwo(blockSize) || blockSize < 512 || blockSize > (1u << 28)) {
        *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Invalid HFS+ allocation block size.");
        return NO;
    }
    _partitionOffset = base;
    _blockSize = blockSize;

    // fork +192, catalogFile fork +272 (80 bytes)
    if (be64(vh + 192) > 0) {
        _extentsTree = [self openTreeWithFork:vh + 192 fileID:kExtentsFileID error:error];
        if (!_extentsTree) return NO;
    }
    _catalogTree = [self openTreeWithFork:vh + 272 fileID:kCatalogFileID error:error];
    if (!_catalogTree) return NO;

    // This should have our volume name
    __block NSString *name = nil;
    uint32_t rootID = kRootFolderID;
    NSError *enumError = nil;
    [self enumerateTree:_catalogTree
               matching:^int(const uint8_t *key, uint16_t keyLen) {
        if (keyLen < 6) return -1;
        uint32_t k = be32(key);
        return k < rootID ? -1 : (k > rootID ? 1 : 0);
    }
                visitor:^BOOL(const uint8_t *key, uint16_t keyLen, const uint8_t *rec, uint16_t recLen) {
        // folder thread
        if (recLen >= 10 && be16(rec) == 3) {
            uint16_t n = be16(rec + 8);
            if (recLen >= 10 + 2u * n) {
                name = [[NSString alloc] initWithBytes:rec + 10 length:2u * n encoding:NSUTF16BigEndianStringEncoding];
                return NO;
            }
        }
        return YES;
    }
                  error:&enumError];
    if (enumError) { *error = enumError; return NO; }

    _volumeName = [(name ?: @"Untitled") stringByReplacingOccurrencesOfString:@":" withString:@"/"];
    _rootNode = [[DMGNode alloc] initWithName:_volumeName identifier:kRootFolderID parentIdentifier:1
                                         kind:DMGNodeKindDirectory permissions:0755 size:0 childCount:0
                             modificationDate:nil forkDescriptor:nil];
    return YES;
}

#pragma mark - Forks

- (nullable NSData *)resolveExtentsForFork:(const uint8_t *)fork fileID:(uint32_t)fileID error:(NSError **)error {
    // logicalSize(8) clumpSize(4) totalBlocks(4) extents[8]{start(4) count(4)}
    NSMutableData *all = [NSMutableData data];
    uint32_t totalBlocks = be32(fork + 12);
    uint64_t have = 0;
    for (int i = 0; i < 8; i++) {
        HFSExtent e = { be32(fork + 16 + 8 * i), be32(fork + 20 + 8 * i) };
        if (e.count == 0) break;
        [all appendBytes:&e length:sizeof e];
        have += e.count;
    }

    while (have < totalBlocks) {
        if (!_extentsTree) {
            if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Fork needs extents overflow, but the volume has none.");
            return nil;
        }
        uint32_t startBlock = (uint32_t)have;
        __block uint64_t added = 0;
        NSError *enumError = nil;
        [self enumerateTree:_extentsTree
                   matching:^int(const uint8_t *key, uint16_t keyLen) {
            if (keyLen < 10) return -1;
            uint8_t forkType = key[0];
            uint32_t fid = be32(key + 2), sb = be32(key + 6);
            if (fid != fileID) return fid < fileID ? -1 : 1;
            if (forkType != 0) return 1; // data fork only
            if (sb != startBlock) return sb < startBlock ? -1 : 1;
            return 0;
        }
                    visitor:^BOOL(const uint8_t *key, uint16_t keyLen, const uint8_t *rec, uint16_t recLen) {
            if (recLen < 64) return NO;
            for (int i = 0; i < 8; i++) {
                HFSExtent e = { be32(rec + 8 * i), be32(rec + 8 * i + 4) };
                if (e.count == 0) break;
                [all appendBytes:&e length:sizeof e];
                added += e.count;
            }
            return NO;
        }
                      error:&enumError];
        if (enumError) { if (error) *error = enumError; return nil; }
        if (added == 0) {
            if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Missing extents overflow record.");
            return nil;
        }
        have += added;
    }
    return all;
}

- (BOOL)readExtents:(NSData *)extents logicalSize:(uint64_t)logicalSize offset:(uint64_t)offset
             length:(NSUInteger)length into:(uint8_t *)dst error:(NSError **)error {
    if (offset > logicalSize || length > logicalSize - offset) {
        if (error) *error = DMGMakeError(DMGParserErrorOutOfRange, @"Read beyond end of fork.");
        return NO;
    }
    const HFSExtent *e = extents.bytes;
    NSUInteger n = extents.length / sizeof(HFSExtent);
    uint64_t cursor = 0;
    NSUInteger done = 0;
    for (NSUInteger i = 0; i < n && done < length; i++) {
        uint64_t extBytes = (uint64_t)e[i].count * _blockSize;
        uint64_t want = offset + done;
        if (want >= cursor + extBytes) { cursor += extBytes; continue; }
        uint64_t inExtent = want - cursor;
        NSUInteger chunk = (NSUInteger)MIN((uint64_t)(length - done), extBytes - inExtent);
        uint64_t physical = _partitionOffset + (uint64_t)e[i].start * _blockSize + inExtent;
        if (![_parser readBytes:dst + done atOffset:physical length:chunk error:error]) return NO;
        done += chunk;
        cursor += extBytes;
    }
    if (done < length) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Fork extents are shorter than its logical size.");
        return NO;
    }
    return YES;
}

#pragma mark - B-tree

- (nullable HFSBTree *)openTreeWithFork:(const uint8_t *)fork fileID:(uint32_t)fileID error:(NSError **)error {
    NSData *extents = [self resolveExtentsForFork:fork fileID:fileID error:error];
    if (!extents) return nil;
    uint64_t logical = be64(fork);

    uint8_t hdr[64];
    if (logical < sizeof hdr || ![self readExtents:extents logicalSize:logical offset:0 length:sizeof hdr into:hdr error:error]) {
        if (error && !*error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"B-tree file is too small.");
        return nil;
    }
    // (14 bytes) +16 rootNode, +32 nodeSize (2), +36 totalNodes
    uint32_t nodeSize = be16(hdr + 32);
    uint32_t root = be32(hdr + 16);
    uint32_t total = be32(hdr + 36);
    if ((int8_t)hdr[8] != 1 || !isPowerOfTwo(nodeSize) || nodeSize < 512 ||
        (uint64_t)total * nodeSize > logical || (root != 0 && root >= total)) {
        if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Corrupt B-tree header.");
        return nil;
    }
    HFSBTree *tree = [HFSBTree new];
    tree.extents = extents;
    tree.logicalSize = logical;
    tree.nodeSize = nodeSize;
    tree.rootNode = root;
    tree.totalNodes = total;
    return tree;
}

/// Descends to the first leaf record that does not sort before the target
/// then walks the leaf chain calling `visit` for every record where
/// compare() == 0, stopping at the first record that sorts after.
- (BOOL)enumerateTree:(HFSBTree *)tree matching:(HFSKeyCompare)compare visitor:(HFSRecordVisitor)visit error:(NSError **)error {
    if (tree.rootNode == 0) return YES; // empty tree
    const uint32_t nodeSize = tree.nodeSize;
    NSMutableData *buffer = [NSMutableData dataWithLength:nodeSize];
    uint8_t *node = buffer.mutableBytes;

    uint32_t nodeNum = tree.rootNode;
    uint32_t hops = 0;
    BOOL inLeaves = NO;

    while (nodeNum != 0) {
        if (++hops > tree.totalNodes + 1 || nodeNum >= tree.totalNodes ||
            ![self readExtents:tree.extents logicalSize:tree.logicalSize offset:(uint64_t)nodeNum * nodeSize
                        length:nodeSize into:node error:error]) {
            if (error && !*error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"B-tree traversal failed (corrupt or cyclic).");
            return NO;
        }
        int8_t kind = (int8_t)node[8];
        uint16_t numRecords = be16(node + 10);
        if (14u + 2u * (numRecords + 1u) > nodeSize) {
            if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Corrupt B-tree node.");
            return NO;
        }

        const uint8_t *key, *data;
        uint16_t keyLen, dataLen;

        if (kind == 0 && !inLeaves) { // index node
            uint16_t pick = 0;
            for (uint16_t i = 0; i < numRecords; i++) {
                if (!nodeRecord(node, nodeSize, numRecords, i, &key, &keyLen, &data, &dataLen)) goto corrupt;
                if (compare(key, keyLen) < 0) pick = i; else break;
            }
            if (numRecords == 0 || !nodeRecord(node, nodeSize, numRecords, pick, &key, &keyLen, &data, &dataLen) || dataLen < 4) goto corrupt;
            nodeNum = be32(data);
        } else if (kind == -1) { // leaf node
            inLeaves = YES;
            for (uint16_t i = 0; i < numRecords; i++) {
                if (!nodeRecord(node, nodeSize, numRecords, i, &key, &keyLen, &data, &dataLen)) goto corrupt;
                int c = compare(key, keyLen);
                if (c < 0) continue;
                if (c > 0) return YES;
                if (!visit(key, keyLen, data, dataLen)) return YES;
            }
            nodeNum = be32(node); // fLink: next leaf
        } else {
            goto corrupt;
        }
    }
    return YES;

corrupt:
    if (error) *error = DMGMakeError(DMGParserErrorInvalidContainer, @"Corrupt B-tree record.");
    return NO;
}

#pragma mark - Public API

- (nullable DMGNode *)nodeFromKey:(const uint8_t *)key keyLen:(uint16_t)keyLen record:(const uint8_t *)rec recordLen:(uint16_t)recLen {
    if (keyLen < 6 || recLen < 2) return nil;
    uint16_t type = be16(rec);
    uint16_t nameLen = be16(key + 4);
    if (nameLen == 0 || keyLen < 6u + 2u * nameLen) return nil;
    if (be16(key + 6) == 0) return nil; // "\0\0\0\0HFS+ Private Data"

    NSString *name = [[NSString alloc] initWithBytes:key + 6 length:2u * nameLen encoding:NSUTF16BigEndianStringEncoding];
    if (!name) return nil;
    if ([name containsString:@":"]) name = [name stringByReplacingOccurrencesOfString:@":" withString:@"/"];

    uint32_t parentID = be32(key);
    uint32_t hfsDate = recLen >= 20 ? be32(rec + 16) : 0; // contentModDate
    NSDate *modified = hfsDate ? [NSDate dateWithTimeIntervalSince1970:(NSTimeInterval)hfsDate - kHFSEpochToUnix] : nil;

    // folder: valence +4, folderID +8
    if (type == 1 && recLen >= 88) {
        return [[DMGNode alloc] initWithName:name identifier:be32(rec + 8) parentIdentifier:parentID
                                        kind:DMGNodeKindDirectory permissions:(be16(rec + 42) & 07777) size:0 childCount:be32(rec + 4)
                            modificationDate:modified forkDescriptor:nil];
    }

    // fileID +8, fileMode +42, dataFork +88
    if (type == 2 && recLen >= 248) {
        uint16_t mode = be16(rec + 42);
        DMGNodeKind kind = ((mode & 0xF000) == 0xA000) ? DMGNodeKindSymlink : DMGNodeKindFile;
        return [[DMGNode alloc] initWithName:name identifier:be32(rec + 8) parentIdentifier:parentID
                                        kind:kind permissions:(mode & 07777) size:be64(rec + 88) childCount:0
                            modificationDate:modified forkDescriptor:[NSData dataWithBytes:rec + 88 length:80]];
    }
    return nil; // thread records (3, 4) and anything unknown
}

- (nullable NSArray<DMGNode *> *)childrenOfNode:(DMGNode *)parent error:(NSError **)error {
    if (parent.kind != DMGNodeKindDirectory) return @[];
    const uint32_t parentID = (uint32_t)parent.identifier;
    NSMutableArray<DMGNode *> *children = [NSMutableArray arrayWithCapacity:MIN(parent.childCount, 4096u)];

    // Catallg is sorted by (parentID, name)
    BOOL ok = [self enumerateTree:_catalogTree
                         matching:^int(const uint8_t *key, uint16_t keyLen) {
        if (keyLen < 6) return -1;
        uint32_t k = be32(key);
        return k < parentID ? -1 : (k > parentID ? 1 : 0);
    }
                          visitor:^BOOL(const uint8_t *key, uint16_t keyLen, const uint8_t *rec, uint16_t recLen) {
        DMGNode *node = [self nodeFromKey:key keyLen:keyLen record:rec recordLen:recLen];
        if (node) [children addObject:node];
        return YES;
    }
                            error:error];
    return ok ? children : nil;
}

- (nullable NSData *)readDataOfNode:(DMGNode *)node offset:(uint64_t)offset length:(NSUInteger)length error:(NSError **)error {
    if (node.kind == DMGNodeKindDirectory || node.forkDescriptor.length < 80) {
        if (error) *error = DMGMakeError(DMGParserErrorUnsupported, @"Node has no data fork.");
        return nil;
    }
    const uint8_t *fork = node.forkDescriptor.bytes;
    uint64_t logical = be64(fork);
    if (offset >= logical || length == 0) return [NSData data];
    length = (NSUInteger)MIN((uint64_t)length, logical - offset);

    NSData *extents = [self resolveExtentsForFork:fork fileID:(uint32_t)node.identifier error:error];
    if (!extents) return nil;
    NSMutableData *out = [NSMutableData dataWithLength:length];
    if (![self readExtents:extents logicalSize:logical offset:offset length:length into:out.mutableBytes error:error]) return nil;
    return out;
}

@end
