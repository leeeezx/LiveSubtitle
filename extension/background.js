// Service worker: manages WebSocket connection to the local translation service
// and fans out subtitle messages to all active content scripts.

const WS_URL = "ws://127.0.0.1:8765";
// 服务刚启动时模型需要加载，采用逐步退避，避免扩展错误页被重复连接错误刷满。
const RECONNECT_DELAYS_MS = [3000, 5000, 10000, 30000, 60000];

let ws = null;
let reconnectTimer = null;
let reconnectAttempt = 0;
let subtitlesEnabled = true;
let cachedConfig = null;

function connect() {
  if (ws && (ws.readyState === WebSocket.OPEN || ws.readyState === WebSocket.CONNECTING)) {
    return;
  }
  try {
    ws = new WebSocket(WS_URL);
  } catch (e) {
    console.warn("[AutoTranslation] WebSocket() threw:", e);
    scheduleReconnect();
    return;
  }

  ws.onopen = () => {
    reconnectAttempt = 0;
    console.log("[AutoTranslation] connected to service");
    broadcastToTabs({ type: "status", status: "connected" });
    notifyPopup({ type: "status", status: "connected" });
    ensureContentScripts();
  };

  ws.onmessage = (event) => {
    let msg;
    try {
      msg = JSON.parse(event.data);
    } catch {
      return;
    }

    if (msg.type === "subtitle" && subtitlesEnabled) {
      broadcastToTabs(msg);
    } else if (msg.type === "config") {
      cachedConfig = msg.config;
      broadcastToTabs(msg);
      notifyPopup(msg);
    } else if (msg.type === "status") {
      broadcastToTabs(msg);
      notifyPopup(msg);
    }
  };

  ws.onclose = () => {
    console.log("[AutoTranslation] disconnected, reconnecting...");
    broadcastToTabs({ type: "status", status: "disconnected" });
    notifyPopup({ type: "status", status: "disconnected" });
    ws = null;
    scheduleReconnect();
  };

  ws.onerror = () => { ws?.close(); };
}

function scheduleReconnect() {
  if (reconnectTimer !== null) return;
  const delay = RECONNECT_DELAYS_MS[
    Math.min(reconnectAttempt, RECONNECT_DELAYS_MS.length - 1)
  ];
  reconnectAttempt += 1;
  reconnectTimer = setTimeout(() => {
    reconnectTimer = null;
    connect();
  }, delay);
}

// 扩展或 Chrome 重启后，为已经打开的网页补注入内容脚本。
// content.js 自带重复加载保护，因此正常页面不会产生双重字幕层。
function ensureContentScripts() {
  chrome.tabs.query({ url: ["http://*/*", "https://*/*"] }, (tabs) => {
    for (const tab of tabs) {
      if (tab.id == null) continue;
      chrome.scripting.executeScript({
        target: { tabId: tab.id },
        files: ["content.js"],
      }).catch(() => {});
    }
  });
}

// Chrome alarms survive service worker sleep — setTimeout/setInterval do not.
chrome.alarms.create("keepAlive", { periodInMinutes: 25 / 60 });
chrome.alarms.onAlarm.addListener((alarm) => {
  if (alarm.name !== "keepAlive") return;
  if (!ws || ws.readyState === WebSocket.CLOSED || ws.readyState === WebSocket.CLOSING) {
    connect();
  } else if (ws.readyState === WebSocket.OPEN) {
    try { ws.send(JSON.stringify({ type: "ping" })); } catch { connect(); }
  }
});

function broadcastToTabs(msg) {
  chrome.tabs.query({}, (tabs) => {
    for (const tab of tabs) {
      if (tab.id != null) {
        chrome.tabs.sendMessage(tab.id, msg).catch(() => {});
      }
    }
  });
}

function notifyPopup(msg) {
  chrome.runtime.sendMessage(msg).catch(() => {});
}

// Messages from popup or content scripts
chrome.runtime.onMessage.addListener((msg, _sender, sendResponse) => {
  if (msg.type === "toggle_subtitles") {
    subtitlesEnabled = msg.enabled;
    sendResponse({ ok: true });
    return true;
  }

  if (msg.type === "update_config") {
    if (ws?.readyState !== WebSocket.OPEN) {
      sendResponse({ ok: false, error: "Service not connected. Is run.py running?" });
      return true;
    }
    ws.send(JSON.stringify(msg));
    sendResponse({ ok: true });
    return true;
  }

  if (msg.type === "get_config") {
    sendResponse({ config: cachedConfig });
    return true;
  }

  if (msg.type === "get_status") {
    sendResponse({
      connected: ws?.readyState === WebSocket.OPEN,
      subtitlesEnabled,
    });
    return true;
  }

  if (msg.type === "get_ui_settings") {
    chrome.storage.local.get(["autotranslation_ui"], (result) => {
      sendResponse({ settings: result.autotranslation_ui || {} });
    });
    return true;
  }

  if (msg.type === "set_ui_settings") {
    chrome.storage.local.set({ autotranslation_ui: msg.settings }, () => {
      broadcastToTabs({ type: "update_ui" });
      sendResponse({ ok: true });
    });
    return true;
  }
});

setTimeout(connect, 0);
