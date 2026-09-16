// Nook Content Blocker: remove sponsored stories from Facebook feed data before Relay stores it.
// Facebook reads XHR bodies through clean iframe built-ins, but every feed payload (first-load
// ServerJS blocks and each streamed pagination line) still goes through this realm's JSON.parse.
// An ad is a Story node with a child object of __typename "SponsoredData" (the key name rotates).
//
// Relay streams one response as: a first payload with data.viewer.news_feed.edges, then one
// payload per later edge (path [viewer, news_feed, edges, N]), each followed by $defer payloads
// under that edge (path [..., N, node, ...]). Ads are removed and later indices renumbered so the
// list stays contiguous; a streamed ad becomes a repeat of the previous item, which Relay stores
// again as a no-op; defers under an ad point at an index that never arrives, so Relay keeps them
// pending and never applies them.
(function () {
  'use strict';
  if (window.__nookFBPrune) return;
  window.__nookFBPrune = true;

  var ORPHAN_BASE = 1000000;

  function isAd(node) {
    if (!node || typeof node !== 'object') return false;
    for (var k in node) {
      var v = node[k];
      if (v && typeof v === 'object' && v.__typename === 'SponsoredData') return true;
    }
    return false;
  }

  function edgeIndex(p) {
    return Array.isArray(p) && p.length >= 4 && p[0] === 'viewer' && p[1] === 'news_feed' && p[2] === 'edges' &&
      typeof p[3] === 'number' ? p[3] : -1;
  }

  // State for the response currently streaming. Feed pages load one at a time.
  var removed = 0, newIndex = {}, orphaned = {}, lastItem = null, streaming = false;

  // Returns the payload to hand back (the same object, edited, or a replacement).
  function handle(payload) {
    var d = payload.data;
    var edges = !payload.path && d && d.viewer && d.viewer.news_feed && d.viewer.news_feed.edges;
    if (Array.isArray(edges)) {
      removed = 0; newIndex = {}; orphaned = {}; lastItem = null; streaming = true;
      var kept = [];
      for (var i = 0; i < edges.length; i++) {
        if (isAd(edges[i] && edges[i].node)) { orphaned[i] = true; removed++; }
        else { newIndex[i] = kept.length; kept.push(edges[i]); }
      }
      if (removed) d.viewer.news_feed.edges = kept;
      return payload;
    }

    var n = edgeIndex(payload.path);
    if (n < 0 || !streaming) return payload;

    if (payload.path.length > 4) { // $defer under an edge
      if (orphaned[n]) payload.path[3] = ORPHAN_BASE + n;
      else if (newIndex[n] !== undefined) payload.path[3] = newIndex[n];
      return payload;
    }

    if (isAd(d && d.node)) { // streamed ad
      orphaned[n] = true; removed++;
      // ponytail: an ad before any kept item in its response falls back to a null node, which broke
      // rendering once for a first-batch ad. Carry over the previous page's last item if this shows up.
      if (!lastItem) { d.node = null; return payload; }
      var repeat = {};
      for (var k in payload) repeat[k] = payload[k];
      repeat.path = lastItem.path.slice();
      repeat.data = lastItem.data;
      return repeat;
    }

    newIndex[n] = n - removed;
    payload.path[3] = n - removed;
    lastItem = { path: payload.path.slice(), data: d };
    return payload;
  }

  function isFeedPayload(o) {
    var d = o.data;
    if (!d || typeof d !== 'object') return false;
    if (o.path !== undefined) return edgeIndex(o.path) >= 0;
    return !!(d.viewer && d.viewer.news_feed && Array.isArray(d.viewer.news_feed.edges));
  }

  // Walks a parsed value and replaces feed payloads in place. Payloads sit at the top level,
  // under a one-key wrapper ({"q7z": payload}), or deep inside ServerJS __bbox.result.
  function visit(o, depth) {
    if (!o || typeof o !== 'object' || depth > 40) return o;
    if (isFeedPayload(o)) return handle(o);
    if (Array.isArray(o)) {
      for (var i = o.length - 1; i >= 0; i--) {
        // Right-column "Sponsored" box: a plain list item, not part of the streamed feed.
        if (o[i] && o[i].__typename === 'AdsSideFeedUnit') { o.splice(i, 1); continue; }
        o[i] = visit(o[i], depth + 1);
      }
    } else {
      for (var k in o) o[k] = visit(o[k], depth + 1);
    }
    return o;
  }

  var origParse = JSON.parse;
  JSON.parse = function (text) {
    var out = origParse.apply(this, arguments);
    if (out && typeof out === 'object' && typeof text === 'string' && (text.indexOf('"news_feed"') !== -1 || text.indexOf('"AdsSideFeedUnit"') !== -1)) {
      try { out = visit(out, 0); } catch (e) {} // a malformed payload is left as Facebook sent it
    }
    return out;
  };
})();
