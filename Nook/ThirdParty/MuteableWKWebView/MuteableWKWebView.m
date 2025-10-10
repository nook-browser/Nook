//
//  MuteableWKWebView.m
//  MuteableWKWebView
//
//  Created by Hori,Masaki on 2017/05/21.
//  Copyright © 2017年 Hori,Masaki. All rights reserved.
//

#import "MuteableWKWebView.h"
#import "MuteableWKWebViewPrivate.h"

#import <objc/runtime.h>

#import "HTSymbolHook.h"
#include "getPage.h"

#import "SearchSymbol.h"

typedef void (*SetMuteFunc)(void*, _WKMediaMutedState);

static const char *mutekey = "HMMuteKey";
static NSString *sSymbolName = nil;
static SetMuteFunc sMuteFunc = NULL;

@interface WKWebView (HMMuteExtensionPrivate)

@property _WKMediaMutedState mute;

@end

@implementation WKWebView (HMMuteExtension)

- (BOOL)isMuted {
    
    return self.mute != _WKMediaNoneMuted;
}

- (void)setMuted:(BOOL)isMuted {
    
    self.mute = isMuted ? _WKMediaAudioMuted : _WKMediaNoneMuted;
}

static NSString *symbolName(void) {
    if( sSymbolName ) return sSymbolName;
    
    static BOOL isFirst = YES;
    if( !isFirst ) return nil;
    isFirst = NO;
    
    NSArray<NSString *> *hints = @[@"WebPageProxy", @"setMuted"];
    sSymbolName = searchSymbol(@"/System/Library/Frameworks/WebKit.framework/WebKit", hints);
    return sSymbolName;
}

static SetMuteFunc getSetMuteFunc(void) {
    if( sMuteFunc ) return sMuteFunc;
    
    static BOOL isFirst = YES;
    if( !isFirst ) return NULL;
    isFirst = NO;
    
    NSString *symName = symbolName();
    if( !symName ) return NULL;
    
    HTSymbolHook *hook = [HTSymbolHook symbolHookWithImageNameSuffix:@"/WebKit"];
    sMuteFunc = (SetMuteFunc)[hook symbolPtrWithSymbolName:symName];
    return sMuteFunc;
}

- (void)setMute:(_WKMediaMutedState)mute {
    void *ptr = getPage(self);
    
    SetMuteFunc setMute = getSetMuteFunc();
    if( !ptr || !setMute ) {
        fprintf(stderr, "It can NOT mute on this Mac.\n");
        return;
    }
    setMute(ptr, mute);
    
    objc_setAssociatedObject(self, mutekey, [NSNumber numberWithInteger:mute], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
}
- (_WKMediaMutedState)mute {
    NSNumber *muteVal = objc_getAssociatedObject(self, mutekey);
    return muteVal.integerValue;
}

@end

/// this method use only WKWebView has _setPageMuted: method.
/// _setPageMuted method available from macOS 10.13 and iOS 11.0.
@implementation WKWebView (NewMethodHMMuteExtension)
- (void)NEW_HMMuteableWKWebView_setMute:(_WKMediaMutedState)mute {
    
    objc_setAssociatedObject(self, mutekey, [NSNumber numberWithInteger:mute], OBJC_ASSOCIATION_RETAIN_NONATOMIC);
    
    [self _setPageMuted:mute];
}
@end
