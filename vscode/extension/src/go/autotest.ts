// Тесты Go в фоне (core/extensions/autotest): сохранили Go-файл — через секунду go test его пакета (из кэша —
// мгновенно). В строке состояния ✓ 42 / ✗ 1 / ✗ сборка, упавшая проверка — ошибкой на своей строке в _test.go,
// даже если открыт другой файл. Клик по статусу — упавшие тесты пакета (enter — к тесту). Выключить — ownvim.go.autotest.
import * as cp from "child_process";
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { pathEnv } from "../core";

export type Fail = { test: string; file: string; line: number; msg: string };
export type Result = { passed: number; failed: number; build: boolean; tests: { name: string; pass: boolean; skip: boolean }[]; fails: Fail[] };

const failLine = /^\s+([\w\-.]+_test\.go):(\d+): (.*?)\s*$/;

/** вывод go test -json → результат; exitCode не ноль без единого теста — не собрался */
export function parse(out: string, exitCode: number): Result {
  const r: Result = { passed: 0, failed: 0, build: false, tests: [], fails: [] };
  const output = new Map<string, string[]>();
  const failed = new Set<string>();
  const seen = new Map<string, number>();
  for (const line of out.split("\n")) {
    let ev: any;
    try { ev = JSON.parse(line); } catch { continue; }
    if (!ev?.Test) continue;
    const topName = ev.Test.split("/")[0];
    if (ev.Action === "output") output.set(ev.Test, [...(output.get(ev.Test) || []), ev.Output]);
    else if (["pass", "fail", "skip"].includes(ev.Action)) {
      if (ev.Action === "fail") failed.add(ev.Test);
      if (ev.Test !== topName) continue;
      const t = { name: topName, pass: ev.Action === "pass", skip: ev.Action === "skip" };
      if (seen.has(topName)) r.tests[seen.get(topName)!] = t;
      else { seen.set(topName, r.tests.length); r.tests.push(t); }
    }
  }
  for (const t of r.tests) if (t.pass) r.passed++; else if (!t.skip) r.failed++;
  for (const t of [...failed].sort()) for (const o of output.get(t) || []) {
    const m = o.match(failLine);
    if (m) r.fails.push({ test: t, file: m[1], line: +m[2], msg: m[3] });
  }
  r.build = exitCode !== 0 && r.passed === 0 && r.failed === 0;
  r.tests.sort((a, b) => (a.pass !== b.pass ? (a.pass ? 1 : -1) : a.name.localeCompare(b.name)));
  return r;
}

function testable(file: string): string | undefined {
  if (!file.endsWith(".go")) return;
  const dir = path.dirname(file);
  let d = dir, mod = false;
  for (let i = 0; i < 10 && !mod; i++) { mod = fs.existsSync(path.join(d, "go.mod")); d = path.dirname(d); }
  if (!mod) return;
  try { if (fs.readdirSync(dir).some((f) => f.endsWith("_test.go"))) return dir; } catch { /* нет папки */ }
}

