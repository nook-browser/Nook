//
//  getPage.h
//  MuteableWKWebView
//
//  Created by Hori,Masaki on 2017/05/20.
//  Copyright © 2017年 Hori,Masaki. All rights reserved.
//

#ifndef getPage_h
#define getPage_h

#include <objc/runtime.h>

/**
 Get WebPageProxy instance from instance of WKWebView.
 WebPageProxy class is C++ class.
 
 @param instance instance of WKWebView.
 @return return instance of WebPageProxy (C++ class).
 */
void *getPage(id instance);

#endif /* getPage_h */
