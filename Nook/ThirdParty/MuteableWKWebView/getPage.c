//
//  getPage.c
//  MuteableWKWebView
//
//  Created by Hori,Masaki on 2017/05/20.
//  Copyright © 2017年 Hori,Masaki. All rights reserved.
//

#include "getPage.h"

#include <objc/runtime.h>
#include <stdio.h>
#include <string.h>
#include <stdlib.h>

#if __has_feature(objc_arc)
#error This file must be compiled without ARC
#endif

const char *pagePropertyName = "_page";
const char *WKWebViewClassName = "WKWebView";

static bool checkPageProperty() {
    
    static bool foundPageProperty = false;
    if( foundPageProperty ) return true;
    
    static bool isFirst = true;
    if( !isFirst ) return false;
    isFirst = false;
    
    Class classObj = objc_getClass(WKWebViewClassName);
    if( classObj == Nil ) return false;
    
    unsigned int c = 0;
    Ivar *ivarP = class_copyIvarList(classObj, &c);
    
    for(int i = 0; i < c; i++) {
        const char *ivarName = ivar_getName(ivarP[i]);
        if( strncmp(pagePropertyName, ivarName, 5) == 0 ) {
            foundPageProperty = true;
            break;
        }
    }
    free(ivarP);
    
    return foundPageProperty;
}

void *getPage(id instance) {
    
    if( !checkPageProperty() ) {
        return NULL;
    }
    
    Class classObj = objc_getClass(WKWebViewClassName);
    Ivar ivar = class_getInstanceVariable(classObj, pagePropertyName);
    void *ptr = object_getIvar(instance, ivar);
    
    return ptr;
}
