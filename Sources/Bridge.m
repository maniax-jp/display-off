#import "Bridge.h"
#import <Cocoa/Cocoa.h>
#import <IOKit/IOKitLib.h>

@interface CGVirtualDisplayMode : NSObject
- (instancetype)initWithWidth:(NSUInteger)w height:(NSUInteger)h refreshRate:(double)r;
@end
@interface CGVirtualDisplayDescriptor : NSObject
@property (nonatomic) unsigned int vendorID, productID, serialNum;
@property (nonatomic, copy) NSString *name;
@property (nonatomic) CGSize sizeInMillimeters;
@property (nonatomic) unsigned int maxPixelsWide, maxPixelsHigh;
@property (nonatomic, strong) dispatch_queue_t queue;
@end
@interface CGVirtualDisplaySettings : NSObject
@property (nonatomic) unsigned int hiDPI;
@property (nonatomic, copy) NSArray *modes;
@end
@interface CGVirtualDisplay : NSObject
- (instancetype)initWithDescriptor:(CGVirtualDisplayDescriptor *)d;
- (BOOL)applySettings:(CGVirtualDisplaySettings *)s;
@property (readonly) unsigned int displayID;
@end

typedef CFTypeRef IOAVServiceRef;
extern IOAVServiceRef IOAVServiceCreateWithService(CFAllocatorRef allocator, io_service_t service);
extern IOReturn IOAVServiceWriteI2C(IOAVServiceRef service, uint32_t chipAddress, uint32_t dataAddress, void *inputBuffer, uint32_t inputBufferSize);

static CGVirtualDisplay *gVirtual;

@implementation DOBridge

+ (BOOL)startVirtualDisplay {
    if (gVirtual) return YES;
    CGVirtualDisplayDescriptor *d = [CGVirtualDisplayDescriptor new];
    d.name = @"DisplayOff Virtual";
    d.vendorID = 0x1234; d.productID = 0x5678; d.serialNum = 1;
    d.maxPixelsWide = 1920; d.maxPixelsHigh = 1080;
    d.sizeInMillimeters = CGSizeMake(527, 296);
    d.queue = dispatch_get_main_queue();
    CGVirtualDisplay *vd = [[CGVirtualDisplay alloc] initWithDescriptor:d];
    if (!vd) return NO;
    CGVirtualDisplaySettings *s = [CGVirtualDisplaySettings new];
    s.hiDPI = 0;
    s.modes = @[[[CGVirtualDisplayMode alloc] initWithWidth:1920 height:1080 refreshRate:60]];
    if (![vd applySettings:s]) return NO;
    gVirtual = vd;
    return YES;
}

+ (void)stopVirtualDisplay { gVirtual = nil; }
+ (unsigned int)virtualDisplayID { return gVirtual ? gVirtual.displayID : 0; }

// Calls block for every external DCPAVServiceProxy; the block returns YES to count it.
+ (int)forEachExternalService:(BOOL (^)(IOAVServiceRef svc, io_service_t proxy))block {
    io_iterator_t iter;
    if (IORegistryEntryCreateIterator(IORegistryGetRootEntry(kIOMainPortDefault), kIOServicePlane,
                                      kIORegistryIterateRecursively, &iter) != KERN_SUCCESS) return 0;
    int count = 0;
    io_service_t svc;
    while ((svc = IOIteratorNext(iter)) != MACH_PORT_NULL) {
        io_name_t name;
        IORegistryEntryGetName(svc, name);
        if (strcmp(name, "DCPAVServiceProxy") == 0) {
            CFTypeRef loc = IORegistryEntrySearchCFProperty(svc, kIOServicePlane, CFSTR("Location"),
                                                            kCFAllocatorDefault, kIORegistryIterateRecursively);
            BOOL external = loc && CFGetTypeID(loc) == CFStringGetTypeID() &&
                            CFStringCompare(loc, CFSTR("External"), 0) == kCFCompareEqualTo;
            if (loc) CFRelease(loc);
            if (external) {
                IOAVServiceRef av = IOAVServiceCreateWithService(kCFAllocatorDefault, svc);
                if (av) {
                    if (block(av, svc)) count++;
                    CFRelease(av);
                }
            }
        }
        IOObjectRelease(svc);
    }
    IOObjectRelease(iter);
    return count;
}

+ (int)externalDDCCount {
    return [self forEachExternalService:^BOOL(IOAVServiceRef svc, io_service_t proxy) { return YES; }];
}

+ (int)standbyAllExternal {
    return [self forEachExternalService:^BOOL(IOAVServiceRef svc, io_service_t proxy) {
        // DDC/CI "Set VCP Feature": opcode 0xD6 (power mode), value 5 (off).
        uint8_t data[6] = {0x84, 0x03, 0xD6, 0x00, 0x05, 0};
        data[5] = 0x6E ^ 0x51 ^ data[0] ^ data[1] ^ data[2] ^ data[3] ^ data[4];
        // MCDP29xx based ports route DDC through chip address 0xB7.
        uint32_t chip = 0x37;
        io_registry_entry_t parent;
        if (IORegistryEntryGetParentEntry(proxy, kIOServicePlane, &parent) == KERN_SUCCESS) {
            CFTypeRef cls = IORegistryEntryCreateCFProperty(parent, CFSTR("EPICProviderClass"), kCFAllocatorDefault, 0);
            if (cls && CFGetTypeID(cls) == CFStringGetTypeID() &&
                CFStringCompare(cls, CFSTR("AppleDCPMCDP29XX"), 0) == kCFCompareEqualTo) chip = 0xB7;
            if (cls) CFRelease(cls);
            IOObjectRelease(parent);
        }
        BOOL ok = NO;
        for (int i = 0; i < 2; i++) {
            usleep(10000);
            ok = IOAVServiceWriteI2C(svc, chip, 0x51, data, sizeof(data)) == KERN_SUCCESS;
            if (!ok) break;
        }
        return ok;
    }];
}

@end
