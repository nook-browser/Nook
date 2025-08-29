//
//  MuteableWKWebView.h
//  MuteableWKWebView
//
//  Created by Hori,Masaki on 2017/09/16.
//  Copyright © 2017年 Hori,Masaki. All rights reserved.
//

#import <WebKit/WebKit.h>

@interface WKWebView (MutableWKWebView)

@property (getter=isMuted) BOOL muted;

@end
