// PlugInInterface.c
// COM-style vtable for AudioServerPlugInDriverInterface
// this is what coreaudiod actually calls into

#include "PlugInInterface.h"
#include <CoreAudio/AudioServerPlugIn.h>
#include <os/log.h>
#include <stdatomic.h>

// MARK: - Logging

static os_log_t sPlugInLog = NULL;

static os_log_t GetPlugInLog(void)
{
  if (sPlugInLog == NULL)
  {
    sPlugInLog = os_log_create("com.fbreidenbach.appfaders.driver", "PlugIn");
  }
  return sPlugInLog;
}

#define LogInfo(format, ...) os_log_info(GetPlugInLog(), format, ##__VA_ARGS__)
#define LogError(format, ...) os_log_error(GetPlugInLog(), format, ##__VA_ARGS__)

// MARK: - Reference Counting

static _Atomic UInt32 sDriverRefCount = 0;

// MARK: - Driver Interface Pointer

// declare static interface
static AudioServerPlugInDriverInterface gDriverInterface;

// driver reference is just a pointer to our interface pointer
static AudioServerPlugInDriverInterface *gDriverInterfacePtr = &gDriverInterface;

// static host interface
static AudioServerPlugInHostRef sHost = NULL;

// MARK: - IUnknown Methods

static HRESULT PlugIn_QueryInterface(
    void *inDriver,
    REFIID inUUID,
    LPVOID *outInterface)
{
  if (outInterface == NULL)
  {
    return E_POINTER;
  }

  // we only support the AudioServerPlugInDriverInterface and IUnknown
  CFUUIDRef requestedUUID = CFUUIDCreateFromUUIDBytes(kCFAllocatorDefault, inUUID);
  CFUUIDRef driverInterfaceUUID = CFUUIDGetConstantUUIDWithBytes(
      NULL,
      0xEE, 0xA5, 0x77, 0x3D, 0xCC, 0x43, 0x49, 0xF1,
      0x8E, 0x00, 0x8F, 0x96, 0xE7, 0xD2, 0x3B, 0x17);
  CFUUIDRef iunknownUUID = CFUUIDGetConstantUUIDWithBytes(
      NULL,
      0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
      0xC0, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x46);

  Boolean isDriverInterface = CFEqual(requestedUUID, driverInterfaceUUID);
  Boolean isIUnknown = CFEqual(requestedUUID, iunknownUUID);
  CFRelease(requestedUUID);

  if (isDriverInterface || isIUnknown)
  {
    atomic_fetch_add(&sDriverRefCount, 1);
    *outInterface = &gDriverInterfacePtr;
    return S_OK;
  }

  *outInterface = NULL;
  return E_NOINTERFACE;
}

static ULONG PlugIn_AddRef(void *inDriver)
{
  UInt32 newCount = atomic_fetch_add(&sDriverRefCount, 1) + 1;
  LogInfo("AddRef: refCount = %u", newCount);
  return newCount;
}

static ULONG PlugIn_Release(void *inDriver)
{
  UInt32 oldCount = atomic_load(&sDriverRefCount);
  UInt32 newCount = 0;
  if (oldCount > 0)
  {
    newCount = atomic_fetch_sub(&sDriverRefCount, 1) - 1;
  }
  LogInfo("Release: refCount = %u", newCount);
  return newCount;
}

// MARK: - Basic Operations

static OSStatus PlugIn_Initialize(
    AudioServerPlugInDriverRef inDriver,
    AudioServerPlugInHostRef inHost)
{
  LogInfo("Initialize called");

  if (inHost == NULL)
  {
    LogError("Initialize called with NULL host");
    return kAudioHardwareBadObjectError;
  }

  sHost = inHost;

  // TODO(task6): swift DriverEntry will handle actual init
  return kAudioHardwareNoError;
}

static OSStatus PlugIn_CreateDevice(
    AudioServerPlugInDriverRef inDriver,
    CFDictionaryRef inDescription,
    const AudioServerPlugInClientInfo *inClientInfo,
    AudioObjectID *outDeviceObjectID)
{
  LogInfo("CreateDevice called");

  // we create device at init time - error on dynamic device creation
  return kAudioHardwareUnsupportedOperationError;
}

static OSStatus PlugIn_DestroyDevice(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID)
{
  LogInfo("DestroyDevice called for device %u", inDeviceObjectID);

  // not currently supporting destroying our built-in device
  return kAudioHardwareUnsupportedOperationError;
}

