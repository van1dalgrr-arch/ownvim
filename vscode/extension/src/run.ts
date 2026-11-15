// ▶ у точек входа и тестов — как lua/own/tools/run.lua, для Python и JS / TS (Go — в go/go.ts):
//   Python  if __name__ == "__main__" и def test_* / class Test* (в test_*.py, *_test.py)
//   JS / TS #!/usr/bin/env node и it / test / describe (в *.test.ts, *.spec.js…)
// пробел r x (cmd-enter) — запустить то, в чём курсор; пробел r X — то же под отладчиком.
// Тесты идут через панель тестов VS Code (Python, Vitest, Jest — значок ✓/✗ у теста), main — задачей в терминале
// с .env проекта. Go — в ownvim.go.run, сюда приходит тоже: одна клавиша на все языки.
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { readEnv, root } from "./core";
import * as goExt from "./go/go";

type Kind = "main" | "test";
const JS = ["javascript", "typescript", "javascriptreact", "typescriptreact"];

export const isTestPy = (f: string) => /^test_.*\.py$/.test(path.basename(f)) || /_test\.py$/.test(f);
export const isTestJs = (f: string) => /\.(test|spec)\.[cm]?[jt]sx?$/.test(f);

/** строка → что это и как называется */
export function kindOf(lang: string, line: string, file: string): [Kind, string] | undefined {
  if (lang === "python") {
    if (/^if __name__ == ["']__main__["']\s*:/.test(line)) return ["main", "main"];
    if (!isTestPy(file)) return;
    const m = line.match(/^\s*(?:async\s+)?def (test\w*)\(/) || line.match(/^class (Test\w*)[(:]/);
    if (m) return ["test", m[1]];
  }
  if (JS.includes(lang)) {
    if (/^#!.*node/.test(line)) return ["main", "main"];
    if (!isTestJs(file)) return;
    const m = line.match(/^\s*(?:it|test|describe)[.\w]*\(\s*["'`](.*?)["'`]/);
    if (m) return ["test", m[1]];
  }
}

const top = (lang: string, line: string) => lang === "python" ? /^(def |async def |class |if )/.test(line) : /^\w/.test(line);

/** то, в чём курсор: ближайшая точка входа или тест выше, но не дальше функции верхнего уровня */
export function current(doc: { languageId: string; uri: { fsPath: string }; lineAt(i: number): { text: string } }, row: number): [Kind, string, number] | undefined {
  for (let i = row; i >= 0; i--) {
    const t = doc.lineAt(i).text;
    const k = kindOf(doc.languageId, t, doc.uri.fsPath);
    if (k) return [k[0], k[1], i];
    if (top(doc.languageId, t) && i !== row) return;
  }
}

async function python(file: string): Promise<string> {
  const uri = vscode.Uri.file(file);
  const folder = vscode.workspace.getWorkspaceFolder(uri);
  try {
    const p = await vscode.commands.executeCommand<string>("python.interpreterPath", { workspaceFolder: folder?.uri.fsPath });
    if (p) return p;
  } catch { /* нет расширения Python */ }
  const dir = root(file);
  for (const v of [".venv", "venv", "env"]) if (fs.existsSync(path.join(dir, v, "bin", "python"))) return path.join(dir, v, "bin", "python");
  return "python3";
}

function env(dir: string) {
  return { ...readEnv(path.join(dir, ".env")), ...readEnv(path.join(dir, ".env.local")) };
}

function task(name: string, cmd: string, args: string[], cwd: string) {
  const t = new vscode.Task({ type: "ownvim", run: name }, vscode.TaskScope.Workspace, name, "ownvim",
    new vscode.ProcessExecution(cmd, args, { cwd, env: env(cwd) }));
  t.presentationOptions = { reveal: vscode.TaskRevealKind.Always, panel: vscode.TaskPanelKind.Dedicated, clear: true };
  for (const x of vscode.tasks.taskExecutions) if (x.task.name === name) x.terminate(); // идёт — перезапустить
  return vscode.tasks.executeTask(t);
}

async function testAt(ed: vscode.TextEditor, line: number, debug: boolean) {
  const ch = ed.document.lineAt(line).firstNonWhitespaceCharacterIndex;
  ed.selection = new vscode.Selection(line, ch, line, ch);
  return vscode.commands.executeCommand(debug ? "testing.debugAtCursor" : "testing.runAtCursor");
}

export async function start(debug: boolean, uri?: vscode.Uri, line?: number) {
  let ed = vscode.window.activeTextEditor;
  if (uri && ed?.document.uri.fsPath !== uri.fsPath) ed = await vscode.window.showTextDocument(uri);
  if (!ed) return;
  const doc = ed.document;
  if (doc.languageId === "go") return debug ? goExt.debug(doc.uri) : goExt.run(doc.uri);
  const file = doc.uri.fsPath;
  const isPy = doc.languageId === "python";
  if (!isPy && !JS.includes(doc.languageId)) return vscode.window.showWarningMessage("▶ работает в Go-, Python- и JS/TS-файлах");
  if (doc.isDirty) await doc.save();
  const cur = current(doc, line ?? ed.selection.active.line);
  const isTest = isPy ? isTestPy(file) : isTestJs(file);
  if (cur?.[0] === "test") return testAt(ed, cur[2], debug);
  if (!cur && isTest) return vscode.commands.executeCommand(debug ? "testing.debugCurrentFile" : "testing.runCurrentFile");
  if (!cur && isPy) return vscode.window.showWarningMessage('курсор не в if __name__ == "__main__" и не в тесте');
  const dir = root(file);
  const ws = vscode.workspace.getWorkspaceFolder(doc.uri);
  const name = "▶ " + path.basename(file);
  if (isPy) {
    const py = await python(file);
    if (debug) return vscode.debug.startDebugging(ws, { type: "debugpy", request: "launch", name, program: file, cwd: dir, python: py, env: env(dir), console: "integratedTerminal", justMyCode: false });
    return task(name, py, [file], dir);
  }
  // JS / TS — файл целиком в node (TypeScript node 23.6+ запускает сам)
  if (debug) return vscode.debug.startDebugging(ws, { type: "node", request: "launch", name, program: file, cwd: dir, env: env(dir), console: "integratedTerminal", sourceMaps: true, skipFiles: ["<node_internals>/**"] });
  return task(name, "node", [file], dir);
}

class Lens implements vscode.CodeLensProvider {
  private ev = new vscode.EventEmitter<void>();
  onDidChangeCodeLenses = this.ev.event;
  provideCodeLenses(doc: vscode.TextDocument): vscode.CodeLens[] {
    if (vscode.workspace.getConfiguration("ownvim").get("runMarks") === false) return [];
    const out: vscode.CodeLens[] = [];
    for (let i = 0; i < doc.lineCount; i++) {
      const k = kindOf(doc.languageId, doc.lineAt(i).text, doc.uri.fsPath);
      if (!k) continue;
      const r = new vscode.Range(i, 0, i, 0);
      // у тестов ▶ уже рисует панель тестов VS Code — над ними только main
      if (k[0] === "main") {
        out.push(new vscode.CodeLens(r, { title: "▶ запустить", command: "ownvim.run", arguments: [doc.uri, i] }),
          new vscode.CodeLens(r, { title: "$(debug-alt) отладка", command: "ownvim.debug", arguments: [doc.uri, i] }));
      }
    }
    return out;
  }
}

/** пробел r p — черновик Python: файл во временной папке, сразу запускать */
async function scratch(ctx: vscode.ExtensionContext, lang: "python" | "typescript") {
  const dir = path.join(ctx.globalStorageUri.fsPath, "scratch");
  fs.mkdirSync(dir, { recursive: true });
  const stamp = new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-");
  const file = path.join(dir, `${stamp}.${lang === "python" ? "py" : "ts"}`);
  fs.writeFileSync(file, lang === "python"
    ? 'def main() -> None:\n    print("привет")\n\n\nif __name__ == "__main__":\n    main()\n'
    : '#!/usr/bin/env node\nconsole.log("привет");\n');
  const ed = await vscode.window.showTextDocument(vscode.Uri.file(file));
  ed.selection = new vscode.Selection(1, 4, 1, lang === "python" ? 20 : 4);
}

export function activate(ctx: vscode.ExtensionContext) {
  const sel = [{ language: "python", scheme: "file" }, ...JS.map((language) => ({ language, scheme: "file" }))];
  ctx.subscriptions.push(
    vscode.languages.registerCodeLensProvider(sel, new Lens()),
    vscode.commands.registerCommand("ownvim.run", (uri?: vscode.Uri, line?: number) => start(false, uri instanceof vscode.Uri ? uri : undefined, typeof line === "number" ? line : undefined)),
    vscode.commands.registerCommand("ownvim.debug", (uri?: vscode.Uri, line?: number) => start(true, uri instanceof vscode.Uri ? uri : undefined, typeof line === "number" ? line : undefined)),
    vscode.commands.registerCommand("ownvim.python.scratch", () => scratch(ctx, "python")),
    vscode.commands.registerCommand("ownvim.ts.scratch", () => scratch(ctx, "typescript")),
  );
}
