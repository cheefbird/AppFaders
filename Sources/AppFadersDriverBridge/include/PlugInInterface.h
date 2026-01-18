// PlugInInterface.h
// AppFadersDriver
//
// C interface layer for HAL AudioServerPlugIn.
// This header declares the factory function that coreaudiod calls to load our driver.

#ifndef PlugInInterface_h
#define PlugInInterface_h

#include <CoreFoundation/CoreFoundation.h>

#ifdef __cplusplus
extern "C" {
#endif

/// Factory function called by coreaudiod to create the driver instance.
/// Must match the name in Info.plist CFPlugInFactories.
///
/// @param allocator The allocator to use (typically kCFAllocatorDefault)
/// @param requestedTypeUUID Must be kAudioServerPlugInTypeUUID
/// @return Pointer to our AudioServerPlugInDriverInterface, or NULL on failure
void* AppFadersDriver_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID);

#ifdef __cplusplus
}
#endif

#endif /* PlugInInterface_h */
