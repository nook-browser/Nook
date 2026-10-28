// Licensed under GPL-3.0. See LICENSE.
//
//  BoostTweaks.swift
//  Nook
//

import Foundation
import NookBlocker
import NookSettings
import WebKit

/// Applies the user's Boosts. Stateless apart from the set of controllers already installed.
@MainActor
public enum BoostTweaks {
    private static let styleMarker = "// Nook Boost Style"
    // Styles go in their own world; scripts in another with no message handlers, so a Boost
    // script reaches neither the page's JS world nor any Nook bridge.
    private static let styleWorld = WKContentWorld.world(name: "NookBoostStyle")
    private static let scriptWorld = WKContentWorld.world(name: "NookBoostScript")
    private static let handlerName = "nookBoostStyle"

    private static let installed = NSHashTable<WKUserContentController>.weakObjects()
    private static var zapKey: String?

    /// Main-frame navigation hook. Installs the style script once per controller and returns:
    /// nothing is rewritten on a navigation or a Boost change.
    public static func apply(for url: URL, in webView: WKWebView, settings: NookSettingsService, blocker: ContentBlockerManager) {
        let ucc = webView.configuration.userContentController
        if !installed.contains(ucc) {
            installed.add(ucc)
            ucc.addScriptMessageHandler(StyleHandler(settings: settings), contentWorld: styleWorld, name: handlerName)
            ucc.addUserScript(WKUserScript(source: styleScriptSource, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: styleWorld))
        }
        syncZapList(settings: settings, blocker: blocker)
    }

    /// The user's zaps as their own small rule list in the blocker, rebuilt only when they change.
    public static func syncZapList(settings: NookSettingsService, blocker: ContentBlockerManager) {
        Task {
            await settings.waitForBoosts()
            let lines = Boost.zapFilterLines(settings.boosts)
            let key = lines.joined(separator: "\n")
            guard key != zapKey else { return }
            zapKey = key
            // A failed compile clears the key so the next navigation tries again.
            if await !blocker.setUserCosmeticRules(lines) { zapKey = nil }
        }
    }

    /// Runs the page's enabled Boost scripts once it has loaded. Boosts with scripts are off
    /// until the person turns each one on, and only matching hosts get any.
    public static func runScripts(for url: URL, in webView: WKWebView, settings: NookSettingsService) {
        Task {
            await settings.waitForBoosts()
            for boost in Boost.matching(url, in: settings.boosts) where boost.scriptEnabled && !boost.script.isEmpty {
                // The page may have navigated while the Boosts loaded or an earlier script ran.
                guard let now = webView.url?.host?.lowercased(), now == url.host?.lowercased() else { return }
                _ = try? await webView.callAsyncJavaScript(
                    "try {\n\(boost.script)\n} catch (e) { console.error('Nook Boost script:', e); }",
                    arguments: [:], in: nil, contentWorld: scriptWorld)
            }
        }
    }

    /// Answers the style script's question from the isolated world. The frame is checked by
    /// WebKit's `frameInfo`, never by anything in the message, and the host comes from that
    /// frame's own request.
    private final class StyleHandler: NSObject, WKScriptMessageHandlerWithReply {
        private weak var settings: NookSettingsService?
        init(settings: NookSettingsService) { self.settings = settings }

        func userContentController(_ userContentController: WKUserContentController, didReceive message: WKScriptMessage) async -> (Any?, String?) {
            guard message.frameInfo.isMainFrame, let url = message.frameInfo.request.url, let settings else { return ("", nil) }
            await settings.waitForBoosts()
            return (BoostTweaks.css(for: url, boosts: settings.boosts), nil)
        }
    }

    static func css(for url: URL, boosts: [Boost]) -> String {
        Boost.css(for: url, in: boosts)
    }

    /// Document start: asks for this host's CSS and keeps one `<style>`. The edit path
    /// (`preview`) writes the same element.
    private static var styleScriptSource: String {
        """
        \(styleMarker)
        (function(){
          var h=window.webkit&&window.webkit.messageHandlers&&window.webkit.messageHandlers.\(handlerName);
          if(!h)return;
          h.postMessage(1).then(function(css){\(styleApplier)},function(){});
        })();
        """
    }

    /// Uses the reply named `css`. One element, found by id, so a repeat never adds a second;
    /// an empty reply removes it.
    private static let styleApplier = """
    var s=document.getElementById('nook-boost-style');
    if(!css){if(s)s.remove();return;}
    if(s&&s.textContent===css)return;
    if(!s){s=document.createElement('style');s.id='nook-boost-style';}
    s.textContent=css;
    var p=document.head||document.documentElement;
    if(p)p.appendChild(s);
    else document.addEventListener('DOMContentLoaded',function(){if(!document.getElementById('nook-boost-style'))(document.head||document.documentElement).appendChild(s);},{once:true});
    """

    /// Shows the edit on the open page now; nothing is written anywhere. `draft` is an unsaved
    /// edit: it stands in for the saved Boost with its id, or joins the list when it is new.
    public static func preview(for url: URL, in webView: WKWebView, settings: NookSettingsService, draft: Boost? = nil) {
        var boosts = settings.boosts
        if let draft {
            if let i = boosts.firstIndex(where: { $0.id == draft.id }) { boosts[i] = draft } else { boosts.append(draft) }
        }
        let css = css(for: url, boosts: boosts)
        webView.evaluateJavaScript("(function(css){\(styleApplier)})(\(jsonString(css)));", in: nil, in: styleWorld) { _ in }
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

    private static func jsonString(_ s: String) -> String {
        guard let data = try? JSONSerialization.data(withJSONObject: [s]),
              let array = String(data: data, encoding: .utf8)
        else { return "\"\"" }
        return String(array.dropFirst().dropLast())
    }
}
