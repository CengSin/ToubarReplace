#import "TouchBarPrivateAPI.h"

#include <dlfcn.h>

typedef CGDisplayStreamRef _Nullable (*TBRCreateStreamFunction)(
    uint32_t displayID,
    dispatch_queue_t queue,
    CGDisplayStreamFrameAvailableHandler handler
);
typedef CGError (*TBRStreamControlFunction)(CGDisplayStreamRef stream);
typedef int32_t (*TBRGetStatusFunction)(void);
typedef void (*TBRSetStatusFunction)(int32_t status);

static void *TBRLoadFramework(const char *path) {
    return dlopen(path, RTLD_LAZY | RTLD_LOCAL);
}

CGDisplayStreamRef _Nullable TBRCreateTouchBarDisplayStream(
    dispatch_queue_t queue,
    CGDisplayStreamFrameAvailableHandler handler
) {
    static TBRCreateStreamFunction createStream;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = TBRLoadFramework(
            "/System/Library/PrivateFrameworks/SkyLight.framework/SkyLight"
        );
        if (handle != NULL) {
            createStream = (TBRCreateStreamFunction)dlsym(
                handle,
                "SLSDFRDisplayStreamCreate"
            );
        }
    });

    return createStream == NULL ? NULL : createStream(0, queue, handler);
}

static TBRStreamControlFunction TBRResolveStreamFunction(const char *name) {
    void *handle = TBRLoadFramework(
        "/System/Library/Frameworks/CoreGraphics.framework/CoreGraphics"
    );
    return handle == NULL
        ? NULL
        : (TBRStreamControlFunction)dlsym(handle, name);
}

CGError TBRStartDisplayStream(CGDisplayStreamRef stream) {
    static TBRStreamControlFunction startStream;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        startStream = TBRResolveStreamFunction("CGDisplayStreamStart");
    });
    return startStream == NULL ? 1000 : startStream(stream);
}

CGError TBRStopDisplayStream(CGDisplayStreamRef stream) {
    static TBRStreamControlFunction stopStream;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        stopStream = TBRResolveStreamFunction("CGDisplayStreamStop");
    });
    return stopStream == NULL ? 1000 : stopStream(stream);
}

int32_t TBRGetTouchBarStatus(void) {
    static TBRGetStatusFunction getStatus;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = TBRLoadFramework(
            "/System/Library/PrivateFrameworks/"
            "DFRFoundation.framework/DFRFoundation"
        );
        if (handle != NULL) {
            getStatus = (TBRGetStatusFunction)dlsym(handle, "DFRGetStatus");
        }
    });
    return getStatus == NULL ? -1 : getStatus();
}

void TBRSetTouchBarStatus(int32_t status) {
    static TBRSetStatusFunction setStatus;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = TBRLoadFramework(
            "/System/Library/PrivateFrameworks/"
            "DFRFoundation.framework/DFRFoundation"
        );
        if (handle != NULL) {
            setStatus = (TBRSetStatusFunction)dlsym(handle, "DFRSetStatus");
        }
    });
    if (setStatus != NULL) {
        setStatus(status);
    }
}
