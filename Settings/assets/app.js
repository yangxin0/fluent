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
  $("#pinyinOptions").classList.toggle("disabled", (config.chinese || "pinyin") !== "pinyin");
  fillProviders();
  fillPrompt();
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

// One save at a time, in order: two quick edits of a key never land the
// wrong way round.
let saving = Promise.resolve();

/** Sets keys in order (null removes one). The page shows the new values at
 *  once, so a Test right after an edit already uses them. */
function saveAll(changes) {
  for (const [key, value] of changes) {
    config = { ...config };
    if (value === null) delete config[key]; else config[key] = value;
  }
  fill();
  saving = saving.then(async () => {
    for (const [key, value] of changes) {
      const reply = await fluent("config.set", { key, value });
      if (!reply.ok) {
        toast(t("Couldn't save: the config file isn't valid JSON."), true);
        return refreshStatus(true);
      }
    }
    toast(t("Saved"));
    refreshStatus();
  });
  return saving;
}

const save = (key, value) => saveAll([[key, value]]);

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

// MARK: - Providers

// The provider in the form, by its place in the list.
let selected = 0;

const isObject = (value) => value !== null && typeof value === "object" && !Array.isArray(value);
const nameOf = (provider) => (typeof provider.name === "string" ? provider.name.trim() : "");
const apiOf = (provider) => (String(provider.api ?? "").trim().toLowerCase() === "chat" ? "chat" : "responses");
const endpointKeys = ["baseURL", "apiKey", "model", "reasoningEffort"];
const hasList = () => Array.isArray(config.providers) && config.providers.some(isObject);

function hostOf(url) {
  try { return new URL(String(url).trim()).hostname; } catch { return ""; }
}

/** The saved providers (docs/config.md). A config from before them has its
 *  one endpoint at the top level: that is the list's only provider. */
function providerList() {
  if (hasList()) return config.providers.filter(isObject);
  const one = { name: hostOf(config.baseURL) || t("Provider {n}", { n: 1 }), api: "responses" };
  for (const key of endpointKeys) {
    if (typeof config[key] === "string" && config[key] !== "") one[key] = config[key];
  }
  return [one];
}

/** The provider in use: the one `provider` names, else the first. */
function activeIndex(list) {
  if (typeof config.provider !== "string") return 0;
  const index = list.findIndex((provider) => nameOf(provider) === config.provider.trim());
  return index < 0 ? 0 : index;
}

/** Saves the list, and the name of the one in use when it changes. The
 *  first list saved takes over from the top-level endpoint keys. */
function saveProviders(list, inUse) {
  const changes = [["providers", list]];
  if (!hasList()) {
    changes.push(["provider", inUse ?? nameOf(list[0])]);
    for (const key of endpointKeys) if (key in config) changes.push([key, null]);
  } else if (inUse !== undefined) {
    changes.push(["provider", inUse]);
  }
  return saveAll(changes);
}

function fillProviders() {
  const list = providerList();
  selected = Math.max(0, Math.min(selected, list.length - 1));
  const active = activeIndex(list);
  $("#providers").replaceChildren(...list.map((provider, index) => {
    const row = document.createElement("li");
    row.dataset.index = index;
    row.classList.toggle("on", index === selected);
    const text = document.createElement("div");
    text.className = "text";
    const name = document.createElement("b");
    name.textContent = nameOf(provider) || t("Unnamed");
    const sub = document.createElement("span");
    sub.className = "sub";
    const model = typeof provider.model === "string" && provider.model.trim() ? provider.model.trim() : t("No model");
    sub.textContent = `${model} · ${apiOf(provider) === "chat" ? "Chat Completions" : "Responses"}`;
    text.append(name, sub);
    row.append(text);
    if (index === active) {
      const tag = document.createElement("span");
      tag.className = "tag";
      tag.textContent = t("In use");
      row.append(tag);
    } else {
      const use = document.createElement("button");
      use.className = "pill";
      use.dataset.use = index;
      use.textContent = t("Use");
      row.append(use);
    }
    return row;
  }));
  const provider = list[selected];
  for (const el of $$("#provider [data-field]")) {
    if (el === document.activeElement) continue;  // don't clobber what is being typed
    const value = provider[el.dataset.field];
    if (el.classList.contains("choice")) markChoice(el, apiOf(provider));
    else el.value = typeof value === "string" ? value.trim() : "";
  }
  $("#deleteProvider").disabled = list.length < 2;
}

