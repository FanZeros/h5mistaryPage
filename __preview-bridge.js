(function () {
  if (window.__taptapPreviewBridgeInstalled) return;
  window.__taptapPreviewBridgeInstalled = true;

  var MAX_LOGS = 2000;
  var TRUNC = 2000;
  var STACK_TRUNC = 4096;
  var buffer = [];
  var recording = false;
  var startedAt = 0;
  var bridge = document.currentScript;
  var buildId = (bridge && bridge.dataset && bridge.dataset.buildId) || "";
  var parentOrigin = getReferrerOrigin();

  function getReferrerOrigin() {
    try {
      return document.referrer ? new URL(document.referrer).origin : "";
    } catch (_) {
      return "";
    }
  }

  function isUsableOrigin(origin) {
    return typeof origin === "string" && origin !== "" && origin !== "null";
  }

  function isTrustedParentMessage(event) {
    if (event.source !== parent) return false;
    if (parentOrigin && event.origin !== parentOrigin) return false;
    if (!parentOrigin && isUsableOrigin(event.origin)) parentOrigin = event.origin;
    return true;
  }

  function formatValue(value) {
    if (typeof value === "string") return value;
    if (typeof value === "undefined") return "undefined";
    if (value === null) return "null";
    if (value instanceof Error) return value.stack || value.message;
    if (typeof value === "number" || typeof value === "boolean" || typeof value === "bigint") {
      return String(value);
    }
    try {
      return JSON.stringify(value);
    } catch (_) {
      return String(value);
    }
  }

  function inferSource(stack) {
    return /tapcode-sce\.spark\.xd\.com|spark\.xd\.com/.test(String(stack || "")) ? "sdk" : "game";
  }

  function emit(level, args, stack) {
    // Without a parent origin there is no consumer; skip buffering too.
    if (!recording || !parentOrigin) return;
    var text = Array.prototype.map.call(args, formatValue).join(" ").slice(0, TRUNC);
    var entry = {
      t: Date.now() - startedAt,
      level: level,
      source: inferSource(stack),
      text: text
    };
    if (stack) entry.stack = String(stack).slice(0, STACK_TRUNC);
    buffer.push(entry);
    if (buffer.length > MAX_LOGS) buffer.shift();
    parent.postMessage({ type: "preview-log", entry: entry }, parentOrigin);
  }

  ["log", "info", "warn", "error", "debug"].forEach(function (level) {
    var original = console[level];
    if (typeof original !== "function") return;
    console[level] = function () {
      var stack = level === "warn" || level === "error" ? new Error().stack : "";
      original.apply(console, arguments);
      emit(level, arguments, stack);
    };
  });

  window.addEventListener("error", function (event) {
    var message = String(event.message || "Error");
    var location = event.filename ? " @ " + event.filename + ":" + event.lineno + ":" + event.colno : "";
    var stack = event.error && event.error.stack ? event.error.stack : "";
    emit("error", [message + location], stack);
  });

  window.addEventListener("unhandledrejection", function (event) {
    var reason = event.reason || {};
    var message = reason && reason.message ? reason.message : reason;
    var stack = reason && reason.stack ? reason.stack : "";
    emit("error", ["UnhandledRejection: " + formatValue(message)], stack);
  });

  var readySent = false;
  function sendReady() {
    if (readySent || !parentOrigin || parent === window) return;
    readySent = true;
    parent.postMessage({ type: "preview-ready", data: { build_id: buildId } }, parentOrigin);
  }

  window.addEventListener("message", function (event) {
    if (!isTrustedParentMessage(event)) return;
    // parentOrigin may have just been learned from this message (referrer unavailable)
    sendReady();
    var data = event.data || {};
    if (data.type === "recording-request-start") {
      buffer.length = 0;
      startedAt = Date.now();
      recording = true;
    } else if (data.type === "recording-request-stop" || data.type === "recording-request-cancel") {
      recording = false;
    }
  });

  // Proxy clipboard.writeText to the parent frame (PreviewPanel), which has
  // higher clipboard permission in restricted WebView environments like Codex.
  (function patchClipboard() {
    var clipboard = navigator.clipboard;
    if (!clipboard) {
      clipboard = {};
      try {
        Object.defineProperty(navigator, "clipboard", {
          configurable: true,
          enumerable: true,
          value: clipboard
        });
      } catch (_) {
        return;
      }
    }

    var nativeWrite = typeof clipboard.writeText === "function" ? clipboard.writeText.bind(clipboard) : null;
    var reqCounter = 0;

    function proxyToParent(text) {
      if (!parentOrigin || parent === window) {
        return Promise.reject(new Error("clipboard write failed"));
      }
      var reqId = String(++reqCounter);
      return new Promise(function (resolve, reject) {
        var timer;
        function handler(event) {
          if (!isTrustedParentMessage(event)) return;
          var d = event.data || {};
          if (d.type !== "clipboard-write-response" || d.reqId !== reqId) return;
          clearTimeout(timer);
          window.removeEventListener("message", handler);
          if (d.success) resolve();
          else reject(new Error(d.error || "clipboard write failed"));
        }
        window.addEventListener("message", handler);
        timer = setTimeout(function () {
          window.removeEventListener("message", handler);
          reject(new Error("clipboard bridge timeout"));
        }, 3000);
        parent.postMessage({ type: "clipboard-write-request", text: String(text), reqId: reqId }, parentOrigin);
      });
    }

    var patchedWriteText = function (text) {
      if (!nativeWrite) return proxyToParent(text);
      return nativeWrite(text).catch(function () { return proxyToParent(text); });
    };

    try {
      clipboard.writeText = patchedWriteText;
    } catch (_) {}
    if (clipboard.writeText !== patchedWriteText) {
      try {
        Object.defineProperty(clipboard, "writeText", {
          configurable: true,
          value: patchedWriteText
        });
      } catch (_) {}
    }
  })();

  sendReady();
})();
