// Licensed under GPL-3.0. See LICENSE.
//
//  BrowserProcessPool+macOS.swift
//  NookWeb
//
//  The web process settings Safari uses. WebKit takes them only through private API, so each
//  one is skipped when this WebKit lacks it.
//

#if os(macOS)
import WebKit

extension BrowserConfiguration {
    /// A pool that keeps a spare web process ready for the next page, suspends background
    /// processes under memory pressure, and sizes WebKit's caches for a primary web browser.
    static func applyProcessPool(to config: WKWebViewConfiguration) {
        let make = NSSelectorFromString("_processPoolWithConfiguration:")
        guard let configurationClass = NSClassFromString("_WKProcessPoolConfiguration") as? NSObject.Type,
              let poolClass = NSClassFromString("WKProcessPool") as AnyObject?,
              poolClass.responds(to: make)
        else { return }

        let configuration = configurationClass.init()
        for key in ["prewarmsProcessesAutomatically", "suspendsWebProcessesAggressivelyOnMemoryPressure"] {
            let setter = "set\(key.prefix(1).uppercased())\(key.dropFirst()):"
            if configuration.responds(to: NSSelectorFromString(setter)) {
                configuration.setValue(true, forKey: key)
            }
        }
        guard let pool = poolClass.perform(make, with: configuration)?.takeUnretainedValue() as? NSObject else { return }

        setPrimaryWebBrowserCacheModel(on: pool)
        let warm = NSSelectorFromString("_warmInitialProcess")
        if pool.responds(to: warm) { pool.perform(warm) }
        // Through KVC because `processPool` is deprecated; WebKit still runs pages in the pool it is given.
        config.setValue(pool, forKey: "processPool")
    }

    private static func setPrimaryWebBrowserCacheModel(on pool: NSObject) {
        guard let symbol = dlsym(dlopen(nil, RTLD_LAZY), "WKContextSetCacheModel") else { return }
        typealias SetCacheModel = @convention(c) (UnsafeRawPointer, UInt32) -> Void
        let primaryWebBrowser: UInt32 = 2
        // WKProcessPool is the Objective-C wrapper behind the C API's WKContextRef.
        unsafeBitCast(symbol, to: SetCacheModel.self)(Unmanaged.passUnretained(pool).toOpaque(), primaryWebBrowser)
    }
}
#endif
