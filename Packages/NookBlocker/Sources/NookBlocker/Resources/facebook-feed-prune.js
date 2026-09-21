// Removes items from Facebook's news feed and Marketplace feed before Relay stores them. Which
// items is set by window.__nookFBFilter, read on every parse so the scripts that set it can run
// in any order: ads (the content blocker), reels and suggested (Social Media tweaks). Both inject
// this file; the first copy installs the hook and later copies only add their flags.
// Facebook reads XHR bodies through clean iframe built-ins, but every feed payload (first-load
// ServerJS blocks and each streamed pagination line) still goes through this realm's JSON.parse.
// A feed ad is a Story node with a child object of __typename "SponsoredData" (the key name
// rotates); a Marketplace ad is a MarketplaceFeedAdStory.
//
// Relay streams one response as: a first payload with the connection's edges (e.g.
// data.viewer.news_feed.edges), then one payload per later edge (path [viewer, news_feed, edges, N]),
// each followed by $defer payloads under that edge (path [..., N, node, ...]). Later indices are
// renumbered past removed items so the list stays contiguous. A removed streamed item becomes a
// repeat of the previous item, which Relay stores again as a no-op. Defers under a removed item
// point at an index that never arrives, so Relay keeps them pending and never applies them.
(function () {
  'use strict';
  var flags = window.__nookFBFilter || {};
  if (window.__nookFBPrune) return;
  window.__nookFBPrune = true;

  var ORPHAN_BASE = 1000000;

  // Streamed connections: where the first payload keeps its edges, and the stream path prefix.
  var CONNECTIONS = [
    { root: ['viewer', 'news_feed'] },
    { root: ['marketplace_home_feed'] },
  ];

  function isAd(node) {
    if (node.__typename === 'MarketplaceFeedAdStory') return true;
    for (var k in node) {
      var v = node[k];
      if (v && typeof v === 'object' && v.__typename === 'SponsoredData') return true;
    }
    return false;
  }

  // Suggestion units ("People you may know"), and posts Facebook recommends from groups or pages
  // the viewer is not in: members' posts carry recommendation_context and
  // if_viewer_can_join_group as null.
  var SUGGESTION_UNIT = /PeopleYouMayKnow|YouShouldJoin|Suggest|Recommend/;
  var SUGGESTION_KEYS = { recommendation_context: true, if_viewer_can_join_group: true };

  function hasSuggestionKey(o, depth) {
    if (!o || typeof o !== 'object' || depth > 14) return false;
    for (var k in o) {
      var v = o[k];
      if (SUGGESTION_KEYS[k] && v !== null && v !== undefined) return true;
      if (v && typeof v === 'object' && hasSuggestionKey(v, depth + 1)) return true;
    }
    return false;
  }

  function isSuggested(node) {
    var t = node.__typename;
    if (t !== 'Story') return SUGGESTION_UNIT.test(t || '');
    return hasSuggestionKey(node.comet_sections, 0);
  }

  function shouldRemove(node) {
    if (!node || typeof node !== 'object') return false;
    return (flags.ads && isAd(node)) ||
      (flags.reels && node.__typename === 'ShowcaseFeedUnit') ||
      (flags.suggested && isSuggested(node));
  }

  function at(o, keys) {
    for (var i = 0; i < keys.length && o; i++) o = o[keys[i]];
    return o;
  }

  // The connection a stream path belongs to, if the path is [...root, 'edges', N, ...].
  function connectionFor(p) {
    if (!Array.isArray(p)) return null;
    for (var c = 0; c < CONNECTIONS.length; c++) {
      var root = CONNECTIONS[c].root, i = 0;
      while (i < root.length && p[i] === root[i]) i++;
      if (i === root.length && p[i] === 'edges' && typeof p[i + 1] === 'number') return CONNECTIONS[c];
    }
    return null;
  }

  // Per-connection state for the response currently streaming. Pages of one connection load one at a time.
  function reset(c) { c.removed = 0; c.newIndex = {}; c.orphaned = {}; c.lastItem = null; c.streaming = true; }

  function handleFirst(c, conn) {
    reset(c);
    var edges = conn.edges, kept = [];
    for (var i = 0; i < edges.length; i++) {
      if (shouldRemove(edges[i] && edges[i].node)) { c.orphaned[i] = true; c.removed++; }
      else { c.newIndex[i] = kept.length; kept.push(edges[i]); }
    }
    if (c.removed) conn.edges = kept;
  }

  // Returns the payload to hand back (the same object, edited, or a replacement).
  function handleStream(c, payload) {
    var d = payload.data, p = payload.path, idx = c.root.length + 1, n = p[idx];
    if (!c.streaming) return payload;

    if (p.length > idx + 1) { // $defer under an edge
      if (c.orphaned[n]) p[idx] = ORPHAN_BASE + n;
      else if (c.newIndex[n] !== undefined) p[idx] = c.newIndex[n];
      return payload;
    }

    if (shouldRemove(d && d.node)) { // streamed item to remove
      c.orphaned[n] = true;
      if (!c.lastItem) {
        // Nothing earlier in this response to repeat: keep the slot with a null node (Facebook
        // renders nothing for it; seen live) and let later removals repeat it.
        d.node = null;
        c.newIndex[n] = n - c.removed;
        p[idx] = n - c.removed;
        c.lastItem = { path: p.slice(), data: d };
        return payload;
      }
      c.removed++;
      var repeat = {};
      for (var k in payload) repeat[k] = payload[k];
      repeat.path = c.lastItem.path.slice();
      repeat.data = c.lastItem.data;
      return repeat;
    }

    c.newIndex[n] = n - c.removed;
    p[idx] = n - c.removed;
    c.lastItem = { path: p.slice(), data: d };
    return payload;
  }

  // A feed payload is either a stream item ({data, path}) or a first payload holding a connection.
  function handle(o) {
    var d = o.data;
    if (!d || typeof d !== 'object') return null;
    if (o.path !== undefined) {
      var c = connectionFor(o.path);
      return c ? handleStream(c, o) : null;
    }
    var found = false;
    for (var i = 0; i < CONNECTIONS.length; i++) {
      var conn = at(d, CONNECTIONS[i].root);
      if (conn && Array.isArray(conn.edges)) { handleFirst(CONNECTIONS[i], conn); found = true; }
    }
    return found ? o : null;
  }

  // Walks a parsed value and replaces feed payloads in place. Payloads sit at the top level,
  // under a one-key wrapper ({"q7z": payload}), or deep inside ServerJS __bbox.result.
  function visit(o, depth) {
    if (!o || typeof o !== 'object' || depth > 40) return o;
    var handled = handle(o);
    if (handled) return handled;
    if (Array.isArray(o)) {
      for (var i = o.length - 1; i >= 0; i--) {
        // Right-column "Sponsored" box: a plain list item, not part of the streamed feed.
        if (flags.ads && o[i] && o[i].__typename === 'AdsSideFeedUnit') { o.splice(i, 1); continue; }
        o[i] = visit(o[i], depth + 1);
      }
    } else {
      for (var k in o) o[k] = visit(o[k], depth + 1);
    }
    return o;
  }

  // The gate is deliberately narrow, and widening it to "anything containing
  // SponsoredData" is a trap. Facebook streams ~4KB decoys that hold no ad at all:
  //
  //   {"q7z":{"data":{"node":{"s":{"__typename":"SponsoredData"}}},
  //           "edges":[{"node":{"s":{"__typename":"SponsoredData"}}}],
  //           "require":[{"node":{"s":{"__typename":"SponsoredData"}}}],
  //           "p":"3f0a7c1b9e42d685..." (the same 20 hex chars repeated to pad),
  //           "extensions":{"is_final":true}}}
  //
  // Three stubs at the three paths a blocker prunes, no advertiser, no image, no
  // link, and a single-key wrapper whose name rotates. Measured on a live feed:
  // 34 payloads carried a sponsored marker, 9 carried a feed connection name, and
  // none carried both. Pruning one of these removes nothing and tells Facebook it
  // is being pruned. A real ad arrives under a connection this list names.
  var WANT = /"(news_feed|marketplace_home_feed|AdsSideFeedUnit)"/;
  window.__nookFBFilter = flags;
  var origParse = JSON.parse;
  JSON.parse = function (text) {
    var out = origParse.apply(this, arguments);
    if (out && typeof out === 'object' && typeof text === 'string' && WANT.test(text)) {
      try { out = visit(out, 0); } catch (e) {} // a malformed payload is left as Facebook sent it
    }
    return out;
  };
})();
