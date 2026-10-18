"use strict";

// Every call to the app: `await fluent(op, args)`, a POST to /api/<op>
// served next to the pages (Settings/api.go).
async function fluent(op, args = {}) {
  const res = await fetch("/api/" + op, {
    method: "POST",
    headers: { "Content-Type": "application/json" },
    body: JSON.stringify(args),
  });
  if (!res.ok) throw new Error(await res.text());
  return res.json();
}

// Wails' runtime drags the window by the header (--wails-draggable).
import("/wails/runtime.js").catch(() => {});

const $ = (selector, root = document) => root.querySelector(selector);
const $$ = (selector, root = document) => [...root.querySelectorAll(selector)];

let lang = "en";
let config = {};
let configStamp = 0;

// MARK: - Language

function t(text, vars) {
  const translated = (I18N[lang] && I18N[lang][text]) || text;
  return vars ? translated.replace(/\{(\w+)\}/g, (_, key) => vars[key]) : translated;
}

function translatePage() {
  document.documentElement.lang = lang === "zh" ? "zh-Hans" : "en";
  for (const el of $$("[data-t]")) {
    if (el.dataset.source === undefined) el.dataset.source = el.textContent.trim();
    el.textContent = t(el.dataset.source);
  }
  for (const el of $$("[data-t-placeholder]")) el.placeholder = t(el.dataset.tPlaceholder);
}

async function loadLanguage() {
  const prefs = await fluent("prefs.get");
  const chosen = prefs.language || "system";
  lang = chosen === "system" ? (String(prefs.system).toLowerCase().startsWith("zh") ? "zh" : "en") : chosen;
  markChoice($("#language"), chosen);
  translatePage();
}

$("#language").addEventListener("click", async (event) => {
  const button = event.target.closest("button");
  if (!button) return;
  await fluent("prefs.set", { language: button.dataset.value });
  await loadLanguage();
  await refreshStatus(true);
});

// MARK: - Pages

function show(view) {
  for (const button of $$("#nav button")) button.classList.toggle("on", button.dataset.view === view);
  for (const section of $$(".view")) section.classList.toggle("on", section.id === view);
  try { localStorage.setItem("view", view); } catch {}
}

$("#nav").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-view]");
  if (button) show(button.dataset.view);
});
for (const button of $$("[data-go]")) button.addEventListener("click", () => show(button.dataset.go));
for (const button of $$("[data-open]")) button.addEventListener("click", () => fluent("open", { what: button.dataset.open }));

let toastTimer;
function toast(message, bad = false) {
  const el = $("#toast");
  el.textContent = message;
  el.classList.toggle("bad", bad);
  el.hidden = false;
  clearTimeout(toastTimer);
  toastTimer = setTimeout(() => { el.hidden = true; }, 1600);
}

// MARK: - Config fields

function markChoice(choice, value) {
  for (const button of $$("button", choice)) button.classList.toggle("on", button.dataset.value === value);
}

function fill() {
  for (const el of $$("[data-key]")) {
    if (el === document.activeElement) continue;  // don't clobber what is being typed
    const value = config[el.dataset.key];
    if (el.classList.contains("choice")) {
      markChoice(el, value ?? el.dataset.default);
    } else if (el.type === "checkbox") {
      el.checked = value ?? el.dataset.default === "true";
    } else if (el.tagName === "TEXTAREA") {
      el.value = Array.isArray(value) ? value.join("\n") : "";
    } else {
      el.value = value ?? "";
    }
  }
  const fuzzy = new Set(config.fuzzyPinyin || []);
  for (const box of $$("#fuzzy input")) box.checked = fuzzy.has(box.value);
  $("#pinyinOptions").classList.toggle("disabled", (config.chinese || "xiaohe") !== "pinyin");
}

/** The field's value as the config wants it; null removes the key. */
function valueOf(el) {
  if (el.type === "checkbox") return el.checked;
  if (el.tagName === "TEXTAREA") {
    const lines = el.value.split("\n").map((line) => line.trim()).filter(Boolean);
    return lines.length ? lines : null;
  }
  const text = el.value.trim();
  if (text === "") return null;
  return el.type === "number" ? Number(text) : text;
}