static OSStatus PlugIn_AddDeviceClient(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    const AudioServerPlugInClientInfo *inClientInfo)
{
  LogInfo("AddDeviceClient: device=%u client=%u pid=%d",
          inDeviceObjectID, inClientInfo->mClientID, inClientInfo->mProcessID);

  // TODO(task6): track clients for per-app volume
  return kAudioHardwareNoError;
}

static OSStatus PlugIn_RemoveDeviceClient(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    const AudioServerPlugInClientInfo *inClientInfo)
{
  LogInfo("RemoveDeviceClient: device=%u client=%u", inDeviceObjectID, inClientInfo->mClientID);

  // TODO(task6): track clients
  return kAudioHardwareNoError;
}

static OSStatus PlugIn_PerformDeviceConfigurationChange(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt64 inChangeAction,
    void *inChangeInfo)
{
  // we don't need this - just logging and returning
  LogInfo("PerformDeviceConfigurationChange: device=%u action=%llu", inDeviceObjectID, inChangeAction);

  return kAudioHardwareNoError;
}

static OSStatus PlugIn_AbortDeviceConfigurationChange(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt64 inChangeAction,
    void *inChangeInfo)
{
  // we don't need this - just logging and returning
  LogInfo("AbortDeviceConfigurationChange: device=%u action=%llu", inDeviceObjectID, inChangeAction);

  return kAudioHardwareNoError;
}

// MARK: - Property Operations

static Boolean PlugIn_HasProperty(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress *inAddress)
{
  // TODO(task7): swift VirtualDevice handles this
  return false;
}

static OSStatus PlugIn_IsPropertySettable(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress *inAddress,
    Boolean *outIsSettable)
{
  if (outIsSettable == NULL)
  {
    return kAudioHardwareIllegalOperationError;
  }

  // TODO(task7): swift VirtualDevice handles this
  *outIsSettable = false;
  return kAudioHardwareUnknownPropertyError;
}

static OSStatus PlugIn_GetPropertyDataSize(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress *inAddress,
    UInt32 inQualifierDataSize,
    const void *inQualifierData,
    UInt32 *outDataSize)
{
  if (outDataSize == NULL)
  {
    return kAudioHardwareIllegalOperationError;
  }

  // TODO(task7): swift VirtualDevice handles this
  *outDataSize = 0;
  return kAudioHardwareUnknownPropertyError;
}

static OSStatus PlugIn_GetPropertyData(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress *inAddress,
    UInt32 inQualifierDataSize,
    const void *inQualifierData,
    UInt32 inDataSize,
    UInt32 *outDataSize,
    void *outData)
{
  if (outDataSize == NULL || outData == NULL)
  {
    return kAudioHardwareIllegalOperationError;
  }

  // TODO(task7): swift VirtualDevice handles this
  *outDataSize = 0;
  return kAudioHardwareUnknownPropertyError;
}

static OSStatus PlugIn_SetPropertyData(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inObjectID,
    pid_t inClientProcessID,
    const AudioObjectPropertyAddress *inAddress,
    UInt32 inQualifierDataSize,
    const void *inQualifierData,
    UInt32 inDataSize,
    const void *inData)
{
  // TODO(task7): swift VirtualDevice handles this
  return kAudioHardwareUnknownPropertyError;
}

// MARK: - IO Operations

static OSStatus PlugIn_StartIO(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID)
{
  LogInfo("StartIO: device=%u client=%u", inDeviceObjectID, inClientID);

  // TODO(task8): swift PassthroughEngine starts here
  return kAudioHardwareNoError;
}

static OSStatus PlugIn_StopIO(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID)
{
  LogInfo("StopIO: device=%u client=%u", inDeviceObjectID, inClientID);

  // TODO(task8): swift PassthroughEngine stops here
  return kAudioHardwareNoError;
}

static OSStatus PlugIn_GetZeroTimeStamp(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    Float64 *outSampleTime,
    UInt64 *outHostTime,
    UInt64 *outSeed)
{
  // TODO(task8): real timing impl
  if (outSampleTime)
    *outSampleTime = 0;
  if (outHostTime)
    *outHostTime = 0;
  if (outSeed)
    *outSeed = 1;
  return kAudioHardwareNoError;
}

