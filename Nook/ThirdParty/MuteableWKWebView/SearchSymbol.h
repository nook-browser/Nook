//
//  SearchSymbol.h
//  MuteableWKWebView
//
//  Created by Hori,Masaki on 2017/05/21.
//  Copyright © 2017年 Hori,Masaki. All rights reserved.
//

#ifndef SearchSymbol_h
#define SearchSymbol_h

#import <Foundation/Foundation.h>

/**
 Description

 @param imagePath image path that search in.
 @param hints hint of function name or class name.
 @return return symbol name. return nil if not found.
 */
NSString *searchSymbol(NSString* imagePath, NSArray<NSString *> *hints);

#endif /* SearchSymbol_h */
