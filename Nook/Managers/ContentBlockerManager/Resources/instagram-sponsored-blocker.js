// Nook Content Blocker — Instagram Sponsored Post & Story Blocker
//
// Instagram marks sponsored feed posts and stories with a leaf text node reading exactly
// "Ad" in the post/story header (confirmed live, Sept 2026 — unlike Facebook's per-letter
// "Sponsored" spans, this is a plain text node). LABELS also covers "sponsored" and a few
// localizations in case placement or locale ever renders that instead.
(function() {
  'use strict';

  if (window.__nookIGAdLoaded) return;
  window.__nookIGAdLoaded = true;

  var TAG = '[NookIGAd]';

  var LABELS = {
    'ad': true, 'sponsored': true, 'gesponsert': true, 'publicidad': true,
    'sponsorisé': true, 'sponsorizzato': true, 'sponsoreret': true, 'sponsrad': true,
    'patrocinado': true, 'gesponsord': true, '広告': true, '광고': true, '赞助': true,
  };

  var POST_SEL = 'article';

  var hiddenCount = 0;

  function findAdLabel(root) {
    var stack = [root];
    while (stack.length) {
      var node = stack.pop();
      if (node.children && node.children.length) {
        for (var i = 0; i < node.children.length; i++) stack.push(node.children[i]);
        continue;
      }
      var t = (node.textContent || '').trim().toLowerCase();
      if (t && LABELS[t]) return node;
    }
    return null;
  }

  function scanFeed() {
    // Re-check every visible post on every scan rather than caching a per-node verdict:
    // Instagram's feed is virtualized and recycles <article> DOM nodes for different posts
    // as you scroll, so a node marked "ad" earlier can become a real post later — a cached
    // verdict would leave it hidden (or hide a future ad-labeled post's real predecessor)
    // forever. The feed is small enough on screen that re-scanning is cheap.
    var posts = document.querySelectorAll(POST_SEL);
    for (var i = 0; i < posts.length; i++) {
      var post = posts[i];
      var header = post.querySelector('header') || post;
      var label = findAdLabel(header);
      if (label) {
        if (post.getAttribute('data-nook-blocked') !== 'sponsored') {
          hiddenCount++;
          post.style.setProperty('display', 'none', 'important');
          post.setAttribute('data-nook-blocked', 'sponsored');
          console.log(TAG, 'HIDE #' + hiddenCount, 'label="' + label.textContent.trim() + '"');
        }
      } else if (post.getAttribute('data-nook-blocked') === 'sponsored') {
        post.style.removeProperty('display');
        post.removeAttribute('data-nook-blocked');
      }
    }
  }

  // --- Stories: advance past an ad as soon as it becomes the active story.
  // Stories are tap-driven, not keyboard-driven — a synthetic ArrowRight keydown does
  // nothing. Prefer the real next-story control (an explicit chevron button beside the
  // card on desktop — "Watch full reel / Right chevron" was seen live in a story's a11y
  // text); fall back to a coordinate tap in case the button isn't found.
  var advancedStories = new WeakSet();

  function advanceStory(card) {
    var next = document.querySelector('[aria-label="Next" i], [aria-label*="next" i][role="button"]');
    if (next) { next.click(); return; }
    var rect = card.getBoundingClientRect();
    var x = rect.left + rect.width * 0.88;
    var y = rect.top + rect.height * 0.5;
    var el = document.elementFromPoint(x, y);
    if (!el) return;
    ['pointerdown', 'mousedown', 'pointerup', 'mouseup', 'click'].forEach(function (type) {
      el.dispatchEvent(new MouseEvent(type, { bubbles: true, cancelable: true, clientX: x, clientY: y, view: window }));
    });
  }

  function scanStories() {
    if (location.pathname.indexOf('/stories/') !== 0) return;
    var player = document.querySelector('[aria-label="Video player"]');
    if (!player || advancedStories.has(player)) return;
    var card = player.closest('section') || player;
    var label = findAdLabel(card);
    if (label) {
      advancedStories.add(player);
      console.log(TAG, 'STORY AD, advancing:', label.textContent.trim());
      advanceStory(card);
    }
  }

  function scan() {
    scanFeed();
    scanStories();
  }

  var pending = false;
  function schedScan() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function () {
      pending = false;
      scan();
    });
  }

  var observer = new MutationObserver(function (mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var m = mutations[i];
      if (m.type === 'childList' && m.addedNodes.length) { schedScan(); return; }
    }
  });

  function start() {
    if (!document.body) {
      var bodyWatcher = new MutationObserver(function () {
        if (document.body) {
          bodyWatcher.disconnect();
          start();
        }
      });
      bodyWatcher.observe(document.documentElement, { childList: true });
      return;
    }
    console.log(TAG, 'started');
    observer.observe(document.body, { subtree: true, childList: true });
    scan();
  }

  start();
})();