/** One field of the provider in the form; null removes it. */
function editProvider(field, value) {
  const list = providerList().map((provider) => ({ ...provider }));
  const provider = list[selected];
  const inUse = selected === activeIndex(list);
  if (field === "name") {
    const taken = list.some((other, index) => index !== selected && nameOf(other) === value);
    if (!value || taken) {
      toast(t(value ? "Another provider has that name." : "A provider needs a name."), true);
      $("#provider [data-field=name]").value = nameOf(provider);
      return;
    }
  }
  if (value === null) delete provider[field]; else provider[field] = value;
  if (JSON.stringify(list) === JSON.stringify(providerList())) return;
  // Renaming the one in use renames it in `provider` too.
  saveProviders(list, field === "name" && inUse ? value : undefined);
}

for (const el of $$("#provider input[data-field], #provider select[data-field]")) {
  el.addEventListener("change", () => editProvider(el.dataset.field, el.value.trim() || null));
}
$("#provider .choice[data-field]").addEventListener("click", (event) => {
  const button = event.target.closest("button");
  if (button && !button.classList.contains("on")) editProvider("api", button.dataset.value);
});

$("#providers").addEventListener("click", (event) => {
  const use = event.target.closest("button[data-use]");
  if (use) return save("provider", nameOf(providerList()[Number(use.dataset.use)]));
  const row = event.target.closest("li[data-index]");
  if (!row || Number(row.dataset.index) === selected) return;
  selected = Number(row.dataset.index);
  $("#testResult").textContent = "";
  fillProviders();
});

$("#addProvider").addEventListener("click", () => {
  const list = providerList().map((provider) => ({ ...provider }));
  let n = list.length + 1;
  while (list.some((provider) => nameOf(provider) === t("Provider {n}", { n }))) n++;
  list.push({ name: t("Provider {n}", { n }), api: "responses" });
  selected = list.length - 1;
  $("#testResult").textContent = "";
  saveProviders(list);
  $("#provider [data-field=name]").select();
});

