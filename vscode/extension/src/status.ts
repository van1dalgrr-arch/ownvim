// Строка состояния, как у ownvim:
//   музыка (lua/own/music.lua) — « Трек — Исполнитель» из «Сейчас играет» macOS (Яндекс Музыка, Apple Music,
//     Spotify, браузер); клик — пауза, пробел u M — следующий / предыдущий. Пауза — бледно, ничего не играет — нет.
//     Нужен media-control (brew install media-control); настройки — "statusline": { "music": { apps, max, paused } }.
//   отдых (lua/own/modules/rest.lua) — через work_min минут непрерывной работы «⏱ пора отдохнуть»; пауза дольше
//     break_min — уже перерыв, счёт заново. Клик — начать перерыв (☕ и обратный отсчёт). "modules": { "rest": … }.
//   система — RAM и время работы Mac в подсказке у значка ownvim; клик — команды ownvim.
import * as cp from "child_process";
import * as os from "os";
import * as vscode from "vscode";
import { pathEnv, settings } from "./core";

// ── музыка ───────────────────────────────────────────────────────────────────

function music(ctx: vscode.ExtensionContext) {
  const item = vscode.window.createStatusBarItem("ownvim.music", vscode.StatusBarAlignment.Right, 1000);
  item.name = "ownvim: музыка";
  item.command = "ownvim.music.toggle";
  let now: any = {};
  let opts: any = {};
  let proc: cp.ChildProcess | undefined;
  let restarts = 0;

  const paint = () => {
    const apps: string[] = opts.apps || [];
    const ok = !apps.length || apps.includes(now.bundleIdentifier) || apps.includes(now.parentApplicationBundleIdentifier);
    const playing = now.playing === true;
    if (!now.title || !ok || (!playing && opts.paused === false)) return item.hide();
    let text = now.artist ? `${now.title} — ${now.artist}` : now.title;
    const max = opts.max || 40;
    if ([...text].length > max) text = [...text].slice(0, max - 1).join("") + "…";
    item.text = `${playing ? "$(play)" : "$(debug-pause)"} ${text}`;
    item.color = playing ? undefined : new vscode.ThemeColor("disabledForeground");
    item.tooltip = `${now.title}${now.artist ? " — " + now.artist : ""}${now.album ? "\n" + now.album : ""}\nклик — пауза · пробел u M — следующий / предыдущий`;
    item.show();
  };

  const start = () => {
    if (proc || restarts > 3) return;
    let rest = "";
    const p = cp.spawn("media-control", ["stream", "--no-diff", "--no-artwork", "--debounce=150"], { env: { ...process.env, PATH: pathEnv() } });
    proc = p;
    p.stdout.on("data", (d) => {
      rest += d;
      const lines = rest.split("\n");
      rest = lines.pop() || "";
      for (const l of lines) {
        try {
          const m = JSON.parse(l);
          if (m.type === "data") { now = m.payload || {}; paint(); }
        } catch { /* не JSON */ }
      }
    });
    p.on("error", () => { restarts = 99; }); // нет media-control
    // упал (например, после сна Mac) — поднять заново, но не крутиться бесконечно
    p.on("close", () => { proc = undefined; now = {}; paint(); restarts++; setTimeout(start, 2000); });
  };

  const cmd = (c: string) => cp.spawn("media-control", [c], { env: { ...process.env, PATH: pathEnv() } }).on("error", () => {});
  settings().then((s) => {
    const sl = s.statusline || {};
    opts = sl.music || {};
    const right: string[] = sl.right || ["music"];
    if (right.includes("music") && vscode.workspace.getConfiguration("ownvim").get("music") !== false) start();
  });
  ctx.subscriptions.push(
    item,
    vscode.commands.registerCommand("ownvim.music.toggle", () => cmd("toggle-play-pause")),
    vscode.commands.registerCommand("ownvim.music.next", () => cmd("next-track")),
    vscode.commands.registerCommand("ownvim.music.prev", () => cmd("previous-track")),
    vscode.commands.registerCommand("ownvim.music.menu", async () => {
      const p = await vscode.window.showQuickPick([
        { label: "$(debug-pause) пауза / играть", c: "toggle-play-pause" },
        { label: "$(arrow-right) следующий", c: "next-track" },
        { label: "$(arrow-left) предыдущий", c: "previous-track" },
      ], { title: now.title ? `${now.title} — ${now.artist || ""}` : "музыка" });
      if (p) cmd(p.c);
    }),
    { dispose: () => proc?.kill() },
  );
}

// ── отдых ────────────────────────────────────────────────────────────────────

export function minutes(n: number): string {
  const d = n % 10, h = n % 100;
  const w = d === 1 && h !== 11 ? "минута" : d >= 2 && d <= 4 && (h < 12 || h > 14) ? "минуты" : "минут";
  return `${n} ${w}`;
}

