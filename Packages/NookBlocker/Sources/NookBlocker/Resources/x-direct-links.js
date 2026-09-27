// Points X's outbound links at their destination instead of t.co, so a click skips X's
// redirect and its click logging. Every API response reaches this realm's JSON.parse as XHR
// text, and each t.co link arrives beside its destination in a link entity:
// {"url": "https://t.co/…", "expanded_url": "https://…", "display_url": …, "indices": […]}.
// Only `url` (entities) and `string_value` (a card's card_url) are rewritten. Post text keeps
// its t.co, since entity indices point into it, and links into X itself stay as they are.
(function () {
  'use strict';
  if (window.__nookXDirectLinks) return;
  window.__nookXDirectLinks = true;

  var TCO = 'https://t.co/';
  var INTERNAL = /^https?:\/\/([^\/]*\.)?(x|twitter)\.com(\/|$)/i;
  var REWRITTEN = { url: true, string_value: true };

  function rewrite(root) {
    var destinations = {};
    var slots = [];
    (function walk(node, depth) {
      if (depth > 64) return;
      for (var key in node) {
        var value = node[key];
        if (typeof value === 'string') {
          if (REWRITTEN[key] && value.lastIndexOf(TCO, 0) === 0) slots.push(node, key);
        } else if (value && typeof value === 'object') {
          walk(value, depth + 1);
        }
      }
      var expanded = node.expanded_url;
      if (typeof node.url === 'string' && node.url.lastIndexOf(TCO, 0) === 0 && typeof expanded === 'string'
          && /^https?:\/\//i.test(expanded) && !INTERNAL.test(expanded)) {
        destinations[node.url] = expanded;
      }
    })(root, 0);
    for (var i = 0; i < slots.length; i += 2) {
      var destination = destinations[slots[i][slots[i + 1]]];
      if (destination) slots[i][slots[i + 1]] = destination;
    }
  }

  var origParse = JSON.parse;
  JSON.parse = function (text) {
    var out = origParse.apply(this, arguments);
    if (out && typeof out === 'object' && typeof text === 'string'
        && text.indexOf('"expanded_url"') !== -1 && text.indexOf(TCO) !== -1) {
      try { rewrite(out); } catch (e) {} // a payload this does not understand is left as X sent it
    }
    return out;
  };
})();
