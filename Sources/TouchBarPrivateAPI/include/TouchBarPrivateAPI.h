#ifndef TouchBarPrivateAPI_h
#define TouchBarPrivateAPI_h

#include <CoreGraphics/CGDisplayStream.h>
#include <dispatch/dispatch.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

CGDisplayStreamRef _Nullable TBRCreateTouchBarDisplayStream(
    dispatch_queue_t _Nonnull queue,
    CGDisplayStreamFrameAvailableHandler _Nonnull handler
);

CGError TBRStartDisplayStream(CGDisplayStreamRef _Nonnull stream);
CGError TBRStopDisplayStream(CGDisplayStreamRef _Nonnull stream);
int32_t TBRGetTouchBarStatus(void);
void TBRSetTouchBarStatus(int32_t status);

#ifdef __cplusplus
}
#endif

#endif