function rest(ctx: vscode.ExtensionContext) {
  const MIN = 60_000;
  const item = vscode.window.createStatusBarItem("ownvim.rest", vscode.StatusBarAlignment.Right, 999);
  item.name = "ownvim: отдых";
  let work = 50, brk = 5, show = "due", enabled = false;
  let started = Date.now(), last = Date.now(), snooze = 0, reminded = false, breakUntil = 0;

  const tick = () => {
    if (!enabled) return item.hide();
    const t = Date.now();
    if (breakUntil) {
      if (t >= breakUntil) {
        breakUntil = 0; started = t; reminded = false;
        vscode.window.showInformationMessage("☕ перерыв окончен — за работу");
      } else {
        item.text = `☕ ${Math.ceil((breakUntil - t) / MIN)} мин`;
        item.tooltip = "перерыв · клик — закончить";
        item.command = "ownvim.rest.stop";
        return item.show();
      }
    }
    if (t - last >= brk * MIN) { started = t; reminded = false; snooze = 0; } // долго не трогали — это был перерыв
    const worked = Math.floor((t - started) / MIN);
    const due = worked >= work && t >= snooze;
    if (due && !reminded) {
      reminded = true;
      vscode.window.showInformationMessage(`⏱ работаешь ${minutes(worked)} без перерыва — отдохни ${brk} мин`, "Перерыв", "Через 10 мин").then((a) => {
        if (a === "Перерыв") vscode.commands.executeCommand("ownvim.rest.start");
        if (a === "Через 10 мин") vscode.commands.executeCommand("ownvim.rest.later");
      });
    }
    item.command = "ownvim.rest.start";
    if (due) { item.text = "⏱ пора отдохнуть"; item.tooltip = `без перерыва ${minutes(worked)} · клик — перерыв`; item.show(); }
    else if (show === "always") { item.text = `⏱ ${worked}м`; item.tooltip = `без перерыва ${minutes(worked)}`; item.show(); }
    else item.hide();
  };

  settings().then((s) => {
    const r = s.modules?.rest;
    enabled = r !== false && r !== undefined;
    if (typeof r === "object") { work = r.work_min || work; brk = r.break_min || brk; show = r.show || show; }
    const own = vscode.workspace.getConfiguration("ownvim").get<boolean | null>("rest");
    if (typeof own === "boolean") enabled = own;
    tick();
  });
  const active = () => { const t = Date.now(); if (t - last >= brk * MIN) { started = t; reminded = false; } last = t; };
  const timer = setInterval(tick, 20_000);
  ctx.subscriptions.push(
    item,
    vscode.workspace.onDidChangeTextDocument(active),
    vscode.window.onDidChangeTextEditorSelection(active),
    vscode.commands.registerCommand("ownvim.rest.start", () => { breakUntil = Date.now() + brk * MIN; tick(); }),
    vscode.commands.registerCommand("ownvim.rest.stop", () => { breakUntil = Date.now(); tick(); }),
    vscode.commands.registerCommand("ownvim.rest.later", () => { snooze = Date.now() + 10 * MIN; reminded = false; tick(); }),
    { dispose: () => clearInterval(timer) },
  );
}

// ── система ──────────────────────────────────────────────────────────────────

function uptime(s: number) {
  const d = Math.floor(s / 86400), h = Math.floor((s % 86400) / 3600), m = Math.floor((s % 3600) / 60);
  return d ? `${d}д ${h}ч` : h ? `${h}ч ${m}м` : `${m}м`;
}

function system(ctx: vscode.ExtensionContext) {
  const item = vscode.window.createStatusBarItem("ownvim.system", vscode.StatusBarAlignment.Left, 1000);
  item.name = "ownvim";
  item.text = "$(vm) ownvim";
  item.command = "ownvim.menu";
  const paint = () => {
    const used = (os.totalmem() - os.freemem()) / 2 ** 30, total = os.totalmem() / 2 ** 30;
    const heap = process.memoryUsage().rss / 2 ** 20;
    item.tooltip = `RAM ${used.toFixed(1)} / ${total.toFixed(0)} ГБ · Mac работает ${uptime(os.uptime())}\nрасширения VS Code: ${heap.toFixed(0)} МБ\nклик — команды ownvim`;
  };
  paint();
  if (vscode.workspace.getConfiguration("ownvim").get("statusIcon") !== false) item.show();
  const timer = setInterval(paint, 30_000);
  ctx.subscriptions.push(item, { dispose: () => clearInterval(timer) },
    vscode.commands.registerCommand("ownvim.menu", () => vscode.commands.executeCommand("workbench.action.quickOpen", ">ownvim: ")));
}

export function activate(ctx: vscode.ExtensionContext) {
  music(ctx);
  rest(ctx);
  system(ctx);
}