export function activate(ctx: vscode.ExtensionContext) {
  const on = () => vscode.workspace.getConfiguration("ownvim.go").get("autotest") !== false;
  const diags = vscode.languages.createDiagnosticCollection("go test");
  const bar = vscode.window.createStatusBarItem("ownvim.autotest", vscode.StatusBarAlignment.Left, 40);
  bar.name = "ownvim: тесты в фоне";
  bar.command = "ownvim.go.autotestShow";
  const results = new Map<string, Result>();
  const running = new Map<string, cp.ChildProcess>();
  const timers = new Map<string, NodeJS.Timeout>();
  let lastDir = "";

  const paint = () => {
    const ed = vscode.window.activeTextEditor;
    const dir = ed && ed.document.languageId === "go" ? path.dirname(ed.document.uri.fsPath) : lastDir;
    const r = results.get(dir);
    if (!on() || !dir || (!r && !running.has(dir))) return bar.hide();
    const bad = !running.has(dir) && !!r && (r.build || r.failed > 0);
    bar.backgroundColor = bad ? new vscode.ThemeColor("statusBarItem.errorBackground") : undefined;
    if (running.has(dir)) bar.text = "$(sync~spin) go test";
    else if (r!.build) bar.text = "$(error) сборка";
    else if (r!.failed) bar.text = `$(error) ${r!.failed}  $(pass) ${r!.passed}`;
    else bar.text = `$(pass) ${r!.passed}`;
    bar.tooltip = `go test ${vscode.workspace.asRelativePath(dir)} — клик: упавшие`;
    bar.show();
  };

  const test = (dir: string) => {
    running.get(dir)?.kill();
    let out = "";
    const p = cp.spawn("go", ["test", "-json", "-count=1", "."], { cwd: dir, env: { ...process.env, PATH: pathEnv() } });
    running.set(dir, p);
    paint();
    p.stdout.on("data", (d) => (out += d));
    p.on("error", () => running.delete(dir));
    p.on("close", (code) => {
      if (running.get(dir) !== p) return;
      running.delete(dir);
      const r = parse(out, code ?? 1);
      results.set(dir, r);
      // старые замечания пакета — убрать, новые — на строки
      diags.forEach((uri) => { if (path.dirname(uri.fsPath) === dir) diags.delete(uri); });
      const by = new Map<string, vscode.Diagnostic[]>();
      for (const f of r.fails) {
        const file = path.join(dir, f.file);
        const d = new vscode.Diagnostic(new vscode.Range(f.line - 1, 0, f.line - 1, 1000), `${f.test}: ${f.msg}`, vscode.DiagnosticSeverity.Error);
        d.source = "go test";
        by.set(file, [...(by.get(file) || []), d]);
      }
      for (const [f, ds] of by) diags.set(vscode.Uri.file(f), ds);
      paint();
    });
  };

  ctx.subscriptions.push(
    diags, bar,
    vscode.workspace.onDidSaveTextDocument((d) => {
      if (!on() || d.languageId !== "go") return;
      const dir = testable(d.uri.fsPath);
      if (!dir) return;
      lastDir = dir;
      clearTimeout(timers.get(dir));
      timers.set(dir, setTimeout(() => test(dir), 1000));
    }),
    vscode.window.onDidChangeActiveTextEditor(paint),
    vscode.workspace.onDidChangeConfiguration((e) => { if (e.affectsConfiguration("ownvim.go.autotest")) { if (!on()) diags.clear(); paint(); } }),
    vscode.commands.registerCommand("ownvim.go.autotestToggle", async () => {
      const c = vscode.workspace.getConfiguration("ownvim.go");
      await c.update("autotest", !on(), vscode.ConfigurationTarget.Global);
      vscode.window.setStatusBarMessage(on() ? "тесты в фоне: вкл" : "тесты в фоне: выкл", 3000);
    }),
    vscode.commands.registerCommand("ownvim.go.autotestShow", async () => {
      const ed = vscode.window.activeTextEditor;
      const dir = ed?.document.languageId === "go" ? path.dirname(ed.document.uri.fsPath) : lastDir;
      const r = results.get(dir);
      if (!r) return dir && test(dir);
      const where = new Map<string, [string, number]>();
      for (const f of fs.readdirSync(dir).filter((x) => x.endsWith("_test.go"))) {
        fs.readFileSync(path.join(dir, f), "utf8").split("\n").forEach((l, i) => {
          const m = l.match(/^func (\w+)\(/);
          if (m) where.set(m[1], [path.join(dir, f), i]);
        });
      }
      const items = [
        { label: "$(refresh) перезапустить пакет", t: "" },
        ...r.tests.filter((t) => !t.skip).map((t) => ({ label: `${t.pass ? "$(pass)" : "$(error)"} ${t.name}`, description: r.fails.filter((f) => f.test.split("/")[0] === t.name).map((f) => f.msg).join(" · "), t: t.name })),
      ];
      const pick = await vscode.window.showQuickPick(items, { title: `go test ${vscode.workspace.asRelativePath(dir)}: ✓ ${r.passed} ✗ ${r.failed}` });
      if (!pick) return;
      if (!pick.t) return test(dir);
      const w = where.get(pick.t);
      if (!w) return;
      const e = await vscode.window.showTextDocument(vscode.Uri.file(w[0]));
      e.selection = new vscode.Selection(w[1], 0, w[1], 0);
      e.revealRange(new vscode.Range(w[1], 0, w[1], 0), vscode.TextEditorRevealType.InCenter);
    }),
    { dispose: () => { for (const p of running.values()) p.kill(); for (const t of timers.values()) clearTimeout(t); } },
  );
}
