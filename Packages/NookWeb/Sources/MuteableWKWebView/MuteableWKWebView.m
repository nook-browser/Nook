//
//  MuteableWKWebView.m
//  MuteableWKWebView
//
//  Created by Hori,Masaki on 2017/05/21.
//  Copyright © 2017年 Hori,Masaki. All rights reserved.
//
//  Simplified for macOS 15.5+: uses _setPageMuted: directly.
//  Removed HTSymbolHook/mach_override/getPage dependency (runtime binary patching).
//

#import "MuteableWKWebView.h"
#import "MuteableWKWebViewPrivate.h"

#import <objc/runtime.h>

static const char *mutekey = "HMMuteKey";

@implementation WKWebView (HMMuteExtension)

- (BOOL)isMuted {
    return self.mute != _WKMediaNoneMuted;
}

- (void)setMuted:(BOOL)isMuted {
    self.mute = isMuted ? _WKMediaAudioMuted : _WKMediaNoneMuted;
}

// Fallback path — only used if MethodSwizzler fails to swizzle.
// On macOS 15.5+ _setPageMuted: is always present, so swizzling always succeeds
// and this implementation is swapped to NEW_HMMuteableWKWebView_setMute:.
- (void)setMute:(_WKMediaMutedState)mute {
    // Direct _setPageMuted: call as safety fallback (guaranteed on macOS 10.13+)
    if ([self respondsToSelector:@selector(_setPageMuted:)]) {
        [self _setPageMuted:mute];
    }
    objc_setAssociatedObject(self, mutekey, [NSNumber numberWithInteger:mute], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}

- (_WKMediaMutedState)mute {
    NSNumber *muteVal = objc_getAssociatedObject(self, mutekey);
    return muteVal.integerValue;
}

@end

/// Uses _setPageMuted: private API (available since macOS 10.13).
/// MethodSwizzler swaps this in as the implementation of setMute: at load time.
@implementation WKWebView (NewMethodHMMuteExtension)
- (void)NEW_HMMuteableWKWebView_setMute:(_WKMediaMutedState)mute {
    objc_setAssociatedObject(self, mutekey, [NSNumber numberWithInteger:mute], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    [self _setPageMuted:mute];
}
@end