async function save(key, value) {
  const reply = await fluent("config.set", { key, value });
  if (!reply.ok) return toast(t("Couldn't save: the config file isn't valid JSON."), true);
  if (value === null) delete config[key]; else config[key] = value;
  fill();
  toast(t("Saved"));
  refreshStatus();
}

for (const el of $$("input[data-key], select[data-key], textarea[data-key]")) {
  el.addEventListener("change", () => {
    const value = valueOf(el);
    if (JSON.stringify(value) !== JSON.stringify(config[el.dataset.key] ?? null)) save(el.dataset.key, value);
  });
}
for (const choice of $$(".choice[data-key]")) {
  choice.addEventListener("click", (event) => {
    const button = event.target.closest("button");
    if (button && !button.classList.contains("on")) save(choice.dataset.key, button.dataset.value);
  });
}
$("#fuzzy").addEventListener("change", () => {
  const pairs = $$("#fuzzy input").filter((box) => box.checked).map((box) => box.value);
  save("fuzzyPinyin", pairs.length ? pairs : null);
});

$("#showKey").addEventListener("click", () => {
  const field = $("#apiKey");
  field.type = field.type === "password" ? "text" : "password";
  $("#showKey").dataset.source = field.type === "password" ? "Show" : "Hide";
  $("#showKey").textContent = t($("#showKey").dataset.source);
});

// MARK: - Status

function check(id, state) {
  const item = $(`#chk-${id}`);
  item.classList.toggle("ok", state === true);
  item.classList.toggle("warn", state === "warn");
}

async function refreshStatus(force = false) {
  const status = await fluent("status");
  check("installed", status.installed);
  check("enabled", status.enabled);
  check("selected", status.selected);
  check("dictionaries", status.dictionaries);
  const problem = status.configProblem;
  check("configured", status.configured ? true : problem ? "warn" : false);
  const sub = $("#configured-sub");
  sub.textContent = problem ? t("Config error: {problem}", { problem }) : t(sub.dataset.source);
  $("#learned").textContent = t("{n} words", { n: status.learned });
  $("#version").textContent = status.version;
  $("#configPath").textContent = status.configPath;
  if (force || status.configStamp !== configStamp) {
    configStamp = status.configStamp;
    config = await fluent("config.get");
    fill();
  }
}

// MARK: - Actions

$("#test").addEventListener("click", async () => {
  const button = $("#test");
  const result = $("#testResult");
  button.disabled = true;
  result.className = "result";
  result.textContent = t("Testing…");
  const reply = await fluent("test");
  button.disabled = false;
  if (reply.ok) {
    result.className = "result ok";
    result.textContent = `✓ “${reply.input}” → “${reply.text}” · ${(reply.ms / 1000).toFixed(1)} s`;
  } else {
    result.className = "result bad";
    result.textContent = reply.code === "notConfigured" ? t("Set the provider URL, API key and model first.")
      : reply.code === "configError" ? t("Config error: {problem}", { problem: reply.error })
      : `⚠ ${reply.error}`;
  }
});

$("#forget").addEventListener("click", async () => {
  const reply = await fluent("learned.forget", {
    title: t("Forget learned words?"),
    detail: t("Candidates go back to the dictionary's order. This can't be undone."),
    confirm: t("Forget"),
    cancel: t("Cancel"),
  });
  if (reply.ok) { toast(t("Forgot the learned words")); refreshStatus(); }
});

// MARK: - Start

(async () => {
  await loadLanguage();
  try { const view = localStorage.getItem("view"); if (view && $(`#${view}`)) show(view); } catch {}
  await refreshStatus(true);
  // Live: the input method, Input Sources and the file can change elsewhere.
  setInterval(() => { if (!document.hidden) refreshStatus(); }, 2000);
})();
