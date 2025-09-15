//
//  HTSymbolHook.m
//  HTSymbolHook
//
//  Copyright (c) 2013 hetima.
//  MIT License

/*
 This code is written considering 32bit, but tested only 64bit.
 */

#if !__has_feature(objc_arc)
#error This file must be compiled with ARC
#endif

#import <mach-o/dyld.h>
#import <mach-o/nlist.h>
#import "HTSymbolHook.h"
#import "mach_override.h"

#if __LP64__
#define struct_mach_header struct mach_header_64
#define struct_segment_command struct segment_command_64
#define LC_SEGMENT_TYPE LC_SEGMENT_64
#define struct_nlist struct nlist_64
#else
#define struct_mach_header struct mach_header
#define struct_segment_command struct segment_command
#define LC_SEGMENT_TYPE LC_SEGMENT
#define struct_nlist struct nlist
#endif


@implementation HTSymbolHook
{
    intptr_t _slide;
    struct_mach_header* _mh;
    uint32_t _totalSymbols;
    vm_offset_t _symbolTableOffset;
    vm_offset_t _stringTableOffset;
    struct_nlist* _firstSymbolEntry;
}

+ (id)symbolHookWithImageName:(NSString*)name
{
    return [[HTSymbolHook alloc]initWithImageName:name matchingRule:HTSymbolHookImageNameMatchingEqual];
}

+ (id)symbolHookWithImageNameSuffix:(NSString*)name
{
    return [[HTSymbolHook alloc]initWithImageName:name matchingRule:HTSymbolHookImageNameMatchingSuffix];
}


- (id)initWithImageName:(NSString*)name matchingRule:(int)rule
{
    self = [super init];
    if (self) {
        _valid=NO;
        _mh=NULL;
        uint32_t i;
        
        //seek mach_header
        uint32_t cnt=_dyld_image_count();
        for (i=0; i<cnt; i++) {
            BOOL match;
            const char* imageName=_dyld_get_image_name(i);
            NSString* imageNameString=[NSString stringWithUTF8String:imageName];
            
            if (rule==HTSymbolHookImageNameMatchingSuffix) {
                match=[imageNameString hasSuffix:name];
            }else{ //HTSymbolHookImageNameMatchingEqual
                match=[imageNameString isEqualToString:name];
            }
                                 
            if (match) {
                _mh=(struct_mach_header*)_dyld_get_image_header(i);
                _slide=_dyld_get_image_vmaddr_slide(i);
                _imageName=imageNameString;
                break;
            }
        }
        
        //calc offset
        struct_segment_command *seglink_cmd=NULL;
        struct symtab_command *symtab_cmd=NULL;
        if (_mh) {
            struct_segment_command *seg;
            long i;
            
            seg = (struct_segment_command *)((char *)_mh + sizeof(struct_mach_header));
            for(i = 0; i < _mh->ncmds; i++){
                if(seg->cmd == LC_SYMTAB){
                    symtab_cmd=((struct symtab_command *)seg);
                    if (seglink_cmd) {
                        break;
                    }
                }else if(seg->cmd == LC_SEGMENT_TYPE && !strncmp(seg->segname, "__LINKEDIT", sizeof(seg->segname))){
                    seglink_cmd=seg;
                    if (symtab_cmd) {
                        break;
                    }
                }
                seg = (struct_segment_command *)((char *)seg + seg->cmdsize);
            }
        }
        
        //gather info
        if (seglink_cmd && symtab_cmd && symtab_cmd->nsyms > 0) {
            _totalSymbols=symtab_cmd->nsyms;
            _symbolTableOffset=seglink_cmd->vmaddr + symtab_cmd->symoff - seglink_cmd->fileoff + _slide;
            _stringTableOffset=seglink_cmd->vmaddr + symtab_cmd->stroff - seglink_cmd->fileoff + _slide;
            _firstSymbolEntry=(struct_nlist*)_symbolTableOffset;
            if (_totalSymbols && _firstSymbolEntry) {
                _valid=YES;
            }
        }
    }
    return self;
}

- (void*)symbolPtrWithSymbolName:(NSString*)symbolName
{
    return [self symbolPtrWithSymbolName:symbolName startOffset:0 endOffset:_totalSymbols];
}

- (void*)symbolPtrWithSymbolName:(NSString*)symbolName startOffset:(UInt32)from endOffset:(UInt32)to
{
    if (!_valid) {
        return NULL;
    }
    if (from>=_totalSymbols) {
        from=0;
    }
    if (to>_totalSymbols || from>0 || from>=to) {
        to=_totalSymbols;
    }
    void* result=NULL;
    UInt32 i;
    const char* seekSymbol=[symbolName cStringUsingEncoding:NSUTF8StringEncoding];
    struct_nlist* nlist=_firstSymbolEntry + from;
    for (i=from; i<to; i++) {
        char* name=(char*)_stringTableOffset + nlist->n_un.n_strx;
        
        if (strcmp(name, seekSymbol)==0) {
            result=(void*)nlist->n_value + _slide;
            return result;
        }

        ++nlist;
    }
    if (from>0) {
        result=[self symbolPtrWithSymbolName:symbolName startOffset:0 endOffset:from];
    }
    
    return result;
}

- (BOOL)overrideSymbol:(NSString*)symbolName withPtr:(void*)ptr reentryIsland:(void**)island
{
    return [self overrideSymbol:symbolName withPtr:ptr reentryIsland:island symbolIndexHint:0];
}

- (BOOL)overrideSymbol:(NSString*)symbolName withPtr:(void*)ptr reentryIsland:(void**)island symbolIndexHint:(UInt32)seekStartIndex
{
    void* symbolPtr=[self symbolPtrWithSymbolName:symbolName startOffset:seekStartIndex endOffset:0];
    if (symbolPtr) {
        mach_error_t error=mach_override_ptr(symbolPtr, ptr, island);
        if (!error) {
            return YES;
        }
    }
    return NO;
}

// for define seekStartIndex in advance
- (UInt32)indexOfSymbol:(NSString*)symbolName
{
    UInt32 i;
    const char* seekSymbol=[symbolName cStringUsingEncoding:NSUTF8StringEncoding];
    struct_nlist* nlist=_firstSymbolEntry;
    for (i=0; i<_totalSymbols; i++) {
        char* name=(char*)_stringTableOffset + nlist->n_un.n_strx;
        if (strcmp(name, seekSymbol)==0) {
            return i;
        }
        ++nlist;
    }
    // FIXME: same result with i==0
    return 0;
}

@end
