// Nook Content Blocker: remove Instagram feed and story ads from data before Relay stores it.
// Instagram responses are single JSON documents parsed with this realm's JSON.parse (the
// first-load ServerJS blocks too). Feed ads are timeline edges whose node.ad is set (organic
// posts sit under node.explore_story or node.media); story ads arrive separately in
// xdt_injected_story_units.ad_media_items.
(function () {
  'use strict';
  if (window.__nookIGPrune) return;
  window.__nookIGPrune = true;

  var FEED = 'xdt_api__v1__feed__timeline__connection';
  var STORY_ADS = 'xdt_injected_story_units';

  function visit(o, depth) {
    if (!o || typeof o !== 'object' || depth > 40) return;
    if (Array.isArray(o)) { for (var i = 0; i < o.length; i++) visit(o[i], depth + 1); return; }
    var feed = o[FEED];
    if (feed && Array.isArray(feed.edges)) {
      feed.edges = feed.edges.filter(function (e) { return !(e && e.node && e.node.ad); });
    }
    var units = o[STORY_ADS];
    if (units && Array.isArray(units.ad_media_items)) units.ad_media_items = [];
    for (var k in o) visit(o[k], depth + 1);
  }

  var origParse = JSON.parse;
  JSON.parse = function (text) {
    var out = origParse.apply(this, arguments);
    if (out && typeof out === 'object' && typeof text === 'string' &&
        (text.indexOf(FEED) !== -1 || text.indexOf(STORY_ADS) !== -1)) {
      try { visit(out, 0); } catch (e) {} // a malformed payload is left as Instagram sent it
    }
    return out;
  };
})();
