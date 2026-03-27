// Nook SponsorBlock — YouTube segment skipper
// Uses community-submitted data from SponsorBlock (sponsor.ajay.app)
// Mirrors the official SponsorBlock extension behavior.
(function() {
  'use strict';

  if (window.__nookSponsorBlockLoaded) return;
  window.__nookSponsorBlockLoaded = true;

  var TAG = '[NookSB]';

  // === Category colors — exact match to SponsorBlock's official palette ===
  var CATEGORY_COLORS = {
    sponsor: '#00d400',
    selfpromo: '#ffff00',
    exclusive_access: '#008a5c',
    interaction: '#cc00ff',
    intro: '#00ffff',
    outro: '#0202ed',
    preview: '#008fd6',
    filler: '#7300ff',
    music_offtopic: '#ff9900',
    poi_highlight: '#ff1684'
  };

  var CATEGORY_OPACITY = { filler: '0.9' };
  var DEFAULT_OPACITY = '0.7';

  var CATEGORY_NAMES = {
    sponsor: 'sponsor',
    selfpromo: 'self-promotion',
    exclusive_access: 'exclusive access',
    interaction: 'interaction reminder',
    intro: 'intro',
    outro: 'outro',
    preview: 'preview',
    filler: 'filler',
    music_offtopic: 'non-music',
    poi_highlight: 'highlight'
  };

  // === State ===
  var currentVideoID = null;
  var segments = [];
  var categoryOptions = {};           // category → "auto" | "manual" | "disabled"
  var currentSkipSchedule = null;
  var currentSkipInterval = null;
  var videoElement = null;
  var videoListenersAttached = false;
  var toastTimeout = null;
  var markerContainer = null;
  var manualSkipContainer = null;

  // Virtual time state (performance.now() precision)
  var lastVideoTime = 0;
  var lastPerformanceTime = 0;
  var lastPlaybackRate = 1;

  var SKIP_NOTICE_DURATION = 4000;

  // === Public API for Swift ===
  window.__nookSponsorBlock = {
    receiveSegments: function(segs, options) {
      segments = segs || [];
      categoryOptions = options || {};
      console.log(TAG, 'Received', segments.length, 'segments for', currentVideoID);
      renderProgressBarMarkers();
      if (segments.length > 0) {
        setupVideoListeners();
        startSponsorSchedule();
      } else {
        cancelSponsorSchedule();
      }
    },
    updateSettings: function() {}
  };

  // === Video ID Extraction ===
  function extractVideoID(href) {
    if (!href) return null;
    var m = href.match(/[?&]v=([a-zA-Z0-9_-]{11})/);
    if (m) return m[1];
    m = href.match(/\/(?:embed|v|shorts)\/([a-zA-Z0-9_-]{11})/);
    if (m) return m[1];
    m = href.match(/youtu\.be\/([a-zA-Z0-9_-]{11})/);
    if (m) return m[1];
    return null;
  }

  // === Virtual Time ===
  // SponsorBlock uses performance.now() deltas for sub-frame precision.
  function getVirtualTime() {
    var video = getVideoElement();
    if (!video) return 0;
    if (video.paused || video.ended) return video.currentTime;
    var elapsed = (performance.now() - lastPerformanceTime) / 1000;
    return lastVideoTime + (elapsed * lastPlaybackRate);
  }

  function updateTimeReference() {
    var video = getVideoElement();
    if (!video) return;
    lastVideoTime = video.currentTime;
    lastPerformanceTime = performance.now();
    lastPlaybackRate = video.playbackRate || 1;
  }

  // === Video Element & Event Listeners ===
  function getVideoElement() {
    if (videoElement && videoElement.isConnected) return videoElement;
    videoElement = document.querySelector('#movie_player video');
    return videoElement;
  }

  function setupVideoListeners() {
    var video = getVideoElement();
    if (!video || videoListenersAttached) return;
    videoListenersAttached = true;

    video.addEventListener('play', onVideoPlay);
    video.addEventListener('playing', onVideoPlay);
    video.addEventListener('seeking', onVideoSeeking);
    video.addEventListener('ratechange', onVideoRateChange);
    video.addEventListener('pause', onVideoPause);
    video.addEventListener('waiting', onVideoPause);
    video.addEventListener('timeupdate', updateTimeReference);
  }

  function removeVideoListeners() {
    if (!videoElement) return;
    videoElement.removeEventListener('play', onVideoPlay);
    videoElement.removeEventListener('playing', onVideoPlay);
    videoElement.removeEventListener('seeking', onVideoSeeking);
    videoElement.removeEventListener('ratechange', onVideoRateChange);
    videoElement.removeEventListener('pause', onVideoPause);
    videoElement.removeEventListener('waiting', onVideoPause);
    videoElement.removeEventListener('timeupdate', updateTimeReference);
    videoListenersAttached = false;
    videoElement = null;
  }

  function onVideoPlay() {
    updateTimeReference();
    startSponsorSchedule();
  }

  function onVideoPause() {
    cancelSponsorSchedule();
    removeManualSkipButton();
  }

  function onVideoSeeking() {
    updateTimeReference();
    removeManualSkipButton();
    startSponsorSchedule();
  }

  function onVideoRateChange() {
    updateTimeReference();
    startSponsorSchedule();
  }

  // === Skip Scheduling ===
  function startSponsorSchedule() {
    cancelSponsorSchedule();

    var video = getVideoElement();
    if (!video || video.paused || video.ended || segments.length === 0) return;

    var currentTime = getVirtualTime();
    var playbackRate = video.playbackRate || 1;
    var nextSeg = getNextSkipSegment(currentTime);

    if (!nextSeg) return;

    var skipOption = categoryOptions[nextSeg.category] || 'disabled';

    // Already inside a segment
    if (currentTime >= nextSeg.segment[0] && currentTime < nextSeg.segment[1] - 0.1) {
      if (skipOption === 'auto') {
        performSkip(nextSeg, currentTime);
      } else if (skipOption === 'manual') {
        showManualSkipButton(nextSeg);
      }
      return;
    }

    var timeUntilSkip = ((nextSeg.segment[0] - currentTime) / playbackRate) * 1000;

    if (timeUntilSkip > 750) {
      var delay = Math.max(0, timeUntilSkip - 150);
      currentSkipSchedule = setTimeout(function() {
        currentSkipSchedule = null;
        startSponsorSchedule();
      }, delay);
    } else {
      currentSkipInterval = setInterval(function() {
        var v = getVideoElement();
        if (!v || v.paused || v.ended) {
          cancelSponsorSchedule();
          return;
        }
        var t = getVirtualTime();
        if (t >= nextSeg.segment[0] && t < nextSeg.segment[1] - 0.1) {
          cancelSponsorSchedule();
          var opt = categoryOptions[nextSeg.category] || 'disabled';
          if (opt === 'auto') {
            performSkip(nextSeg, t);
          } else if (opt === 'manual') {
            showManualSkipButton(nextSeg);
            // Keep checking in case segment ends without user action
            scheduleManualSegmentEnd(nextSeg);
          }
        }
      }, 50);
    }
  }

  function cancelSponsorSchedule() {
    if (currentSkipSchedule) {
      clearTimeout(currentSkipSchedule);
      currentSkipSchedule = null;
    }
    if (currentSkipInterval) {
      clearInterval(currentSkipInterval);
      currentSkipInterval = null;
    }
  }

  function getNextSkipSegment(currentTime) {
    var best = null;
    for (var i = 0; i < segments.length; i++) {
      var seg = segments[i];
      var opt = categoryOptions[seg.category] || 'disabled';
      if (opt === 'disabled') continue;
      if (currentTime < seg.segment[1] - 0.1) {
        if (!best || seg.segment[0] < best.segment[0]) {
          best = seg;
        }
      }
    }
    return best;
  }

  function performSkip(seg, currentTime) {
    var video = getVideoElement();
    if (!video) return;

    removeManualSkipButton();

    if (seg.actionType === 'mute') {
      video.muted = true;
      scheduleUnmute(video, seg.segment[1]);
    } else {
      video.currentTime = seg.segment[1];
      console.log(TAG, 'Skipped', seg.category, seg.segment[0].toFixed(1), '->', seg.segment[1].toFixed(1));
    }

    showSkipToast(seg, currentTime);
    reportSegmentSkipped(seg.UUID);
    setTimeout(startSponsorSchedule, 100);
  }

  function scheduleUnmute(video, endTime) {
    var check = setInterval(function() {
      if (!video || video.currentTime >= endTime || video.ended) {
        video.muted = false;
        clearInterval(check);
      }
    }, 200);
    setTimeout(function() { clearInterval(check); }, 300000);
  }

  // When in a manual-skip segment, schedule removal of the button when segment ends
  function scheduleManualSegmentEnd(seg) {
    var check = setInterval(function() {
      var v = getVideoElement();
      if (!v || v.currentTime >= seg.segment[1] || v.currentTime < seg.segment[0] - 0.5) {
        clearInterval(check);
        removeManualSkipButton();
        startSponsorSchedule();
      }
    }, 200);
    // Safety cleanup
    setTimeout(function() { clearInterval(check); }, 600000);
  }

  // === Manual Skip Button ===
  // SponsorBlock shows a "Skip" button when entering a manual-skip segment.
  function showManualSkipButton(seg) {
    removeManualSkipButton();

    var player = document.querySelector('#movie_player');
    if (!player) return;

    var color = CATEGORY_COLORS[seg.category] || '#888';
    var categoryName = CATEGORY_NAMES[seg.category] || seg.category;

    manualSkipContainer = document.createElement('div');
    manualSkipContainer.id = 'nook-sb-skip-btn';
    manualSkipContainer.style.cssText = [
      'position: absolute',
      'bottom: 70px',
      'right: 10px',
      'z-index: 1000',
      'display: flex',
      'align-items: center',
      'gap: 8px',
      'padding: 8px 16px',
      'border-radius: 8px',
      'background: rgba(0, 0, 0, 0.8)',
      'backdrop-filter: blur(10px)',
      '-webkit-backdrop-filter: blur(10px)',
      'color: #fff',
      'font-family: -apple-system, BlinkMacSystemFont, sans-serif',
      'font-size: 14px',
      'cursor: pointer',
      'pointer-events: auto',
      'white-space: nowrap',
      'transition: opacity 0.2s ease',
      'border-left: 3px solid ' + color
    ].join('; ');

    var text = document.createElement('span');
    text.textContent = 'Skip ' + categoryName;

    manualSkipContainer.appendChild(text);

    manualSkipContainer.addEventListener('click', function(e) {
      e.stopPropagation();
      e.preventDefault();
      var t = getVideoElement() ? getVideoElement().currentTime : 0;
      performSkip(seg, t);
    });

    player.appendChild(manualSkipContainer);
  }

  function removeManualSkipButton() {
    if (manualSkipContainer) {
      manualSkipContainer.remove();
      manualSkipContainer = null;
    }
    var existing = document.querySelector('#nook-sb-skip-btn');
    if (existing) existing.remove();
  }

  // === Skip Notice Toast ===
  function showSkipToast(seg, originalTime) {
    removeToast();

    var player = document.querySelector('#movie_player');
    if (!player) return;

    var toast = document.createElement('div');
    toast.id = 'nook-sb-toast';
    toast.style.cssText = [
      'position: absolute',
      'bottom: 70px',
      'right: 10px',
      'z-index: 1000',
      'display: flex',
      'align-items: center',
      'gap: 10px',
      'padding: 8px 16px',
      'border-radius: 8px',
      'background: rgba(0, 0, 0, 0.8)',
      'backdrop-filter: blur(10px)',
      '-webkit-backdrop-filter: blur(10px)',
      'color: #fff',
      'font-family: -apple-system, BlinkMacSystemFont, sans-serif',
      'font-size: 13px',
      'pointer-events: auto',
      'white-space: nowrap',
      'transition: opacity 0.3s ease'
    ].join('; ');

    var categoryName = CATEGORY_NAMES[seg.category] || seg.category;
    var color = CATEGORY_COLORS[seg.category] || '#888';

    var dot = document.createElement('span');
    dot.style.cssText = 'width:8px;height:8px;border-radius:50%;flex-shrink:0;background:' + color;

    var text = document.createElement('span');
    text.textContent = 'Skipped ' + categoryName + ' (' + formatTime(seg.segment[0]) + ' \u2192 ' + formatTime(seg.segment[1]) + ')';

    var undoBtn = document.createElement('button');
    undoBtn.textContent = 'Undo';
    undoBtn.style.cssText = [
      'background: rgba(255,255,255,0.2)',
      'border: none',
      'color: #fff',
      'padding: 3px 10px',
      'border-radius: 4px',
      'cursor: pointer',
      'font-size: 12px',
      'font-family: inherit'
    ].join('; ');
    undoBtn.addEventListener('click', function(e) {
      e.stopPropagation();
      e.preventDefault();
      var video = getVideoElement();
      if (video) {
        video.currentTime = originalTime;
      }
      removeToast();
      setTimeout(startSponsorSchedule, 2000);
    });

    toast.appendChild(dot);
    toast.appendChild(text);
    toast.appendChild(undoBtn);
    player.appendChild(toast);

    toastTimeout = setTimeout(function() {
      if (toast.parentNode) {
        toast.style.opacity = '0';
        setTimeout(function() { removeToast(); }, 300);
      }
    }, SKIP_NOTICE_DURATION);
  }

  function removeToast() {
    if (toastTimeout) {
      clearTimeout(toastTimeout);
      toastTimeout = null;
    }
    var existing = document.querySelector('#nook-sb-toast');
    if (existing) existing.remove();
  }

  function formatTime(seconds) {
    var m = Math.floor(seconds / 60);
    var s = Math.floor(seconds % 60);
    return m + ':' + (s < 10 ? '0' : '') + s;
  }

  // === Telemetry ===
  // Report skipped segments to SponsorBlock (supports community data).
  function reportSegmentSkipped(uuid) {
    postToNative({ type: 'segment-skipped', uuid: uuid });
  }

  // === Progress Bar Markers ===
  function renderProgressBarMarkers() {
    removeProgressBarMarkers();

    if (segments.length === 0) return;

    var video = getVideoElement();
    if (!video || !isFinite(video.duration) || video.duration <= 0) {
      video && video.addEventListener('durationchange', onDurationReady, { once: true });
      return;
    }

    var parent = document.querySelector('.ytp-progress-bar');
    if (!parent) return;

    var duration = video.duration;

    markerContainer = document.createElement('ul');
    markerContainer.id = 'previewbar';
    markerContainer.style.cssText = [
      'position: absolute',
      'top: 0',
      'left: 0',
      'width: 100%',
      'height: 100%',
      'pointer-events: none',
      'z-index: 40',
      'list-style: none',
      'margin: 0',
      'padding: 0'
    ].join('; ');

    for (var i = 0; i < segments.length; i++) {
      var seg = segments[i];
      var startPct = Math.min(1, seg.segment[0] / duration) * 100;
      var endPct = Math.min(1, seg.segment[1] / duration) * 100;
      var color = CATEGORY_COLORS[seg.category] || '#888';
      var opacity = CATEGORY_OPACITY[seg.category] || DEFAULT_OPACITY;

      var bar = document.createElement('li');
      bar.className = 'previewbar';
      bar.style.cssText = [
        'position: absolute',
        'bottom: 0',
        'height: 100%',
        'border-radius: 1px',
        'left: ' + startPct + '%',
        'right: ' + (100 - endPct) + '%',
        'background: ' + color,
        'opacity: ' + opacity
      ].join('; ');

      markerContainer.appendChild(bar);
    }

    parent.prepend(markerContainer);
  }

  function onDurationReady() {
    renderProgressBarMarkers();
  }

  function removeProgressBarMarkers() {
    if (markerContainer) {
      markerContainer.remove();
      markerContainer = null;
    }
    var existing = document.querySelector('#previewbar');
    if (existing) existing.remove();
  }

  // === SPA Navigation ===
  function onVideoChange() {
    var newID = extractVideoID(location.href);
    if (!newID || newID === currentVideoID) return;

    currentVideoID = newID;
    segments = [];
    categoryOptions = {};
    cancelSponsorSchedule();
    removeVideoListeners();
    removeProgressBarMarkers();
    removeManualSkipButton();
    removeToast();

    postToNative({ type: 'video-changed', videoID: newID });
  }

  function postToNative(msg) {
    try {
      if (window.webkit && window.webkit.messageHandlers && window.webkit.messageHandlers.nookSponsorBlock) {
        window.webkit.messageHandlers.nookSponsorBlock.postMessage(msg);
      }
    } catch (e) {
      console.warn(TAG, 'Failed to post to native:', e);
    }
  }

  // === YouTube Shorts Loop Detection ===
  function setupLoopDetection() {
    var lastTime = 0;
    setInterval(function() {
      var video = getVideoElement();
      if (!video) return;
      if (video.currentTime < lastTime - 1 && lastTime > 2) {
        startSponsorSchedule();
      }
      lastTime = video.currentTime;
    }, 500);
  }

  // === Initialization ===
  function init() {
    document.addEventListener('yt-navigate-finish', onVideoChange);

    window.addEventListener('popstate', function() {
      setTimeout(onVideoChange, 100);
    });

    document.addEventListener('fullscreenchange', function() {
      if (segments.length > 0) {
        setTimeout(renderProgressBarMarkers, 300);
      }
    });

    setupLoopDetection();

    var id = extractVideoID(location.href);
    if (id) {
      currentVideoID = id;
      postToNative({ type: 'video-changed', videoID: id });
    }
  }

  if (document.readyState === 'loading') {
    document.addEventListener('DOMContentLoaded', init);
  } else {
    init();
  }
})();
