// Licensed under GPL-3.0. See LICENSE.
//
//  BoostTweaks.swift
//  Nook
//

import Foundation
import NookBlocker
import NookSettings
import WebKit

/// Injects the user's Boosts for the page about to load. Stateless, like `YouTubeTweaks`.
@MainActor
public enum BoostTweaks {
    private static let styleMarker = "// Nook Boost Style"
    private static let scriptMarker = "// Nook Boost Script"
    // Styles go in their own world; scripts in another with no message handlers, so a Boost
    // script reaches neither the page's JS world nor any Nook bridge.
    private static let styleWorld = WKContentWorld.world(name: "NookBoostStyle")
    private static let scriptWorld = WKContentWorld.world(name: "NookBoostScript")

    /// Main-frame navigation hook. Changes apply from the page being loaded; the next
    /// navigation removes them again once a Boost stops matching.
    public static func apply(for url: URL, in webView: WKWebView, settings: NookSettingsService) {
        let matches = Boost.matching(url, in: settings.boosts)
        let css = matches.map(\.compiledCSS).filter { !$0.isEmpty }.joined(separator: "\n")
        let code = matches.filter { $0.scriptEnabled && !$0.script.isEmpty }.map(\.script)

        let styleSource = css.isEmpty ? nil : styleScript(css)
        let scriptSource = code.isEmpty ? nil : userScript(code)

        let ucc = webView.configuration.userContentController
        // Read everything from the lazily bridged array before removeAllUserScripts() (Release-only trap).
        let all = ucc.userScripts
        let currentStyle = all.first { $0.source.hasPrefix(styleMarker) }?.source
        let currentScript = all.first { $0.source.hasPrefix(scriptMarker) }?.source
        // The no-Boost path ends here without touching the controller.
        guard currentStyle != styleSource || currentScript != scriptSource else { return }

        let others = all.nookOwned.filter { !$0.source.hasPrefix(styleMarker) && !$0.source.hasPrefix(scriptMarker) }
        ucc.removeAllUserScripts()
        others.forEach { ucc.addUserScript($0) }
        if let styleSource {
            ucc.addUserScript(WKUserScript(source: styleSource, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: styleWorld))
        }
        if let scriptSource {
            ucc.addUserScript(WKUserScript(source: scriptSource, injectionTime: .atDocumentEnd, forMainFrameOnly: true, in: scriptWorld))
        }
    }

    /// Shows the edit on the open page now. The user scripts for later loads catch up in `apply`
    /// when the panel closes, so a slider drag never rewrites the controller.
    /// `draft` is an unsaved edit: it stands in for the saved Boost with its id, or joins the list
    /// when it is new, so nothing is written to settings while the person is still choosing.
    public static func preview(for url: URL, in webView: WKWebView, settings: NookSettingsService, draft: Boost? = nil) {
        var boosts = settings.boosts
        if let draft {
            if let i = boosts.firstIndex(where: { $0.id == draft.id }) { boosts[i] = draft } else { boosts.append(draft) }
        }
        let css = Boost.matching(url, in: boosts).map(\.compiledCSS).filter { !$0.isEmpty }.joined(separator: "\n")
        webView.evaluateJavaScript(styleJS(css), in: nil, in: styleWorld) { _ in }
    }

    /// Zap: lets the person click one element on the page and returns a CSS selector for it, or
    /// nil when they press Escape or call `cancelPick`. Nothing is hidden or saved here.
    public static func pickElement(in webView: WKWebView) async -> String? {
        let result = try? await webView.callAsyncJavaScript(zapJS, arguments: [:], in: nil, contentWorld: zapWorld)
        return (result as? String).flatMap { $0.isEmpty ? nil : $0 }
    }

    public static func cancelPick(in webView: WKWebView) {
        webView.evaluateJavaScript("window.__nookZapCancel&&window.__nookZapCancel()", in: nil, in: zapWorld) { _ in }
    }

    private static let zapWorld = WKContentWorld.world(name: "NookBoostZap")

    private static let zapJS = """
    return new Promise(function(resolve){
      var box=document.createElement('div');
      box.style.cssText='position:fixed;pointer-events:none;z-index:2147483647;border:2px solid #ff4d4f;background:rgba(255,77,79,.18);border-radius:4px;display:none';
      document.documentElement.appendChild(box);
      var cur=null, prevCursor=document.documentElement.style.cursor;
      document.documentElement.style.cursor='crosshair';
      function ok(el){return el&&el!==document.documentElement&&el!==document.body&&el!==box;}
      function sel(el){
        var parts=[];
        while(el&&el.nodeType===1&&el!==document.documentElement){
          if(el.id&&/^[A-Za-z][\\w-]*$/.test(el.id)&&document.querySelectorAll('#'+el.id).length===1){parts.unshift('#'+el.id);break;}
          var p=el.tagName.toLowerCase(),par=el.parentElement;
          if(par){var same=[].filter.call(par.children,function(c){return c.tagName===el.tagName;});if(same.length>1)p+=':nth-of-type('+(same.indexOf(el)+1)+')';}
          parts.unshift(p);el=par;
          if(document.querySelectorAll(parts.join('>')).length===1)break;
        }
        return parts.join('>');
      }
      function done(v){
        ['mousemove','click','keydown'].forEach(function(t){document.removeEventListener(t,h[t],true);});
        box.remove();document.documentElement.style.cursor=prevCursor;window.__nookZapCancel=null;resolve(v);
      }
      var h={
        mousemove:function(e){cur=e.target;if(!ok(cur)){box.style.display='none';return;}
          var r=cur.getBoundingClientRect();box.style.display='block';
          box.style.left=r.left+'px';box.style.top=r.top+'px';box.style.width=r.width+'px';box.style.height=r.height+'px';},
        click:function(e){e.preventDefault();e.stopPropagation();done(ok(e.target)?sel(e.target):'');},
        keydown:function(e){if(e.key==='Escape'){e.preventDefault();done('');}}
      };
      for(var t in h)document.addEventListener(t,h[t],true);
      window.__nookZapCancel=function(){done('');};
    });
    """

    /// One element, found by id, so a repeat run or an SPA navigation never adds a second.
    /// An empty stylesheet removes it.
    private static func styleJS(_ css: String) -> String {
        """
        (function(css){var s=document.getElementById('nook-boost-style');
        if(!css){if(s)s.remove();return;}
        if(!s){s=document.createElement('style');s.id='nook-boost-style';}
        s.textContent=css;(document.head||document.documentElement).appendChild(s);})(\(jsonString(css)));
        """
    }

    private static func styleScript(_ css: String) -> String {
        "\(styleMarker)\n\(styleJS(css))"
    }

    /// Each script runs in its own try, so one error neither stops the others nor reaches the page.
    private static func userScript(_ code: [String]) -> String {
        let body = code.map { "try{\n\($0)\n}catch(e){console.error('Nook Boost script:',e);}" }.joined(separator: "\n")
        return "\(scriptMarker)\n(function(){\n\(body)\n})();"
    }

    private static func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let array = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }
}
