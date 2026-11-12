#import "DMGNode.h"

@implementation DMGNode

- (instancetype)initWithName:(NSString *)name
                  identifier:(uint64_t)identifier
            parentIdentifier:(uint64_t)parentIdentifier
                        kind:(DMGNodeKind)kind
                 permissions:(uint16_t)permissions
                        size:(uint64_t)size
                  childCount:(uint32_t)childCount
            modificationDate:(NSDate *)modificationDate
              forkDescriptor:(NSData *)forkDescriptor {
    self = [super init];
    if (self) {
        _name = [name copy];
        _identifier = identifier;
        _parentIdentifier = parentIdentifier;
        _kind = kind;
        _permissions = permissions;
        _size = size;
        _childCount = childCount;
        _modificationDate = modificationDate;
        _forkDescriptor = forkDescriptor;
    }
    return self;
}

@end
