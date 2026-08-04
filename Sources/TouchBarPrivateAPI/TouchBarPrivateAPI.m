#import "TouchBarPrivateAPI.h"
#import <AppKit/AppKit.h>

#include <dlfcn.h>
#include <objc/message.h>

@interface NSTouchBar (TBRSystemModal)
+ (void)presentSystemModalTouchBar:(NSTouchBar *)touchBar
                         placement:(int64_t)placement
          systemTrayItemIdentifier:(NSTouchBarItemIdentifier _Nullable)identifier;
+ (void)dismissSystemModalTouchBar:(NSTouchBar *)touchBar;
@end

typedef CGDisplayStreamRef _Nullable (*TBRCreateStreamFunction)(
    uint32_t displayID,
    dispatch_queue_t queue,
    CGDisplayStreamFrameAvailableHandler handler
);
typedef CGError (*TBRStreamControlFunction)(CGDisplayStreamRef stream);
typedef int32_t (*TBRGetStatusFunction)(void);
typedef void (*TBRSetStatusFunction)(int32_t status);
typedef void (*TBRSetSystemModalCloseBoxFunction)(bool showsCloseBox);

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

bool TBRCanPresentSystemModalTouchBar(void) {
    return [NSTouchBar respondsToSelector:
        @selector(presentSystemModalTouchBar:placement:systemTrayItemIdentifier:)]
        && [NSTouchBar respondsToSelector:
            @selector(dismissSystemModalTouchBar:)];
}

void TBRSetSystemModalShowsCloseBoxWhenFrontMost(bool showsCloseBox) {
    static TBRSetSystemModalCloseBoxFunction setShowsCloseBox;
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        void *handle = TBRLoadFramework(
            "/System/Library/PrivateFrameworks/"
            "DFRFoundation.framework/DFRFoundation"
        );
        if (handle != NULL) {
            setShowsCloseBox = (TBRSetSystemModalCloseBoxFunction)dlsym(
                handle,
                "DFRSystemModalShowsCloseBoxWhenFrontMost"
            );
        }
    });
    if (setShowsCloseBox != NULL) {
        setShowsCloseBox(showsCloseBox);
    }
}

static void TBRHideSystemModalCloseButtonNow(void) {
    Class functionRowClass = NSClassFromString(@"NSFunctionRow");
    SEL topLevelViewsSelector = NSSelectorFromString(
        @"_topLevelFunctionRowViews"
    );
    if (functionRowClass == Nil
        || ![functionRowClass respondsToSelector:topLevelViewsSelector]) {
        return;
    }

    typedef NSArray<NSView *> *(*TBRTopLevelViewsFunction)(id, SEL);
    NSArray<NSView *> *views = ((TBRTopLevelViewsFunction)objc_msgSend)(
        functionRowClass,
        topLevelViewsSelector
    );
    for (NSView *view in views) {
        if (![NSStringFromClass(view.class)
            isEqualToString:@"NSFunctionRowBackgroundColorView"]) {
            continue;
        }
        for (NSView *subview in view.subviews) {
            if (![subview isKindOfClass:NSStackView.class]) {
                continue;
            }
            for (NSView *stackSubview in subview.subviews) {
                if ([stackSubview isKindOfClass:NSButton.class]) {
                    stackSubview.hidden = YES;
                    return;
                }
            }
        }
    }
}

void TBRHideSystemModalCloseButton(void) {
    dispatch_async(dispatch_get_main_queue(), ^{
        TBRHideSystemModalCloseButtonNow();
    });
    dispatch_after(
        dispatch_time(DISPATCH_TIME_NOW, 100 * NSEC_PER_MSEC),
        dispatch_get_main_queue(),
        ^{
            TBRHideSystemModalCloseButtonNow();
        }
    );
}

void TBRPresentSystemModalTouchBar(NSTouchBar *touchBar, int64_t placement) {
    if (!TBRCanPresentSystemModalTouchBar()) {
        return;
    }
    [NSTouchBar presentSystemModalTouchBar:touchBar
                                placement:placement
                 systemTrayItemIdentifier:nil];
}

void TBRDismissSystemModalTouchBar(NSTouchBar *touchBar) {
    if (![NSTouchBar respondsToSelector:
        @selector(dismissSystemModalTouchBar:)]) {
        return;
    }
    [NSTouchBar dismissSystemModalTouchBar:touchBar];
}
