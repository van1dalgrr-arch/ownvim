// Задачи и свои команды — из тех же settings.jsonc, что у ownvim (один список на nvim и VS Code):
//   "tasks": { "list": [ { "name", "cmd", "when": ["go.mod"], "ft": ["go"], "cwd": "root" | "file", "env": ".env" } ] }
//     в cmd: ${root} ${file} ${file_dir} ${image} ${python}, ${input:Подсказка} — спросить при запуске (в терминале задачи)
//     пробел r t / alt-t — в общем списке задач VS Code, раздел «ownvim».
//   "commands": { "Имя": { "run": "python3 extensions/x.py", "input": "selection|file|line|word|none",
//                          "output": "replace|insert|window|notify|none" } } — пробел x x; скрипт: stdin → stdout,
//     контекст — OWN_FILE, OWN_LINE, OWN_ROOT, OWN_FILETYPE, OWN_WORD.
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { readEnv, repo, root, run, settings } from "./core";

const q = (s: string) => "'" + s.replace(/'/g, `'\\''`) + "'";

function python(dir: string) {
  for (const v of [".venv", "venv", "env"]) if (fs.existsSync(path.join(dir, v, "bin", "python"))) return path.join(dir, v, "bin", "python");
  return "python3";
}

/** cmd ownvim → строка для shell: переменные подставлены, ${input:…} — read в терминале задачи */
export function expand(cmd: string, vars: Record<string, string>): string {
  const asks: string[] = [];
  cmd = cmd.replace(/\$\{input:([^}]+)\}/g, (_, label: string) => {
    let i = asks.indexOf(label);
    if (i < 0) { asks.push(label); i = asks.length - 1; }
    return `"$OWN_IN_${i}"`;
  });
  cmd = cmd.replace(/\$\{(\w+)\}/g, (all, k: string) => (k in vars ? q(vars[k]) : all));
  const reads = asks.map((l, i) => `printf '%s: ' ${q(l)}; read -r OWN_IN_${i}; `).join("");
  return reads + cmd;
}

const list = (v: any): string[] => (v === undefined ? [] : Array.isArray(v) ? v : [v]);

class Tasks implements vscode.TaskProvider {
  async provideTasks(): Promise<vscode.Task[]> {
    const s = await settings();
    const ed = vscode.window.activeTextEditor;
    const dir = root();
    const file = ed?.document.uri.fsPath || "";
    const vars = {
      root: dir, file, file_dir: file ? path.dirname(file) : dir,
      image: path.basename(dir).toLowerCase().replace(/ /g, "-") + ":dev", python: python(dir),
    };
    const out: vscode.Task[] = [];
    for (const t of (s.tasks?.list || []) as any[]) {
      if (!t?.name || !t?.cmd) continue;
      const ft = list(t.ft);
      if (ft.length && !ft.includes(ed?.document.languageId || "")) continue;
      const when = list(t.when);
      if (when.length && !when.some((f) => fs.existsSync(path.join(dir, f)))) continue;
      const env: Record<string, string> = {};
      for (const f of list(t.env)) Object.assign(env, readEnv(path.join(dir, f)));
      const cwd = t.cwd === "file" ? vars.file_dir : dir;
      const task = new vscode.Task({ type: "ownvim-task", name: t.name }, vscode.TaskScope.Workspace, t.name, "ownvim",
        new vscode.ShellExecution(expand(t.cmd, vars), { cwd, env }));
      task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, panel: vscode.TaskPanelKind.Dedicated, clear: true, focus: /\$\{input:/.test(t.cmd) };
      out.push(task);
    }
    return out;
  }
  resolveTask() { return undefined; }
}

// ── свои команды ─────────────────────────────────────────────────────────────

async function runCommand(name: string, c: any) {
  const ed = vscode.window.activeTextEditor;
  const doc = ed?.document;
  let input = "";
  let range: vscode.Range | undefined;
  const kind = c.input || "none";
  if (ed && doc) {
    if (kind === "file") { range = new vscode.Range(0, 0, doc.lineCount, 0); input = doc.getText(); }
    if (kind === "line") { range = doc.lineAt(ed.selection.active.line).range; input = doc.getText(range); }
    if (kind === "word") { range = doc.getWordRangeAtPosition(ed.selection.active); input = range ? doc.getText(range) : ""; }
    if (kind === "selection") {
      const s = ed.selection;
      range = new vscode.Range(s.start.line, 0, s.end.line, doc.lineAt(s.end.line).text.length);
      input = doc.getText(range);
    }
  }
  if (c.ft && doc && !list(c.ft).includes(doc.languageId)) return vscode.window.showWarningMessage(name + ": не для этого типа файла");
  const dir = root();
  const cmd = String(c.run).replace(/^(\S+)\s+(extensions\/)/, `$1 ${repo}/$2`);
  const env = {
    OWN_FILE: doc?.uri.fsPath || "", OWN_LINE: String((ed?.selection.active.line ?? 0) + 1), OWN_ROOT: dir,
    OWN_FILETYPE: doc?.languageId || "", OWN_WORD: doc && ed ? doc.getText(doc.getWordRangeAtPosition(ed.selection.active)) : "",
  };
  const r = await run("sh", ["-c", cmd], { cwd: dir, input, env, timeout: 60000 });
  if (r.code !== 0) return vscode.window.showErrorMessage(`${name}: ошибка ${r.code}\n${r.err}`);
  const out = r.out.replace(/\n$/, "");
  const o = c.output || "notify";
  if (o === "replace" && ed && range) await ed.edit((b) => b.replace(range!, kind === "file" ? out + "\n" : out));
  else if (o === "insert" && ed) await ed.edit((b) => b.insert(new vscode.Position(ed.selection.active.line + 1, 0), out + "\n"));
  else if (o === "window") {
    const d = await vscode.workspace.openTextDocument({ content: out });
    await vscode.window.showTextDocument(d, { viewColumn: vscode.ViewColumn.Beside, preview: true });
  } else if (o === "notify" && out) vscode.window.showInformationMessage(`${name}: ${out}`);
}

export async function commands() {
  const all = (await settings()).commands || {};
  const names = Object.keys(all).sort();
  if (!names.length) return vscode.window.showInformationMessage('своих команд нет — раздел "commands" в settings.jsonc');
  const pick = await vscode.window.showQuickPick(names.map((n) => ({ label: n, description: all[n].run, detail: `вход: ${all[n].input || "none"} → ${all[n].output || "notify"}` })), { title: "Мои команды" });
  if (pick) await runCommand(pick.label, all[pick.label]);
}

export function activate(ctx: vscode.ExtensionContext) {
  ctx.subscriptions.push(
    vscode.tasks.registerTaskProvider("ownvim-task", new Tasks()),
    vscode.commands.registerCommand("ownvim.commands", commands),
    vscode.commands.registerCommand("ownvim.settings", () => vscode.window.showTextDocument(vscode.Uri.file(path.join(repo, "settings.jsonc")))),
  );
}
