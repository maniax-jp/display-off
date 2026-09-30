#import <Foundation/Foundation.h>

// Private-API helpers: virtual display (CGVirtualDisplay) and DDC/CI over IOAVService.
@interface DOBridge : NSObject
+ (BOOL)startVirtualDisplay;
+ (void)stopVirtualDisplay;
+ (unsigned int)virtualDisplayID;
/// Number of external displays currently reachable over DDC (Apple Silicon).
+ (int)externalDDCCount;
/// Sends DDC "standby" (VCP 0xD6 = 5) to every external display. Returns how many succeeded.
+ (int)standbyAllExternal;
@end
