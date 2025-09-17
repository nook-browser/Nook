//
//  MethodSwizzler.m
//  MuteableWKWebView
//
//  Created by Hori,Masaki on 2018/02/15.
//  Copyright © 2018年 Hori,Masaki. All rights reserved.
//

#import <objc/runtime.h>

#import <WebKit/WebKit.h>

#import "MethodSwizzler.h"
#import "MuteableWKWebViewPrivate.h"

@implementation MethodSwizzler

+ (void)load {
    static dispatch_once_t onceToken;
    dispatch_once(&onceToken, ^{
        
        Class class = [WKWebView class];
        SEL setPageMutedSelector = @selector(_setPageMuted:);
        Method setPageMutedMethod = class_getInstanceMethod(class, setPageMutedSelector);
        
        if( setPageMutedMethod ) {
            
            SEL originalSelector = @selector(setMute:);
            SEL swizzledSelector = @selector(NEW_HMMuteableWKWebView_setMute:);
            
            Method originalMethod = class_getInstanceMethod(class, originalSelector);
            Method swizzledMethod = class_getInstanceMethod(class, swizzledSelector);
            
            method_exchangeImplementations(originalMethod, swizzledMethod);
        }
    });
}

@end

