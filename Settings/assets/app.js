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

// MARK: - ⇧⇧ notice previews

// Each style of the ⇧⇧ notice (toggleNotice), on and then off, drawn after
// the input method's Sources/Fluent/ToggleNotice.swift, in its points.
function noticePreview(style) {
  const css = (property, value) => `style="${property}:var(--n-${value})"`;
  const fill = (value) => css("fill", value);

  // The menu bar's FL badge: 22×16 with a corner radius of 5, at height h.
  // "on" and "off" have white letters (the badge style); "cut" is indigo with
  // letters in the panel's colour, as if cut out; "outline" is for off.
  function badge(x, y, h, look) {
    const w = (h * 22) / 16, r = (h * 5) / 16, stroke = h * 0.155;
    const at = (fx, fy) => `${(x + fx * w).toFixed(2)},${(y + fy * h).toFixed(2)}`;
    const letters = (color, width) => `<path d="M${at(.217, .721)}L${at(.217, .279)}L${at(.414, .279)}`
      + `M${at(.217, .5)}L${at(.383, .5)}M${at(.6, .279)}L${at(.6, .721)}L${at(.797, .721)}" fill="none" `
      + `style="stroke:${color}" stroke-width="${width}" stroke-linecap="round" stroke-linejoin="round"/>`;
    if (look === "outline") {
      return `<rect x="${x + .75}" y="${y + .75}" width="${w - 1.5}" height="${h - 1.5}" rx="${r - .75}" fill="none" `
        + `${css("stroke", "second")} stroke-width="1.5"/>` + letters("var(--n-second)", stroke * .85);
    }
    return `<rect x="${x}" y="${y}" width="${w}" height="${h}" rx="${r}" ${fill(look === "off" ? "off" : "indigo")}/>`
      + letters(look === "cut" ? "var(--n-panel)" : "#fff", stroke);
  }

  // A body of w×h with corner radius r, its tail's tip at (tip, top) when
  // there is one.
  function panel(x, y, w, h, r, tip) {
    const top = tip === undefined ? y : y + 7;
    let d = `M${x + r},${top}`;
    if (tip !== undefined) d += `L${tip - 7},${top}L${tip},${y}L${tip + 7},${top}`;
    d += `L${x + w - r},${top}A${r},${r} 0 0 1 ${x + w},${top + r}L${x + w},${top + h - r}`
      + `A${r},${r} 0 0 1 ${x + w - r},${top + h}L${x + r},${top + h}A${r},${r} 0 0 1 ${x},${top + h - r}`
      + `L${x},${top + r}A${r},${r} 0 0 1 ${x + r},${top}Z`;
    return { svg: `<path d="${d}" ${fill("panel")} ${css("stroke", "edge")} stroke-width=".5" filter="url(#shadow-${style})"/>`, top };
  }

  const word = (x, midY, on) => `<text x="${x}" y="${midY + 5.3}" font-size="15" font-weight="600" `
    + `${fill(on ? "label" : "second")}>${on ? "On" : "Off"}</text>`;
  const keys = (x, midY) => [0, 21].map((dx) => `<rect x="${x + dx + .3}" y="${midY - 8.7}" width="17.4" height="17.4" rx="4.5" `
    + `${fill("key")} ${css("stroke", "edge")} stroke-width=".6"/><text x="${x + dx + 9}" y="${midY + 4.3}" font-size="12" `
    + `font-weight="500" text-anchor="middle" ${fill("second")}>⇧</text>`).join("");

  const metrics = {
    pill: { height: 34, radius: 17, badge: 18, leading: 10, trailing: 14, word: true, keys: true },
    bubble: { height: 32, radius: 9, badge: 22, leading: 10, trailing: 12, word: true, keys: false },
    keys: { height: 32, radius: 9, badge: 22, leading: 9, trailing: 9, minWidth: 52, word: false, keys: true },
  };

  // One scene: a caret, and the notice 6 points under it.
  function scene(cx, on) {
    const caretBottom = 22, top = caretBottom + 6;
    const caret = (x) => `<rect x="${x - 1}" y="${caretBottom - 16}" width="2" height="16" rx="1" ${fill("caret")}/>`;
    if (style === "badge") {
      const w = 33;
      return caret(cx) + `<rect x="${cx - w / 2}" y="${top + 1.5}" width="${w}" height="24" rx="7.5" fill="#000" `
        + `opacity=".25" filter="url(#blur-${style})"/>` + badge(cx - w / 2, top, 24, on ? "on" : "off");
    }
    const m = metrics[style];
    const items = ["badge", ...(m.word ? ["word"] : []), ...(m.keys && !on ? ["keys"] : [])];
    const widths = { badge: (m.badge * 22) / 16, word: on ? 21 : 24, keys: 39 };
    const width = Math.max(m.minWidth || 0, m.leading + m.trailing
      + items.reduce((sum, item, i) => sum + widths[item] + (i ? (item === "keys" ? 10 : 8) : 0), 0));
    const x = cx - width / 2;
    // The pill starts at the caret, like the candidate bar; bubbles point at it.
    const caretX = style === "pill" ? x + 1 : cx;
    const shape = panel(x, top, width, m.height, m.radius, style === "pill" ? undefined : cx);
    const midY = shape.top + m.height / 2;
    let out = caret(caretX) + shape.svg;
    let at = items.length === 1 ? cx - widths.badge / 2 : x + m.leading;
    items.forEach((item, i) => {
      if (i) at += item === "keys" ? 10 : 8;
      if (item === "badge") out += badge(at, midY - m.badge / 2, m.badge, on ? "cut" : "outline");
      if (item === "word") out += word(at, midY, on);
      if (item === "keys") out += keys(at, midY);
      at += widths[item];
    });
    return out;
  }

  return `<svg viewBox="0 0 320 76" xmlns="http://www.w3.org/2000/svg" font-family="-apple-system, BlinkMacSystemFont, sans-serif">`
    + `<defs><filter id="shadow-${style}" x="-20%" y="-30%" width="140%" height="180%">`
    + `<feDropShadow dx="0" dy="2" stdDeviation="3" flood-opacity=".2"/></filter>`
    + `<filter id="blur-${style}" x="-30%" y="-30%" width="160%" height="180%"><feGaussianBlur stdDeviation="2.5"/></filter></defs>`
    + `<rect width="320" height="76" ${fill("doc")}/>` + scene(80, true) + scene(240, false) + `</svg>`;
}

for (const el of $$(".preview[data-preview]")) el.innerHTML = noticePreview(el.dataset.preview);

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
