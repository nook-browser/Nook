// Nook Content Blocker — YouTube Ad Blocker
// Uses native WKScriptMessageHandler for ad skipping (invisible to YouTube detection)
(function() {
  'use strict';

  // Prevent double execution (WKUserScript + fallback injection)
  if (window.__nookYTAdLoaded) return;
  window.__nookYTAdLoaded = true;

  var TAG = '[NookYTAd]';

  // Ad property keys to strip from YouTube data objects
  var AD_KEYS = [
    'playerAds', 'adPlacements', 'adSlots', 'adBreakParams',
    'adBreakHeartbeatParams', 'adBreakServiceRenderer',
    'instreamAdBreak', 'linearAdSequenceRenderer',
    'instreamVideoAdRenderer', 'adPlacementRenderer',
    'adSlotRenderer', 'adPlacementConfig',
    'bannerPromoRenderer', 'enforcementOverlayRendererModel',
    'adPodMetadata', 'adSlots', 'fullyAdFreeUpsell',
    'vpaidAdDisplayContainer', 'surveysEnabled'
    // NOTE: playbackTracking is NOT stripped — needed for video playback
    // NOTE: promotedVideoRenderer stripped only inside stripRendererAds (context-aware)
  ];

  // Additional nested paths to clean
  var NESTED_AD_PATHS = {
    'playerConfig': ['adRequestConfig'],
    'auxiliaryUi': null // strip messageRenderers.enforcementMessageViewModel
  };

  var strippedCount = 0;

  // === LAYER 1: Object Traps ===
  // Intercept ytInitialPlayerResponse / ytInitialData assignment on window

  function stripAds(obj, label) {
    if (!obj || typeof obj !== 'object') return obj;
    var removed = 0;

    // Neutralize ad keys — set to empty values instead of deleting.
    // YouTube checks if these properties EXIST; deleting them triggers
    // the "experiencing interruptions" enforcement dialog. Empty arrays
    // look like "no ads available for this video" — a normal state.
    for (var i = 0; i < AD_KEYS.length; i++) {
      if (obj[AD_KEYS[i]] !== undefined) {
        obj[AD_KEYS[i]] = Array.isArray(obj[AD_KEYS[i]]) ? [] :
                           (typeof obj[AD_KEYS[i]] === 'object' ? {} : undefined);
        removed++;
      }
    }

    // Clean nested paths
    if (obj.playerConfig && obj.playerConfig.adRequestConfig) {
      obj.playerConfig.adRequestConfig = {};
      removed++;
    }

    // Neutralize enforcement dialog
    if (obj.auxiliaryUi &&
        obj.auxiliaryUi.messageRenderers &&
        obj.auxiliaryUi.messageRenderers.enforcementMessageViewModel) {
      obj.auxiliaryUi.messageRenderers.enforcementMessageViewModel = undefined;
      removed++;
    }

    // Clean ad renderers from contents (search/browse results)
    if (obj.contents) {
      stripRendererAds(obj.contents);
    }
    if (obj.onResponseReceivedActions) {
      stripRendererAds(obj.onResponseReceivedActions);
    }

    if (removed > 0) {
      strippedCount += removed;
      console.log(TAG, 'stripAds:', label, '| removed', removed, 'keys | total:', strippedCount);
    }

    return obj;
  }

  function stripRendererAds(node, depth) {
    if (!node || typeof node !== 'object') return;
    if ((depth || 0) > 20) return; // guard against pathological nesting
    var d = (depth || 0) + 1;
    if (Array.isArray(node)) {
      for (var i = node.length - 1; i >= 0; i--) {
        var item = node[i];
        if (item && (item.adSlotRenderer || item.promotedVideoRenderer ||
                     item.promotedSparklesWebRenderer || item.searchPyvRenderer ||
                     item.adSlotAndLayoutRenderer)) {
          node.splice(i, 1);
        } else {
          stripRendererAds(item, d);
        }
      }
      return;
    }
    var keys = Object.keys(node);
    for (var j = 0; j < keys.length; j++) {
      var k = keys[j];
      if (k === 'adSlotRenderer' || k === 'promotedVideoRenderer' ||
          k === 'promotedSparklesWebRenderer' || k === 'searchPyvRenderer' ||
          k === 'adSlotAndLayoutRenderer') {
        delete node[k];
      } else if (typeof node[k] === 'object') {
        stripRendererAds(node[k], d);
      }
    }
  }

  function installObjectTrap(propName) {
    var storedValue = window[propName];

    try {
      Object.defineProperty(window, propName, {
        configurable: true,
        enumerable: true,
        get: function() { return storedValue; },
        set: function(val) {
          storedValue = stripAds(val, propName);
        }
      });

      // If property was already set before our trap, clean it
      if (storedValue && typeof storedValue === 'object') {
        storedValue = stripAds(storedValue, propName + '(existing)');
      }
    } catch (e) {
      console.log(TAG, 'trap failed for', propName, e.message);
    }
  }

  installObjectTrap('ytInitialPlayerResponse');
  installObjectTrap('ytInitialData');

  console.log(TAG, 'Layer 1: object traps installed');


  // === LAYER 2: Fetch/XHR Response Interception ===
  // Persistent across SPA navigations since we patch global prototypes

  function isAdDataUrl(url) {
    if (!url) return false;
    var s = typeof url === 'string' ? url : url.toString();
    // Intercept endpoints that carry ad renderers/overlays and player ad data
    return s.indexOf('/youtubei/v1/next') !== -1 ||
           s.indexOf('/youtubei/v1/browse') !== -1 ||
           s.indexOf('/youtubei/v1/player') !== -1;
  }

  // Fast ad-only strip — neutralize top-level keys, skip deep recursion
  function stripAdsFast(obj) {
    if (!obj || typeof obj !== 'object') return obj;
    for (var i = 0; i < AD_KEYS.length; i++) {
      if (obj[AD_KEYS[i]] !== undefined) {
        obj[AD_KEYS[i]] = Array.isArray(obj[AD_KEYS[i]]) ? [] :
                           (typeof obj[AD_KEYS[i]] === 'object' ? {} : undefined);
      }
    }
    if (obj.playerConfig && obj.playerConfig.adRequestConfig) {
      obj.playerConfig.adRequestConfig = {};
    }
    if (obj.auxiliaryUi && obj.auxiliaryUi.messageRenderers) {
      obj.auxiliaryUi.messageRenderers.enforcementMessageViewModel = undefined;
    }
    return obj;
  }

  // Hook fetch() — intercept ad-data and player endpoints
  var origFetch = window.fetch;
  window.fetch = function() {
    var url = arguments[0];
    var urlStr = typeof url === 'string' ? url : (url && url.url ? url.url : '');

    if (!isAdDataUrl(urlStr)) {
      return origFetch.apply(this, arguments);
    }

    return origFetch.apply(this, arguments).then(function(response) {
      var clone = response.clone();
      return clone.json().then(function(json) {
        var cleaned = stripAdsFast(json);
        console.log(TAG, 'Layer 2: stripped fetch', urlStr.split('?')[0]);
        return new Response(JSON.stringify(cleaned), {
          status: response.status,
          statusText: response.statusText,
          headers: response.headers
        });
      }).catch(function() {
        return response; // not JSON — pass through
      });
    });
  };

  // Hook XMLHttpRequest — same matching
  var origXhrOpen = XMLHttpRequest.prototype.open;
  XMLHttpRequest.prototype.open = function(method, url) {
    this.__nookUrl = url;
    return origXhrOpen.apply(this, arguments);
  };

  var origXhrSend = XMLHttpRequest.prototype.send;
  XMLHttpRequest.prototype.send = function() {
    if (isAdDataUrl(this.__nookUrl)) {
      var xhr = this;

      xhr.addEventListener('readystatechange', function() {
        if (xhr.readyState === 4 && xhr.status === 200) {
          try {
            var json = JSON.parse(xhr.responseText);
            var cleaned = stripAdsFast(json);
            var str = JSON.stringify(cleaned);
            Object.defineProperty(xhr, 'responseText', {
              configurable: true,
              get: function() { return str; }
            });
            Object.defineProperty(xhr, 'response', {
              configurable: true,
              get: function() { return str; }
            });
          } catch (e) {}
        }
      });
    }
    return origXhrSend.apply(this, arguments);
  };

  console.log(TAG, 'Layer 2: fetch/XHR hooks installed (next/browse/player)');


  // === LAYER 3: Player State Monitor → Native Skip ===
  // Posts to WKScriptMessageHandler — native Swift side skips the ad
  // via evaluateJavaScript, which is invisible to YouTube's anti-adblock

  var adSkipInProgress = false;

  function notifyNativeAdPlaying() {
    if (adSkipInProgress) return;
    adSkipInProgress = true;

    var video = document.querySelector('#movie_player video');
    var info = {
      type: 'ad-playing',
      videoTime: video ? video.currentTime : 0,
      videoDuration: video ? video.duration : 0
    };

    // Post to native handler (WKScriptMessageHandler)
    if (window.webkit && window.webkit.messageHandlers &&
        window.webkit.messageHandlers.nookAdBlocker) {
      window.webkit.messageHandlers.nookAdBlocker.postMessage(info);
      console.log(TAG, 'Layer 3: ad-playing → native skip requested');
    } else {
      // Fallback: skip directly from JS if native handler unavailable
      skipAdDirect();
    }

    // Reset flag after a short delay to allow re-detection
    setTimeout(function() { adSkipInProgress = false; }, 500);
  }

  function skipAdDirect() {
    // Seek to end of ad video
    var video = document.querySelector('#movie_player video');
    if (video && isFinite(video.duration) && video.duration > 0) {
      video.currentTime = video.duration;
    }
    // Click skip button (multiple selectors for different YouTube UI variants)
    var skipBtn = document.querySelector(
      '.ytp-skip-ad-button, ' +
      '.ytp-ad-skip-button, ' +
      '.ytp-ad-skip-button-modern, ' +
      '.ytp-ad-skip-button-container button, ' +
      'button[id^="skip-button"], ' +
      '.ytp-ad-overlay-close-button'
    );
    if (skipBtn) {
      skipBtn.click();
      console.log(TAG, 'Layer 3: skip button clicked');
    }
  }

  function isAdPlaying() {
    var player = document.querySelector('#movie_player, .html5-video-player');
    if (!player) return false;
    return player.classList.contains('ad-showing') || player.classList.contains('ad-interrupting');
  }

  function setupPlayerObserver() {
    var player = document.querySelector('#movie_player, .html5-video-player');
    if (!player) return false;

    // Already observing
    if (player.__nookObserving) return true;
    player.__nookObserving = true;

    // NOTE: attributes: true with attributeFilter is safe here despite CLAUDE.md guidance.
    // The body-level observer uses childList-only (per CLAUDE.md). This narrow observer
    // only watches the player's class attribute and never modifies it, so no infinite loop.
    var observing = false; // re-entry guard
    var observer = new MutationObserver(function(mutations) {
      if (observing) return;
      observing = true;
      try {
        for (var i = 0; i < mutations.length; i++) {
          var m = mutations[i];
          if (m.type === 'attributes' && m.attributeName === 'class') {
            var cl = player.classList;
            if (cl.contains('ad-showing') || cl.contains('ad-interrupting')) {
              notifyNativeAdPlaying();
            }
          }
        }
      } finally {
        observing = false;
      }
    });

    observer.observe(player, {
      attributes: true,
      attributeFilter: ['class']
    });

    // Check immediately in case ad is already showing
    if (isAdPlaying()) {
      notifyNativeAdPlaying();
    }

    console.log(TAG, 'Layer 3: player observer installed');
    return true;
  }


  // === LAYER 4: DOM Cleanup ===
  // childList-only MutationObserver on document.body

  // Inner ad elements to detect
  var AD_INNER_SELS = [
    'ytd-ad-slot-renderer',
    'ytd-in-feed-ad-layout-renderer',
    'ytd-banner-promo-renderer',
    'ytd-promoted-sparkles-web-renderer',
    'ytd-promoted-video-renderer',
    'ytd-display-ad-renderer',
    'ytd-statement-banner-renderer',
    'ytd-compact-promoted-item-renderer',
    'ytd-action-companion-ad-renderer',
    'ytd-player-legacy-desktop-watch-ads-renderer',
    'ytd-ad-slot-and-layout-renderer'
  ];
  var AD_INNER_SEL_STR = AD_INNER_SELS.join(',');

  // Grid-level parents to collapse (removes gap from layout)
  var GRID_PARENTS = 'ytd-rich-item-renderer, ytd-rich-section-renderer, ytd-shelf-renderer, ytd-reel-shelf-renderer';

  var adContainersRemoved = 0;
  var processedAdContainers = new WeakSet();

  function collapseElement(el) {
    if (processedAdContainers.has(el)) return;
    processedAdContainers.add(el);
    // Remove entirely from DOM to guarantee no gap in grid layout
    el.remove();
    adContainersRemoved++;
  }

  function hideElement(el) {
    if (processedAdContainers.has(el)) return;
    processedAdContainers.add(el);
    el.style.setProperty('display', 'none', 'important');
  }

  function cleanupAdContainers() {
    // Find ad elements and remove their grid-level parent to close gaps
    var ads = document.querySelectorAll(AD_INNER_SEL_STR);
    for (var i = 0; i < ads.length; i++) {
      if (processedAdContainers.has(ads[i])) continue;
      processedAdContainers.add(ads[i]);
      // Walk up to grid parent and remove it entirely
      var parent = ads[i].closest(GRID_PARENTS);
      if (parent) {
        collapseElement(parent);
      } else {
        // No grid parent — remove the ad element itself
        collapseElement(ads[i]);
      }
    }

    // Catch section-level ad containers
    var sections = document.querySelectorAll(
      'ytd-rich-section-renderer:has(ytd-ad-slot-renderer), ytd-rich-section-renderer:has(ytd-statement-banner-renderer)'
    );
    for (var s = 0; s < sections.length; s++) {
      collapseElement(sections[s]);
    }

    // Hide overlay ads (don't remove — they're inside the player)
    var overlays = document.querySelectorAll(
      '.ytp-ad-overlay-container, .ytp-ad-text-overlay, .video-ads, ' +
      '.ytp-ad-image-overlay, .ytp-ad-skip-ad-slot, ' +
      '.ad-container:not(#movie_player)'
    );
    for (var j = 0; j < overlays.length; j++) {
      hideElement(overlays[j]);
    }

    // Remove enforcement / interruption dialogs
    var dialogs = document.querySelectorAll(
      'tp-yt-paper-dialog:has(ytd-enforcement-dialog-view-model), ' +
      'ytd-enforcement-message-view-model, ' +
      'tp-yt-paper-dialog:has([target-id="enforcement"]), ' +
      'ytd-popup-container tp-yt-paper-dialog'
    );
    for (var k = 0; k < dialogs.length; k++) {
      // Only remove dialogs that look like enforcement (not all popups)
      var el = dialogs[k];
      var text = (el.textContent || '').toLowerCase();
      if (text.indexOf('interruption') !== -1 || text.indexOf('ad blocker') !== -1 ||
          text.indexOf('allow ads') !== -1 || el.querySelector('ytd-enforcement-dialog-view-model')) {
        collapseElement(el);
        console.log(TAG, 'Layer 4: removed enforcement dialog');
      }
    }

    // Remove masthead/banner ads
    var masthead = document.querySelector('#masthead-ad, #masthead-container .ytd-masthead-ad-v3-renderer');
    if (masthead) collapseElement(masthead);
    var playerAds = document.querySelector('#player-ads');
    if (playerAds) collapseElement(playerAds);

    if (adContainersRemoved > 0) {
      console.log(TAG, 'Layer 4:', adContainersRemoved, 'ad containers removed');
    }

    // Try to set up player observer if not yet done
    setupPlayerObserver();
  }


  // === LAYER 5: SPA Navigation Handler ===

  function onSPANavigateStart() {
    // Reset skip state early so the new page starts fresh
    adSkipInProgress = false;
  }

  function onSPANavigateFinish() {
    console.log(TAG, 'Layer 5: SPA navigation detected');
    // Reset observer state on player so it gets re-attached
    var player = document.querySelector('#movie_player, .html5-video-player');
    if (player) player.__nookObserving = false;
    cleanupAdContainers();
    setupPlayerObserver();
  }


  // === Start ===

  var pending = false;
  function schedCleanup() {
    if (pending) return;
    pending = true;
    requestAnimationFrame(function() {
      pending = false;
      cleanupAdContainers();
    });
  }

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

    // DOM cleanup observer (childList only — NOT attributes)
    var bodyObserver = new MutationObserver(function(mutations) {
      for (var i = 0; i < mutations.length; i++) {
        if (mutations[i].type === 'childList' && mutations[i].addedNodes.length) {
          schedCleanup();
          return;
        }
      }
    });
    bodyObserver.observe(document.body, { subtree: true, childList: true });

    // SPA navigation listeners
    document.addEventListener('yt-navigate-start', onSPANavigateStart);
    document.addEventListener('yt-navigate-finish', onSPANavigateFinish);

    // Initial cleanup
    cleanupAdContainers();
  }

  start();
})();
