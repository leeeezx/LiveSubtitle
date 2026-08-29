const byId = (id) => document.getElementById(id);

function setStatus(connected) {
  byId("status-dot").className = `dot ${connected ? "connected" : "disconnected"}`;
  byId("status-text").textContent = connected ? "本地服务已连接" : "本地服务未启动或正在加载模型";
}

chrome.runtime.sendMessage({ type: "get_status" }, (result) => {
  setStatus(Boolean(result?.connected));
  if (result) byId("toggle-subtitles").checked = result.subtitlesEnabled;
});
chrome.runtime.sendMessage({ type: "get_config" }, (result) => {
  const config = result?.config;
  if (!config) return;
  byId("source-language").value = config.source_language || "";
  byId("target-language").value = config.target_language || "简体中文";
});
chrome.runtime.sendMessage({ type: "get_ui_settings" }, (result) => {
  const ui = result?.settings || {};
  byId("font-size").value = Number(ui.fontSize) || 28;
  byId("position").value = ui.position || "bottom";
  byId("show-original").checked = Boolean(ui.showOriginal);
});
chrome.runtime.onMessage.addListener((message) => {
  if (message.type === "status") setStatus(message.status === "connected");
});
byId("toggle-subtitles").addEventListener("change", (event) => {
  chrome.runtime.sendMessage({ type: "toggle_subtitles", enabled: event.target.checked });
});
byId("save-btn").addEventListener("click", () => {
  const button = byId("save-btn");
  chrome.runtime.sendMessage({ type: "set_ui_settings", settings: {
    fontSize: Number(byId("font-size").value),
    position: byId("position").value,
    showOriginal: byId("show-original").checked,
  }});
  chrome.runtime.sendMessage({ type: "update_config", config: {
    source_language: byId("source-language").value,
    target_language: byId("target-language").value,
  }}, (result) => {
    button.textContent = result?.ok ? "已应用" : "服务尚未连接";
    setTimeout(() => { button.textContent = "应用设置"; }, 1600);
  });
});
