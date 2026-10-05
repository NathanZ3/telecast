// TéléCast video detector.
// Injected at document start in every frame (page content world) of the in-app browser.
// Reports media URLs to the app through window.webkit.messageHandlers.castDetector:
//   { kind: "hello", frameURL, userAgent }
//   { kind: "candidate", url, via, frameURL, mime?, duration?, width?, height?, playing? }
//   { kind: "playing", frameURL, duration, playing: true }   (a media element plays a blob:/MediaSource)
// "via" is one of: video-src, source, media-event, fetch, xhr, perf.
(function () {
  'use strict';

  if (window.__teleCastDetector) return;
  try {
    Object.defineProperty(window, '__teleCastDetector', { value: true, enumerable: false });
  } catch (e) {
    window.__teleCastDetector = true;
  }

  var IGNORED_SCHEME = /^(blob:|data:|mediastream:|about:|javascript:)/i;
  var MEDIA_URL = /\.(m3u8|mpd|mp4|m4v|mov|webm|mkv)(\?|#|$)|\.m3u8/i;
  var MANIFEST_URL = /\.(m3u8|mpd)(\?|#|$)|\.m3u8/i;
  var MEDIA_MIME = /mpegurl|dash\+xml|^\s*video\//i;
  var MEDIA_EVENTS = ['loadstart', 'loadedmetadata', 'durationchange', 'play', 'playing'];

  var sent = new Map();
  var xhrURLs = new WeakMap();
  var playingSent = new WeakMap();

  function frameURL() {
    try {
      return String(location.href);
    } catch (e) {
      return '';
    }
  }

  function post(message) {
    try {
      var handlers = window.webkit && window.webkit.messageHandlers;
      var handler = handlers && handlers.castDetector;
      if (handler) handler.postMessage(message);
    } catch (e) {
      // never break the page
    }
  }

  function absolute(raw) {
    try {
      return new URL(String(raw), document.baseURI).href;
    } catch (e) {
      return null;
    }
  }

  function finite(value) {
    return typeof value === 'number' && isFinite(value) && value > 0 ? value : null;
  }

  function report(raw, via, extra) {
    if (!raw || IGNORED_SCHEME.test(String(raw))) return;
    var url = absolute(raw);
    if (!url || !/^https?:/i.test(url)) return;
    var info = extra || {};
    var signature = [
      info.duration ? Math.round(info.duration) : 0,
      info.playing ? 1 : 0,
      info.mime || '',
      info.width || 0,
    ].join('|');
    var key = url + '|' + via;
    if (sent.get(key) === signature) return;
    if (sent.size > 500) sent.clear();
    sent.set(key, signature);
    var message = { kind: 'candidate', url: url, via: via, frameURL: frameURL() };
    if (info.mime) message.mime = String(info.mime);
    if (info.duration) message.duration = info.duration;
    if (info.width) message.width = info.width;
    if (info.height) message.height = info.height;
    if (info.playing) message.playing = true;
    post(message);
  }

  function mediaInfo(element) {
    var info = {};
    try {
      var duration = finite(element.duration);
      if (duration) info.duration = duration;
      if (element.videoWidth) info.width = element.videoWidth;
      if (element.videoHeight) info.height = element.videoHeight;
      info.playing = !element.paused && !element.ended;
    } catch (e) {
      // ignore
    }
    return info;
  }

  function reportPlayingBlob(element) {
    try {
      if (element.paused || element.ended) return;
      var duration = finite(element.duration);
      var signature = duration ? Math.round(duration) : 0;
      if (playingSent.get(element) === signature) return;
      playingSent.set(element, signature);
      post({ kind: 'playing', frameURL: frameURL(), duration: duration, playing: true });
    } catch (e) {
      // ignore
    }
  }

  function inspectMedia(element, via) {
    try {
      var src = element.currentSrc || element.src || element.getAttribute('src');
      if (src && /^blob:/i.test(src)) {
        reportPlayingBlob(element);
      } else if (src) {
        report(src, via, mediaInfo(element));
      }
      if (element.querySelectorAll) {
        var sources = element.querySelectorAll('source[src]');
        for (var i = 0; i < sources.length; i++) {
          report(sources[i].getAttribute('src'), 'source', { mime: sources[i].getAttribute('type') || '' });
        }
      }
    } catch (e) {
      // ignore
    }
  }

  function scanNode(node) {
    if (!node || node.nodeType !== 1) return;
    var tag = node.tagName;
    if (tag === 'VIDEO' || tag === 'AUDIO') {
      inspectMedia(node, 'video-src');
    } else if (tag === 'SOURCE') {
      report(node.getAttribute('src'), 'source', { mime: node.getAttribute('type') || '' });
    } else if (node.querySelectorAll) {
      var found = node.querySelectorAll('video, audio');
      for (var i = 0; i < found.length; i++) inspectMedia(found[i], 'video-src');
    }
  }

  function scanDocument() {
    try {
      var found = document.querySelectorAll('video, audio');
      for (var i = 0; i < found.length; i++) inspectMedia(found[i], 'video-src');
    } catch (e) {
      // ignore
    }
  }

  // 1. `src` property assignments on media elements.
  try {
    var descriptor = Object.getOwnPropertyDescriptor(HTMLMediaElement.prototype, 'src');
    if (descriptor && descriptor.set && descriptor.configurable) {
      Object.defineProperty(HTMLMediaElement.prototype, 'src', {
        configurable: true,
        enumerable: descriptor.enumerable,
        get: descriptor.get,
        set: function (value) {
          try {
            report(String(value), 'video-src');
          } catch (e) {
            // ignore
          }
          return descriptor.set.call(this, value);
        },
      });
    }
  } catch (e) {
    // ignore
  }

  // 2. Elements and `src` attributes added to the DOM (parser, innerHTML, setAttribute).
  try {
    var observer = new MutationObserver(function (mutations) {
      for (var i = 0; i < mutations.length; i++) {
        var mutation = mutations[i];
        if (mutation.type === 'childList') {
          for (var j = 0; j < mutation.addedNodes.length; j++) scanNode(mutation.addedNodes[j]);
        } else if (mutation.type === 'attributes') {
          scanNode(mutation.target);
        }
      }
    });
    observer.observe(document, { childList: true, subtree: true, attributes: true, attributeFilter: ['src'] });
  } catch (e) {
    // ignore
  }

  // 3. Media events (they do not bubble, but capture listeners on the document see them).
  try {
    MEDIA_EVENTS.forEach(function (type) {
      document.addEventListener(
        type,
        function (event) {
          var target = event.target;
          if (target && (target.tagName === 'VIDEO' || target.tagName === 'AUDIO')) inspectMedia(target, 'media-event');
        },
        true
      );
    });
  } catch (e) {
    // ignore
  }

  // 4. fetch(): URL hint before the request, Content-Type after the response.
  try {
    var originalFetch = window.fetch;
    if (typeof originalFetch === 'function') {
      var wrappedFetch = function (input, init) {
        var requested = null;
        try {
          requested = typeof input === 'string' ? input : (input && input.url) || String(input);
          if (requested && MEDIA_URL.test(requested)) report(requested, 'fetch');
        } catch (e) {
          // ignore
        }
        var promise = originalFetch.apply(this === undefined || this === null ? window : this, arguments);
        try {
          promise.then(
            function (response) {
              try {
                var type = (response && response.headers && response.headers.get('content-type')) || '';
                if (MEDIA_MIME.test(type)) report(response.url || requested, 'fetch', { mime: type });
              } catch (e) {
                // ignore
              }
            },
            function () {}
          );
        } catch (e) {
          // ignore
        }
        return promise;
      };
      try {
        Object.defineProperty(wrappedFetch, 'toString', {
          value: function () {
            return originalFetch.toString();
          },
        });
      } catch (e) {
        // ignore
      }
      window.fetch = wrappedFetch;
    }
  } catch (e) {
    // ignore
  }

  // 5. XMLHttpRequest: URL hint on open(), Content-Type once headers are received.
  try {
    var XHR = window.XMLHttpRequest;
    if (XHR && XHR.prototype && typeof XHR.prototype.open === 'function') {
      var originalOpen = XHR.prototype.open;
      XHR.prototype.open = function (method, url) {
        try {
          var requested = String(url);
          if (!xhrURLs.has(this)) {
            this.addEventListener('readystatechange', function () {
              try {
                if (this.readyState === 2 || this.readyState === 4) {
                  var type = this.getResponseHeader('content-type') || '';
                  if (MEDIA_MIME.test(type)) report(this.responseURL || xhrURLs.get(this), 'xhr', { mime: type });
                }
              } catch (e) {
                // ignore
              }
            });
          }
          xhrURLs.set(this, requested);
          if (MEDIA_URL.test(requested)) report(requested, 'xhr');
        } catch (e) {
          // ignore
        }
        return originalOpen.apply(this, arguments);
      };
    }
  } catch (e) {
    // ignore
  }

  // 6. Safety net: manifests seen in the resource timeline (requests made before our hooks, workers…).
  try {
    if (window.PerformanceObserver) {
      var performanceObserver = new PerformanceObserver(function (list) {
        var entries = list.getEntries();
        for (var i = 0; i < entries.length; i++) {
          if (entries[i].name && MANIFEST_URL.test(entries[i].name)) report(entries[i].name, 'perf');
        }
      });
      performanceObserver.observe({ type: 'resource', buffered: true });
    }
  } catch (e) {
    // ignore
  }

  document.addEventListener('DOMContentLoaded', scanDocument, true);
  window.addEventListener('load', scanDocument, true);

  post({ kind: 'hello', frameURL: frameURL(), userAgent: navigator.userAgent });
})();
