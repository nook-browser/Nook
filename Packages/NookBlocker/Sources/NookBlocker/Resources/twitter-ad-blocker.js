// Nook Content Blocker — Twitter/X Promoted Post Blocker
(function() {
  'use strict';

  // Prevent double execution (WKUserScript + fallback injection)
  if (window.__nookTwitterAdLoaded) return;
  window.__nookTwitterAdLoaded = true;

  var TAG = '[NookXAd]';

  // Timeline tweet selectors
  var TWEET_SEL = 'article[data-testid="tweet"]';
  var CELL_SEL = '[data-testid="cellInnerDiv"]';
  var TWEET_TEXT_SEL = '[data-testid="tweetText"]';

  // "Ad" badge labels across languages — Twitter uses short labels
  // English changed from "Promoted" to "Ad" in 2023
  var AD_LABELS = [
    'ad', 'ads', 'promoted',
    'anuncio', 'publicidad',           // Spanish
    'publicité',                        // French
    'anzeige',                          // German
    'pubblicità', 'annuncio',          // Italian
    'publicidade', 'anúncio',          // Portuguese
    'gesponsord', 'advertentie',       // Dutch
    'sponsrad', 'annons',              // Swedish
    'sponset', 'reklame',              // Danish/Norwegian
    'mainos', 'sponsoroitu',           // Finnish
    'promowane', 'reklama',            // Polish
    'sponzorováno',                    // Czech
    'hirdetés', 'szponzorált',         // Hungarian
    'promovat', 'reclamă',             // Romanian
    'реклама',                          // Russian
    'tanıtım', 'reklam',              // Turkish
    'إعلان',                            // Arabic
    'מודעה', 'פרסומת',                   // Hebrew
    'プロモーション', '広告',              // Japanese
    '프로모션', '광고',                   // Korean
    '推广', '广告',                      // Chinese Simplified
    '推廣', '廣告',                      // Chinese Traditional
    'โปรโมต', 'โฆษณา',                 // Thai
    'quảng cáo', 'được quảng bá',     // Vietnamese
    'प्रचारित', 'विज्ञापन',              // Hindi
    'dipromosikan', 'iklan',           // Indonesian/Malay
    'διαφήμιση', 'χορηγούμενο',        // Greek
  ];

  var labelSet = {};
  for (var i = 0; i < AD_LABELS.length; i++) labelSet[AD_LABELS[i]] = true;

  var processedCells = new WeakSet();
  var hiddenCount = 0;
  var scanCount = 0;

  function isAdLabel(text) {
    if (!text) return false;
    var normalized = text.trim().toLowerCase();
    return !!labelSet[normalized];
  }

  function getCellContainer(el) {
    if (!el) return null;
    var cur = el;
    while (cur && cur !== document.body) {
      if (cur.dataset && cur.dataset.testid === 'cellInnerDiv') return cur;
      cur = cur.parentElement;
    }
    return null;
  }

  function describePost(article) {
    var nameEl = article.querySelector('[data-testid="User-Name"]');
    var name = nameEl ? (nameEl.textContent || '').trim().substring(0, 50) : '?';
    return '"' + name + '"';
  }

  function hideCell(cell, article, reason) {
    if (!cell || processedCells.has(cell)) return;
    processedCells.add(cell);
    hiddenCount++;
    cell.style.setProperty('display', 'none', 'important');
    cell.setAttribute('data-nook-blocked', 'ad');
    cell.setAttribute('data-nook-reason', reason);
    var desc = article ? describePost(article) : '(no article)';
    console.log(TAG, 'HIDE #' + hiddenCount, reason, '|', desc);
  }

  function scan() {
    scanCount++;
    var hidesBefore = hiddenCount;

    // Strategy 1: placementTracking containers (most reliable)
    // Twitter wraps promoted content in elements with this data-testid
    var trackingEls = document.querySelectorAll('[data-testid="placementTracking"]');
    for (var i = 0; i < trackingEls.length; i++) {
      var cell = getCellContainer(trackingEls[i]);
      if (cell && !processedCells.has(cell)) {
        var article = cell.querySelector(TWEET_SEL);
        hideCell(cell, article, 'placementTracking');
      }
    }

    // Strategy 2: Scan tweet articles for "Ad" badge text
    // The ad badge is a small span NOT inside the tweet text body,
    // typically in the social context / metadata area below the author line
    var articles = document.querySelectorAll(TWEET_SEL);
    for (var j = 0; j < articles.length; j++) {
      var article = articles[j];
      var cell = getCellContainer(article);
      if (!cell || processedCells.has(cell)) continue;

      // Get the tweet text container to exclude it from badge search
      var tweetText = article.querySelector(TWEET_TEXT_SEL);

      // Scan all leaf-level spans for ad badge text
      var spans = article.querySelectorAll('span');
      for (var k = 0; k < spans.length; k++) {
        var span = spans[k];

        // Ad badge spans are leaf nodes with very short text
        if (span.children.length > 0) continue;
        var text = span.textContent;
        if (!text || text.length > 20) continue;

        // Skip spans inside the actual tweet text
        if (tweetText && tweetText.contains(span)) continue;

        if (isAdLabel(text)) {
          // Additional validation: the ad badge is usually NOT inside
          // a link to a user profile (which contains display names)
          var parentLink = span.closest('a[role="link"]');
          if (parentLink) {
            var href = parentLink.getAttribute('href') || '';
            // User profile links start with / followed by username
            // Skip if this looks like a user profile link
            if (/^\/[A-Za-z0-9_]+$/.test(href)) continue;
          }

          hideCell(cell, article, 'ad-label("' + text.trim() + '")');
          break;
        }
      }
    }

    // Strategy 3: Promoted trends in Explore/sidebar
    // Promoted trends have a "Promoted" label within trend items
    var trendItems = document.querySelectorAll('[data-testid="trend"]');
    for (var m = 0; m < trendItems.length; m++) {
      var trend = trendItems[m];
      var trendCell = getCellContainer(trend);
      if (!trendCell || processedCells.has(trendCell)) continue;

      var trendSpans = trend.querySelectorAll('span');
      for (var n = 0; n < trendSpans.length; n++) {
        var ts = trendSpans[n];
        if (ts.children.length > 0) continue;
        if (isAdLabel(ts.textContent)) {
          hideCell(trendCell, null, 'promoted-trend("' + ts.textContent.trim() + '")');
          break;
        }
      }
    }

    var newHides = hiddenCount - hidesBefore;
    if (newHides > 0) {
      console.log(TAG, 'scan #' + scanCount, '|', newHides, 'new hides |', hiddenCount, 'total blocked');
    }
  }

  // --- Observer (scan on DOM changes only, childList only) ---
  var pending = false;
  function schedScan() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function() {
      pending = false;
      scan();
    });
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
    // childList only — NOT attributes. Watching attributes causes infinite loops:
    // hideCell() sets style/data-nook-* → observer fires → scan() → repeat.
    observer.observe(document.body, {
      subtree: true,
      childList: true
    });
    scan();
  }

  start();
})();
