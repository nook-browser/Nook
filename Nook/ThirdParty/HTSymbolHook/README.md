# HTSymbolHook

HTSymbolHook is Objective-C wrapper of [mach_override](https://github.com/rentzsch/mach_override).  
In addítion, It can override symbol by name (even non-exported!).


#Usage
Tested on OS X 10.8.5 64bit with ARC.

Symbol name must contain underscore prefix. So use entire name by `nm` output. (e.g. specify `@"_NSClassFromString"` not `@"NSClassFromString"`)

```objc
HTSymbolHook* hook=[HTSymbolHook symbolHookWithImageNameSuffix:@"/FrameworkName"];
[hook overrideSymbol:@"_symbol_name"
    withPtr:(void*)replace_function
    reentryIsland:(void**)&original_function];

```

If you check symbol index in advance,

```objc
UInt32 correctIndex=[hook indexOfSymbol:@"_symbol_name"];
```

Then It can be used as needle for speed.

```objc
UInt32 seekStartIndex=12345-20;
[hook overrideSymbol:@"_symbol_name"
    withPtr:(void*)replace_function
    reentryIsland:(void**)&original_function
    symbolIndexHint:seekStartIndex];

```

# Author

http://hetima.com/  
https://twitter.com/hetima

# License
HTSymbolHook  
MIT License. Copyright (c) 2013 hetima.

[mach_override](https://github.com/rentzsch/mach_override)  
(c) 2003-2012 Jonathan 'Wolf' Rentzsch