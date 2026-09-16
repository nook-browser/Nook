// Nook Content Blocker — Facebook Sponsored Post Blocker
(function() {
  'use strict';

  // Prevent double execution (WKUserScript + fallback injection)
  if (window.__nookFBAdLoaded) return;
  window.__nookFBAdLoaded = true;

  var TAG = '[NookFBAd]';

  var PRIVACY_ATTR_SEL = 'a[attributionsrc^="/privacy_sandbox/comet/register/source/"]';

  var POST_SELS = [
    '[role="article"]',
    '[data-pagelet*="FeedUnit"]',
    '[data-testid="fbfeed_story"]',
    '[aria-posinset]'
  ];
  var POST_SEL_STR = POST_SELS.join(',');

  var SPONSORED_LABELS = [
    'sponsored', 'publicidad', 'publicaciónpagada',
    'sponsorisé', 'commandité', 'gesponsert', 'patrocinado',
    'sponsorizzato', 'gesponsord', 'sponsoreret', 'sponsrad',
    'sponset', 'sponsoroitu', 'sponsorowane', 'sponzorováno',
    'szponzorált', 'спонсорирано', 'реклама',
    '赞助内容', '贊助', 'スポンサー', '광고',
    'ได้รับการสนับสนุน', 'đượctàitrợ', 'bersponsor',
    'प्रायोजित', 'ditaja', 'χορηγούμενο', 'promovare',
    'sponzorované', 'sponsorlu', 'ממומן',
  ];

  var labelSet = {};
  for (var i = 0; i < SPONSORED_LABELS.length; i++) labelSet[SPONSORED_LABELS[i]] = true;

  var processedAnchors = new WeakSet();
  var markedPosts = new WeakSet();
  var hiddenCount = 0;
  var scanCount = 0;

  function reconstructVisibleText(anchor) {
    var letters = [];
    var spans = anchor.querySelectorAll('span, b');
    for (var i = 0; i < spans.length; i++) {
      var sp = spans[i];
      var t = (sp.textContent || '').trim();
      if (t.length === 1) {
        var style = sp.getAttribute('style') || '';
        if (/display\s*:\s*none/i.test(style)) continue;
        if (/visibility\s*:\s*hidden/i.test(style)) continue;
        var r = sp.getBoundingClientRect();
        if (r && isFinite(r.left) && isFinite(r.top) && (r.width > 0 || r.height > 0)) {
          letters.push({ ch: t, x: Math.round(r.left), y: Math.round(r.top) });
        }
      }
    }
    letters.sort(function(a, b) { return a.y === b.y ? a.x - b.x : a.y - b.y; });
    var joined = '';
    for (var j = 0; j < letters.length; j++) joined += letters[j].ch;
    return joined.replace(/[^A-Za-z\u00C0-\u024F\u0400-\u04FF\u0590-\u05FF\u0600-\u06FF\u0E00-\u0E7F\u3000-\u9FFF\uAC00-\uD7AF]/g, '').toLowerCase();
  }

  function isLikelySponsored(text) {
    if (!text) return false;
    var lo = text.toLowerCase();
    if (labelSet[lo]) return true;
    if (lo.indexOf('sponsored') !== -1) return true;
    return false;
  }

  function getPostContainer(el) {
    if (!el) return null;
    var nearest = el.closest(POST_SEL_STR);
    if (nearest) return nearest;
    var cur = el, depth = 0;
    while (cur && cur !== document.body && depth++ < 15) {
      var r = cur.getBoundingClientRect();
      if (r && r.height >= 180 && r.width >= 280) return cur;
      cur = cur.parentElement;
    }
    return null;
  }

  function describePost(post) {
    var pagelet = post.getAttribute('data-pagelet') || '';
    var posinset = post.getAttribute('aria-posinset') || '';
    var id = pagelet || ('pos=' + posinset);
    var h3 = post.querySelector('h3, h4');
    var author = h3 ? (h3.textContent || '').trim().substring(0, 40) : '?';
    return id + ' "' + author + '"';
  }

  function hidePost(post, reason) {
    if (!post || markedPosts.has(post)) return;
    markedPosts.add(post);
    hiddenCount++;
    // Collapse the post completely so there's no gap in the feed
    post.style.setProperty('display', 'none', 'important');
    post.setAttribute('data-nook-blocked', 'sponsored');
    post.setAttribute('data-nook-reason', reason);
    console.log(TAG, 'HIDE #' + hiddenCount, reason, '|', describePost(post));
  }

  function scan() {
    scanCount++;
    var hidesBefore = hiddenCount;

    // Strategy 1: attributionsrc anchors — only process NEW ones
    var attrAnchors = document.querySelectorAll(PRIVACY_ATTR_SEL);
    for (var i = 0; i < attrAnchors.length; i++) {
      var a = attrAnchors[i];
      if (processedAnchors.has(a)) continue;
      processedAnchors.add(a);

      var post = getPostContainer(a);
      if (!post || markedPosts.has(post)) continue;

      var text = reconstructVisibleText(a);
      var label = (a.getAttribute('aria-label') || '').toLowerCase();

      if (isLikelySponsored(text)) {
        hidePost(post, 'attributionsrc+text("' + text + '")');
      } else if (labelSet[label] || label === 'advertiser') {
        hidePost(post, 'attributionsrc+aria("' + label + '")');
      } else {
        console.log(TAG, 'skip attributionsrc: text="' + text + '" aria="' + label + '"');
      }
    }

    // (Strategy 2, data-ad-rendering-role, removed 2026-09: Facebook puts it on organic posts
    //  too, so it only logged, and re-walking every post each scan caused load-time jank.)

    // Strategy 3: /ads/about links — only process NEW ones
    var adsAboutLinks = document.querySelectorAll('a[href*="/ads/about"]');
    for (var m = 0; m < adsAboutLinks.length; m++) {
      var aal = adsAboutLinks[m];
      if (processedAnchors.has(aal)) continue;
      processedAnchors.add(aal);

      var post5 = getPostContainer(aal);
      if (!post5 || markedPosts.has(post5)) continue;
      var aat = reconstructVisibleText(aal);
      if (isLikelySponsored(aat)) {
        hidePost(post5, 'ads-about+text("' + aat + '")');
      }
    }

    // Strategy 4: explicit ad-redirect CTA links (Meta's shared ad-click infra, seen on
    // both facebook.com and instagram.com sponsored posts) — only process NEW ones
    var adRedirectLinks = document.querySelectorAll('a[href*="/ads/ig_redirect/"]');
    for (var p = 0; p < adRedirectLinks.length; p++) {
      var arl = adRedirectLinks[p];
      if (processedAnchors.has(arl)) continue;
      processedAnchors.add(arl);

      var post6 = getPostContainer(arl);
      if (post6 && !markedPosts.has(post6)) {
        hidePost(post6, 'ads-ig-redirect-href');
      }
    }

    // (Strategy 5, data-ad-comet-preview / data-ad-preview, removed 2026-09: live logs showed it
    //  on organic posts: most of 48 live hides were group and friend posts.)

    var newHides = hiddenCount - hidesBefore;
    if (newHides > 0) {
      var totalPosts = document.querySelectorAll(POST_SEL_STR).length;
      console.log(TAG, 'scan #' + scanCount, '|', newHides, 'new hides |', hiddenCount + '/' + totalPosts, 'total blocked');
    }
  }

  // --- Stories: advance past an ad as soon as it becomes the active story.
  // Unverified — no Facebook story ad was seen live during probing (see
  // docs/superpowers/specs or CLAUDE.md's site-tweak probe method). Reuses the feed's
  // SPONSORED_LABELS text match; gated to the story-viewer dialog so it can't fire on an
  // ordinary inline feed video, which also gets aria-label="Video player".
  var advancedStories = new WeakSet();

  function findLeafLabel(root) {
    var stack = [root];
    while (stack.length) {
      var node = stack.pop();
      if (node.children && node.children.length) {
        for (var i = 0; i < node.children.length; i++) stack.push(node.children[i]);
        continue;
      }
      var t = (node.textContent || '').trim().toLowerCase();
      if (t && isLikelySponsored(t)) return node;
    }
    return null;
  }

  // Prefer the real next-story control (an explicit chevron button next to the story card
  // on desktop, not an in-video tap zone — a synthetic click inside the video just hits
  // pause/mute). Fall back to a coordinate tap in case the button isn't found.
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
    var player = document.querySelector('[aria-label="Video player"]');
    if (!player || advancedStories.has(player)) return;
    var dialog = player.closest('[role="dialog"]');
    if (!dialog) return; // inline feed video, not the story viewer
    var label = findLeafLabel(dialog);
    if (label) {
      advancedStories.add(player);
      console.log(TAG, 'STORY AD, advancing:', label.textContent.trim());
      advanceStory(dialog);
    }
  }

  // --- Observer (replaces setInterval — only scan when DOM changes) ---
  // Facebook's feed never virtualizes (it only grows as you scroll) and its DOM churns
  // constantly even for trivial state updates, so scanning on every single mutation batch
  // — even via requestAnimationFrame, which still fires up to 60x/sec — visibly slowed
  // scrolling. Nothing here needs sub-second latency; throttle to a few times a second.
  var pending = false;
  var lastRun = 0;
  var MIN_INTERVAL_MS = 400;
  function schedScan() {
    if (pending) return;
    pending = true;
    var wait = Math.max(0, MIN_INTERVAL_MS - (Date.now() - lastRun));
    setTimeout(function() {
      requestAnimationFrame(function() {
        pending = false;
        lastRun = Date.now();
        scan();
        scanStories();
      });
    }, wait);
  }

  var observer = new MutationObserver(function(mutations) {
    for (var i = 0; i < mutations.length; i++) {
      var m = mutations[i];
      if (m.type === 'childList' && m.addedNodes.length) { schedScan(); return; }
    }
  });

  function start() {
    if (!document.body) {
      // atDocumentStart: body doesn't exist yet, wait for it
      var bodyWatcher = new MutationObserver(function() {
        if (document.body) {
          bodyWatcher.disconnect();
          start();
        }
      });
      bodyWatcher.observe(document.documentElement, { childList: true });
      return;
    }
    console.log(TAG, 'started');
    // childList only — NOT attributes. Watching attributes causes an infinite loop:
    // hidePost() sets style/data-nook-* attributes → observer fires → scan() →
    // hidePost() again → repeat. childList is enough to catch new feed posts.
    observer.observe(document.body, {
      subtree: true,
      childList: true
    });
    scan();
    scanStories();
  }

  start();
})();
