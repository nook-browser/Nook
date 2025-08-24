//
//  HTSymbolHook.m
//  HTSymbolHook
//
//  Copyright (c) 2013 hetima.
//  MIT License


/*
 This code is written considering 32bit, but tested only 64bit.
 */


#import <Foundation/Foundation.h>

enum HTSymbolHookImageNameMatchingRule {
    HTSymbolHookImageNameMatchingEqual=0,
    HTSymbolHookImageNameMatchingSuffix=1
};


@interface HTSymbolHook : NSObject

@property (nonatomic,strong,readonly) NSString* imageName;
@property (nonatomic,readonly) BOOL valid;

+ (id)symbolHookWithImageName:(NSString*)name;
+ (id)symbolHookWithImageNameSuffix:(NSString*)name;

- (void*)symbolPtrWithSymbolName:(NSString*)symbolName;
- (BOOL)overrideSymbol:(NSString*)symbolName withPtr:(void*)ptr reentryIsland:(void**)island;
- (BOOL)overrideSymbol:(NSString*)symbolName withPtr:(void*)ptr reentryIsland:(void**)island symbolIndexHint:(UInt32)seekStartIndex;

// for define seekStartIndex
- (UInt32)indexOfSymbol:(NSString*)symbolName;

// public for example, usually not used.
- (void*)symbolPtrWithSymbolName:(NSString*)symbolName startOffset:(UInt32)from endOffset:(UInt32)to;

@end