$("#deleteProvider").addEventListener("click", async () => {
  const list = providerList();
  if (list.length < 2) return;
  const reply = await fluent("confirm", {
    title: t("Delete {name}?", { name: nameOf(list[selected]) || t("Unnamed") }),
    detail: t("Its URL, API key and model go with it."),
    confirm: t("Delete"),
    cancel: t("Cancel"),
  });
  if (!reply.ok) return;
  const rest = list.filter((_, index) => index !== selected);
  // Deleting the one in use puts the first one left in use.
  const inUse = selected === activeIndex(list) ? nameOf(rest[0]) : undefined;
  selected = Math.min(selected, rest.length - 1);
  $("#testResult").textContent = "";
  saveProviders(rest, inUse);
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
  // One style attribute: a second one on the element would be dropped.
  const fillAndEdge = (value) => `style="fill:var(--n-${value});stroke:var(--n-edge)"`;

  // The menu bar's FL badge: 22×16 with a corner radius of 5, at height h.
  // "on" and "off" have white letters (the badge style); "cut" is indigo with
  // letters in the panel's colour, as if cut out; "outline" is for off.
  // `scale` sizes the letters, centred on their ink, against the menu bar's.
  function badge(x, y, h, look, scale = 1) {
    const w = (h * 22) / 16, r = (h * 5) / 16, stroke = h * 0.155 * scale;
    const at = (fx, fy) => `${(x + (0.5 + (fx - 0.507) * scale) * w).toFixed(2)},`
      + `${(y + (0.5 + (fy - 0.5) * scale) * h).toFixed(2)}`;
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
    return { svg: `<path d="${d}" ${fillAndEdge("panel")} stroke-width=".5" filter="url(#shadow-${style})"/>`, top };
  }

  const word = (x, midY, on) => `<text x="${x}" y="${midY + 5.3}" font-size="15" font-weight="600" `
    + `${fill(on ? "label" : "second")}>${on ? "On" : "Off"}</text>`;
  const keys = (x, midY) => [0, 21].map((dx) => `<rect x="${x + dx + .3}" y="${midY - 8.7}" width="17.4" height="17.4" rx="4.5" `
    + `${fillAndEdge("key")} stroke-width=".6"/><text x="${x + dx + 9}" y="${midY + 4.3}" font-size="12" `
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
        + `opacity=".25" filter="url(#blur-${style})"/>` + badge(cx - w / 2, top, 24, on ? "on" : "off", 0.8);
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

// MARK: - Prompts

// The built-in prompts, and the rule Fluent puts after every prompt.
let defaults = {};
let promptMode = "fix";
// What Try sends when its field is empty.
const samples = {
  fix: "helo wrld, how r u",
  polish: "i want know if this way can work good",
  translate: "这个 bug 我明天 fix，你先 review 一下",
};

const ownPrompts = () => (isObject(config.prompts) ? config.prompts : {});

function ownPrompt(mode) {
  const text = ownPrompts()[mode];
  return typeof text === "string" && text.trim() ? text : null;
}

function fillPrompt() {
  markChoice($("#promptMode"), promptMode);
  const own = ownPrompt(promptMode);
  const editor = $("#prompt");
  if (editor !== document.activeElement) editor.value = own ?? defaults[promptMode] ?? "";
  $("#promptState").textContent = t(own ? "Your own prompt" : "Built-in prompt");
  $("#resetPrompt").disabled = !own;
  $("#tryInput").placeholder = samples[promptMode];
  $("#outputRule").textContent = defaults.outputRule ?? "";
  // Try asks the provider in use, which is on the LLM page.
  const providers = providerList();
  $("#tryProvider").textContent = t("Uses {name}, the provider in use.",
    { name: nameOf(providers[activeIndex(providers)]) || t("Unnamed") });
}

/** Saves the mode's prompt; blank or the built-in one removes it, so the
 *  built-in prompt (which may improve) is used. */
function savePrompt(text) {
  const prompts = { ...ownPrompts() };
  text = (text ?? "").trim();
  if (!text || text === defaults[promptMode]) delete prompts[promptMode]; else prompts[promptMode] = text;
  if (JSON.stringify(prompts) === JSON.stringify(ownPrompts())) return fillPrompt();
  save("prompts", Object.keys(prompts).length ? prompts : null);
}

$("#prompt").addEventListener("change", () => savePrompt($("#prompt").value));
$("#resetPrompt").addEventListener("click", () => {
  $("#prompt").value = defaults[promptMode] ?? "";
  savePrompt(null);
});
$("#promptMode").addEventListener("click", (event) => {
  const button = event.target.closest("button[data-value]");
  if (!button || button.dataset.value === promptMode) return;
  promptMode = button.dataset.value;
  $("#tryInput").value = "";
  $("#tryRow").hidden = true;
  fillPrompt();
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

/** A Test or Try reply: what went in and came out, or what went wrong. */
function showReply(result, reply) {
  if (reply.ok) {
    result.className = "result ok";
    result.textContent = `✓ “${reply.input}” → “${reply.text}” · ${(reply.ms / 1000).toFixed(1)} s`;
  } else {
    result.className = "result bad";
    result.textContent = reply.code === "notConfigured" ? t("Set the provider URL, API key and model first.")
      : reply.code === "configError" ? t("Config error: {problem}", { problem: reply.error })
      : `⚠ ${reply.error}`;
  }
}

/** Runs one request from button and shows its reply in result. */
async function ask(button, result, waiting, op, args) {
  button.disabled = true;
  result.className = "result";
  result.textContent = t(waiting);
  const reply = await fluent(op, args());
  button.disabled = false;
  showReply(result, reply);
}

// The provider in the form, as edited: it may not be the one in use.
$("#test").addEventListener("click", () =>
  ask($("#test"), $("#testResult"), "Testing…", "test", () => ({ provider: providerList()[selected] })));

// The mode's prompt as it is in the editor, with the provider in use.
function tryPrompt() {
  $("#tryRow").hidden = false;
  ask($("#tryPrompt"), $("#tryResult"), "Trying…", "try", () => ({
    mode: promptMode,
    input: $("#tryInput").value.trim() || samples[promptMode],
    prompt: $("#prompt").value,
  }));
}
$("#tryPrompt").addEventListener("click", tryPrompt);
$("#tryInput").addEventListener("keydown", (event) => { if (event.key === "Enter") tryPrompt(); });

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
  defaults = await fluent("prompts.defaults");
  try { const view = localStorage.getItem("view"); if (view && $(`#${view}`)) show(view); } catch {}
  await refreshStatus(true);
  // Live: the input method, Input Sources and the file can change elsewhere.
  setInterval(() => { if (!document.hidden) refreshStatus(); }, 2000);
})();
