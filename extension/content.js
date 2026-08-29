(function () {
  if (window.__liveSubtitleLoaded) return;
  window.__liveSubtitleLoaded = true;

  let overlay = null;
  let translationEl = null;
  let originalEl = null;
  let hideTimer = null;
  let settings = {};

  function targetContainer() {
    return document.fullscreenElement || document.documentElement;
  }

  function ensureOverlay() {
    if (!overlay) {
      overlay = document.createElement("div");
      overlay.id = "live-subtitle-overlay";
      Object.assign(overlay.style, {
        position: "fixed", left: "50%", bottom: "8%",
        transform: "translateX(-50%)", width: "min(86vw, 1100px)",
        zIndex: "2147483647", pointerEvents: "none", textAlign: "center",
        fontFamily: '\"Microsoft YaHei UI\", \"Segoe UI\", sans-serif',
        color: "#fff", textShadow: "0 2px 5px #000, 0 0 2px #000",
        opacity: "0", transition: "opacity 120ms ease",
      });

      const box = document.createElement("div");
      Object.assign(box.style, {
        display: "inline-block", maxWidth: "100%", padding: "10px 18px 12px",
        borderRadius: "10px", background: "rgba(0, 0, 0, 0.68)",
        backdropFilter: "blur(3px)",
      });

      originalEl = document.createElement("div");
      translationEl = document.createElement("div");
      Object.assign(originalEl.style, {
        marginBottom: "4px", color: "rgba(255,255,255,.72)",
        fontSize: "16px", lineHeight: "1.35",
      });
      Object.assign(translationEl.style, {
        fontSize: "28px", fontWeight: "600", lineHeight: "1.38",
      });
      box.append(originalEl, translationEl);
      overlay.appendChild(box);
    }

    const container = targetContainer();
    if (overlay.parentNode !== container) container.appendChild(overlay);
    applySettings();
  }

  function applySettings() {
    if (!overlay) return;
    const size = Math.max(16, Math.min(48, Number(settings.fontSize) || 28));
    translationEl.style.fontSize = `${size}px`;
    originalEl.style.fontSize = `${Math.max(12, Math.round(size * 0.58))}px`;
    originalEl.style.display = settings.showOriginal ? "block" : "none";
    overlay.style.bottom = settings.position === "top" ? "auto" : "8%";
    overlay.style.top = settings.position === "top" ? "7%" : "auto";
  }

  function showSubtitle(original, translation) {
    ensureOverlay();
    originalEl.textContent = original || "";
    translationEl.textContent = translation || original || "";
    overlay.style.opacity = "1";
    clearTimeout(hideTimer);
    hideTimer = setTimeout(() => {
      if (overlay) overlay.style.opacity = "0";
    }, 12000);
  }

  function loadSettings() {
    chrome.runtime.sendMessage({ type: "get_ui_settings" }, (result) => {
      settings = result?.settings || {};
      applySettings();
    });
  }

  document.addEventListener("fullscreenchange", () => {
    if (overlay) setTimeout(ensureOverlay, 0);
  });

  chrome.runtime.onMessage.addListener((message) => {
    if (message.type === "subtitle") showSubtitle(message.original, message.translation);
    if (message.type === "update_ui") loadSettings();
  });

  loadSettings();
})();
