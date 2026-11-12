// Licensed under GPL-3.0. See LICENSE.
//
//  RedditTweaks.swift
//  Nook
//
//  Created by Bain Gurley on 22/10/2026.
//

import Foundation
import NookBlocker
import NookSettings
import WebKit

/// Opens Reddit feeds sorted by Hot instead of Best. Subreddit and custom feed loads are
/// redirected in `decidePolicyFor`, and a click listener rewrites their links for Reddit's
/// in-page navigations. The home feed has no Hot sort any more (its `/hot/` redirects to Best),
/// so the script swaps its posts for the old listing's `/hot.json`, each drawn by Reddit's own
/// `partial-feed-post` card.
@MainActor
public enum RedditTweaks {
    private static let marker = "// Nook Reddit Tweaks"
    // Page world: the Hot item calls the sort dropdown's own methods.
    private static let world = WKContentWorld.page

    // Mirrors hotURL(for:settings:).
    private static let script = #"""
    // Nook Reddit Tweaks
    (() => {
      if (!/^(www\.)?reddit\.com$/.test(location.hostname)) return;
      const feed = /^\/(r\/[^/]+\/|user\/[^/]+\/m\/[^/]+\/)$/;
      document.addEventListener('click', (e) => {
        const a = e.composedPath().find((n) => n instanceof HTMLAnchorElement && n.href);
        if (!a) return;
        const u = new URL(a.href);
        const path = u.pathname.endsWith('/') ? u.pathname : u.pathname + '/';
        if (u.host !== location.host || !feed.test(path)) return;
        u.pathname = path + 'hot/';
        a.href = u.href;
      }, true);

      // Home's Following feed (For You is not subscriptions). Reddit dropped its Hot sort, so
      // the dropdown gets a Hot item back; the choice is kept per browser.
      const HOME = 'shreddit-feed[reload-url*="home-feed"][reload-url*="feed=following"]';
      const KEY = 'nook.redditHomeSort';
      const wantsHot = () => { try { return localStorage.getItem(KEY) !== 'reddit'; } catch { return true; } };
      const remember = (mode) => { try { localStorage.setItem(KEY, mode); } catch {} };

      // Hide Reddit's own posts until the Hot ones replace them.
      const style = document.createElement('style');
      style.textContent = `${HOME}:not([data-nook-hot]) > :is(article, hr, shreddit-ad-post) { visibility: hidden }`;
      style.disabled = !wantsHot();
      (document.head || document.documentElement).append(style);

      const card = (id) => fetch(`/svc/shreddit/partial-feed-post/${id}?render-mode=partial&postViewContext=AggregateFeed&feedViewType=cardView`)
        .then((r) => (r.ok ? r.text() : '')).catch(() => '');
      const hot = (after) => fetch(`/hot.json?limit=10&raw_json=1${after ? `&after=${after}` : ''}`)
        .then((r) => { if (!r.ok) throw new Error(r.status); return r.json(); }).then((j) => j.data);

      // Home's HTML streams for over a second, so ask for the first page before the feed exists.
      let early = location.pathname === '/' && wantsHot() ? hot(null) : null;
      early?.catch(() => {});
      setTimeout(() => { early = null; }, 30000);

      const page = async (state) => {
        // Picking another sort refills the feed and drops the sentinel.
        if (!state.sentinel.isConnected) state.done = true;
        if (state.loading || state.done) return;
        state.loading = true;
        try {
          const first = !state.after;
          const data = await (first && early ? early : hot(state.after));
          if (first) early = null;
          const ids = data.children.map((c) => c.data.name).filter((id) => !state.seen.has(id));
          ids.forEach((id) => state.seen.add(id));
          const cards = ids.map(card);
          const range = document.createRange();
          range.selectNodeContents(state.feed);
          let cleared = !first;
          // Each post goes in as soon as it and the ones above it arrive, so one slow card holds
          // back only the posts under it. A partial is a loader, the <article> and its <hr>.
          for (const c of cards) {
            const html = await c;
            if (!state.sentinel.isConnected) break;
            if (!html) continue;
            if (!cleared) {
              for (const el of [...state.feed.children]) {
                if (/^(ARTICLE|HR|SHREDDIT-AD-POST|FACEPLATE-LOADER)$/.test(el.tagName) || el.slot === 'load-after') el.remove();
              }
              cleared = true;
            }
            state.feed.insertBefore(range.createContextualFragment(html), state.sentinel);
            state.feed.dataset.nookHot = '';
          }
          state.after = data.after;
          state.done = !data.after;
        } catch {
          state.done = true;
        } finally {
          state.loading = false;
          state.feed.dataset.nookHot = '';
        }
        // The observer only reports changes, so keep going while the end is still near.
        if (!state.done && state.sentinel.getBoundingClientRect().top < innerHeight + 1500) setTimeout(() => page(state));
      };

      const take = (feed) => {
        delete feed.dataset.nookHot;
        const sentinel = document.createElement('div');
        feed.append(sentinel);
        const state = { feed, sentinel, after: null, seen: new Set(), loading: false, done: false };
        new IntersectionObserver((entries) => {
          if (entries.some((e) => e.isIntersecting)) page(state);
        }, { rootMargin: '1500px' }).observe(sentinel);
        page(state);
      };

      // Clone Reddit's Best item into a Hot item, and mark Hot chosen while it shows.
      const dropdown = () => document.querySelector('shreddit-sort-dropdown[sort-event="feed-sort-change"]');
      const addHotItem = (d) => {
        const best = d.querySelector('data[value="BEST"]');
        if (!best || d.querySelector('data[value="HOT"]')) return;
        const hot = best.cloneNode(true);
        hot.setAttribute('value', 'HOT');
        hot.querySelector('.text-body-2').textContent = 'Hot';
        best.after(hot);
      };
      const selectHot = (d) => {
        d.silentlySelectItemByValue?.('HOT');
        for (const item of d.querySelectorAll('data')) {
          const on = item.getAttribute('value') === 'HOT';
          item.querySelector('li')?.toggleAttribute('rpl-selected', on);
          const row = item.querySelector('[aria-selected]');
          row?.setAttribute('aria-selected', String(on));
          row?.classList.toggle('bg-neutral-background-selected', on);
        }
      };

      document.addEventListener('click', (e) => {
        const item = e.target.closest?.('shreddit-sort-dropdown[sort-event="feed-sort-change"] data');
        const feed = document.querySelector(HOME);
        if (!item || !feed) return;
        if (item.getAttribute('value') !== 'HOT') { remember('reddit'); style.disabled = true; return; }
        // Reddit's handler would ask its own feed for HOT, which it ignores.
        e.stopImmediatePropagation();
        e.preventDefault();
        remember('hot');
        style.disabled = false;
        document.body.click();
        selectHot(item.closest('shreddit-sort-dropdown'));
        take(feed);
      }, true);

      const find = () => {
        const d = dropdown();
        if (d) addHotItem(d);
        const feed = document.querySelector(`${HOME}:not([data-nook-hot-taken])`);
        if (!feed) return;
        feed.dataset.nookHotTaken = '';
        if (!wantsHot()) return;
        take(feed);
        if (d) selectHot(d);
      };
      // Reddit mutates constantly; look once per frame at most.
      let queued = false;
      new MutationObserver(() => {
        if (queued) return;
        queued = true;
        requestAnimationFrame(() => { queued = false; find(); });
      }).observe(document.documentElement, { childList: true, subtree: true });
      find();
    })();
    """#

    /// The Hot version of a sortless subreddit or custom feed URL.
    public static func hotURL(for url: URL, settings: NookSettingsService) -> URL? {
        guard settings.redditSortHot,
              let host = url.host?.lowercased(), host == "reddit.com" || host == "www.reddit.com",
              var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        else { return nil }
        let parts = components.path.split(separator: "/")
        let isFeed = (parts.count == 2 && parts[0] == "r")
            || (parts.count == 4 && parts[0] == "user" && parts[2] == "m")
        guard isFeed else { return nil }
        components.path = "/" + parts.map { "\($0)/" }.joined() + "hot/"
        return components.url
    }

    /// Main-frame navigation hook, next to FacebookTweaks. The script gates on hostname itself,
    /// so it is only rewritten when the setting changes.
    public static func apply(in webView: WKWebView, settings: NookSettingsService) {
        let ucc = webView.configuration.userContentController
        // Read everything from the lazily bridged array before removeAllUserScripts (Release-only trap).
        let all = ucc.userScripts
        let installed = all.contains { $0.source.hasPrefix(marker) }
        guard installed != settings.redditSortHot else { return }
        let others = all.nookOwned.filter { !$0.source.hasPrefix(marker) }
        ucc.resetUserScripts(to: others)
        if settings.redditSortHot {
            ucc.addUserScript(WKUserScript(source: script, injectionTime: .atDocumentStart, forMainFrameOnly: true, in: world))
        }
    }
}
