
[![Build Status](https://travis-ci.org/masakih/MuteableWKWebView.svg?branch=master)](https://travis-ci.org/masakih/MuteableWKWebView)
[![License](https://img.shields.io/github/license/masakih/WKWebKitMuteExt.svg)](https://github.com/masakih/WKWebKitMuteExt/blob/master/LICENSE)
[![GitHub release](https://img.shields.io/github/release/masakih/WKWebKitMuteExt.svg)](https://github.com/masakih/WKWebKitMuteExt/releases/latest)
[![Carthage compatible](https://img.shields.io/badge/Carthage-compatible-4BC51D.svg?style=flat)](https://github.com/masakih/MuteableWKWebView)


# MuteableWKWebView
Mute per WKWebView like Safari.

----
# How to use

Interface:
```objc
@interface WKWebView (HMMuteExtension)

@property (getter=isMuted) BOOL muted;

@end
```

MuteableWKWebView append mute property into WKWebView.

Usage:
```objc
WKWebView *webView;

// mute
webView.muted = YES;

// unmute
webView.muted = NO;
```
----

powered by https://github.com/hetima/HTSymbolHook.