static OSStatus PlugIn_WillDoIOOperation(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    UInt32 inOperationID,
    Boolean *outWillDo,
    Boolean *outWillDoInPlace)
{
  // TODO(task8): tell host which IO ops we support
  if (outWillDo)
    *outWillDo = false;
  if (outWillDoInPlace)
    *outWillDoInPlace = true;
  return kAudioHardwareNoError;
}

static OSStatus PlugIn_BeginIOOperation(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    UInt32 inOperationID,
    UInt32 inIOBufferFrameSize,
    const AudioServerPlugInIOCycleInfo *inIOCycleInfo)
{
  // TODO(task8): IO cycle start
  return kAudioHardwareNoError;
}

static OSStatus PlugIn_DoIOOperation(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    AudioObjectID inStreamObjectID,
    UInt32 inClientID,
    UInt32 inOperationID,
    UInt32 inIOBufferFrameSize,
    const AudioServerPlugInIOCycleInfo *inIOCycleInfo,
    void *ioMainBuffer,
    void *ioSecondaryBuffer)
{
  // TODO(task9): this is where audio passthrough happens
  return kAudioHardwareNoError;
}

static OSStatus PlugIn_EndIOOperation(
    AudioServerPlugInDriverRef inDriver,
    AudioObjectID inDeviceObjectID,
    UInt32 inClientID,
    UInt32 inOperationID,
    UInt32 inIOBufferFrameSize,
    const AudioServerPlugInIOCycleInfo *inIOCycleInfo)
{
  // TODO(task8): IO cycle end
  return kAudioHardwareNoError;
}

// MARK: - Driver Interface VTable

static AudioServerPlugInDriverInterface gDriverInterface = {
    // IUnknown stuff
    ._reserved = NULL,
    .QueryInterface = PlugIn_QueryInterface,
    .AddRef = PlugIn_AddRef,
    .Release = PlugIn_Release,

    // basic operations
    .Initialize = PlugIn_Initialize,
    .CreateDevice = PlugIn_CreateDevice,
    .DestroyDevice = PlugIn_DestroyDevice,
    .AddDeviceClient = PlugIn_AddDeviceClient,
    .RemoveDeviceClient = PlugIn_RemoveDeviceClient,
    .PerformDeviceConfigurationChange = PlugIn_PerformDeviceConfigurationChange,
    .AbortDeviceConfigurationChange = PlugIn_AbortDeviceConfigurationChange,

    // property-specific operations
    .HasProperty = PlugIn_HasProperty,
    .IsPropertySettable = PlugIn_IsPropertySettable,
    .GetPropertyDataSize = PlugIn_GetPropertyDataSize,
    .GetPropertyData = PlugIn_GetPropertyData,
    .SetPropertyData = PlugIn_SetPropertyData,

    // io operations
    .StartIO = PlugIn_StartIO,
    .StopIO = PlugIn_StopIO,
    .GetZeroTimeStamp = PlugIn_GetZeroTimeStamp,
    .WillDoIOOperation = PlugIn_WillDoIOOperation,
    .BeginIOOperation = PlugIn_BeginIOOperation,
    .DoIOOperation = PlugIn_DoIOOperation,
    .EndIOOperation = PlugIn_EndIOOperation};

// MARK: - Factory Function

// Factory function called by coreaudiod to create driver instance.
/// @param allocator Allocator to use (ignored)
/// @param requestedTypeUUID Must be kAudioServerPlugInTypeUUID
/// @return Pointer to our driver interface, or NULL on failure
/// this is the entry point - coreaudiod calls this based on Info.plist
void *AppFadersDriver_Create(CFAllocatorRef allocator, CFUUIDRef requestedTypeUUID)
{
  LogInfo("AppFadersDriver_Create called");

  // must be kAudioServerPlugInTypeUUID
  CFUUIDRef audioServerPlugInTypeUUID = CFUUIDGetConstantUUIDWithBytes(
      NULL,
      0x44, 0x3A, 0xBA, 0xB8, 0xE7, 0xB3, 0x49, 0x1A,
      0xB9, 0x85, 0xBE, 0xB9, 0x18, 0x70, 0x30, 0xDB);

  if (!CFEqual(requestedTypeUUID, audioServerPlugInTypeUUID))
  {
    LogError("AppFadersDriver_Create: wrong type UUID");
    return NULL;
  }

  LogInfo("AppFadersDriver_Create: returning driver interface");
  atomic_store(&sDriverRefCount, 1);
  return &gDriverInterfacePtr;
}
