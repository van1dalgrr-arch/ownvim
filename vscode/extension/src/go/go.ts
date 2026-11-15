// Go как в GoLand, сверх расширения Go (оно даёт ▶ у тестов, генерацию, покрытие):
//   ▶ запустить / отладка над func main — пробел r x / r X
//   «реализует: io.Reader, fmt.Stringer» над типом (через gopls)
//   пробел r g — черновик: модуль во временной папке, main.go — сразу запускать
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import * as json2struct from "./json2struct";

const cfg = () => vscode.workspace.getConfiguration("ownvim.go");

function mainLine(doc: vscode.TextDocument): number {
  const text = doc.getText();
  if (!/^package\s+main\b/m.test(text)) return -1;
  for (let i = 0; i < doc.lineCount; i++) if (/^func\s+main\s*\(\s*\)/.test(doc.lineAt(i).text)) return i;
  return -1;
}

export function run(uri?: vscode.Uri) {
  const doc = uri ? vscode.workspace.textDocuments.find((d) => d.uri.fsPath === uri.fsPath) : vscode.window.activeTextEditor?.document;
  if (!doc) return;
  if (doc.uri.fsPath.endsWith("_test.go")) return vscode.commands.executeCommand("go.test.cursor");
  if (mainLine(doc) < 0) return vscode.commands.executeCommand("go.test.cursor");
  const dir = path.dirname(doc.uri.fsPath);
  const exec = new vscode.ShellExecution("go run .", { cwd: dir, env: envFile(dir) });
  const task = new vscode.Task({ type: "ownvim", run: dir }, vscode.TaskScope.Workspace, "▶ " + path.basename(dir), "go", exec, "$go");
  task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, panel: vscode.TaskPanelKind.Dedicated, clear: true };
  // идёт — перезапустить
  for (const t of vscode.tasks.taskExecutions) if (t.task.name === task.name) t.terminate();
  vscode.tasks.executeTask(task);
}

export function debug(uri?: vscode.Uri) {
  const doc = uri ? vscode.workspace.textDocuments.find((d) => d.uri.fsPath === uri.fsPath) : vscode.window.activeTextEditor?.document;
  if (!doc) return;
  if (mainLine(doc) < 0) return vscode.commands.executeCommand("go.debug.cursor");
  const dir = path.dirname(doc.uri.fsPath);
  const ws = vscode.workspace.getWorkspaceFolder(doc.uri);
  const env = envFile(dir);
  vscode.debug.startDebugging(ws, { type: "go", request: "launch", name: "▶ " + path.basename(dir), mode: "debug", program: dir, env });
}

/** .env рядом с go.mod — в окружение запуска, как задачи ownvim */
function envFile(dir: string): Record<string, string> {
  let d = dir;
  for (let i = 0; i < 6; i++) {
    if (fs.existsSync(path.join(d, "go.mod"))) break;
    d = path.dirname(d);
  }
  const out: Record<string, string> = {};
  for (const p of [path.join(d, ".env"), path.join(dir, ".env")]) {
    try {
      for (const l of fs.readFileSync(p, "utf8").split("\n")) {
        const m = l.match(/^\s*(?:export\s+)?(\w+)\s*=\s*(.*?)\s*$/);
        if (m) out[m[1]] = m[2].replace(/^(['"])(.*)\1$/, "$2");
      }
    } catch { /* нет .env */ }
  }
  return out;
}

class Lens implements vscode.CodeLensProvider {
  provideCodeLenses(doc: vscode.TextDocument): vscode.CodeLens[] {
    const out: vscode.CodeLens[] = [];
    const m = mainLine(doc);
    if (m >= 0 && cfg().get("runMarks") !== false) {
      const r = new vscode.Range(m, 0, m, 0);
      out.push(new vscode.CodeLens(r, { title: "▶ запустить", command: "ownvim.go.run", arguments: [doc.uri] }),
        new vscode.CodeLens(r, { title: "$(debug-alt) отладка", command: "ownvim.go.debug", arguments: [doc.uri] }));
    }
    if (cfg().get("implements") !== false) {
      for (let i = 0; i < doc.lineCount; i++) {
        const t = doc.lineAt(i).text.match(/^type\s+(\w+)(\[[^\]]*\])?\s+(struct|\w)/);
        if (t && !/\binterface\b/.test(doc.lineAt(i).text)) {
          const lens = new vscode.CodeLens(new vscode.Range(i, 0, i, 0)) as vscode.CodeLens & { pos?: vscode.Position; uri?: vscode.Uri };
          lens.pos = new vscode.Position(i, 5);
          lens.uri = doc.uri;
          out.push(lens);
        }
      }
    }
    return out;
  }

  async resolveCodeLens(lens: vscode.CodeLens & { pos?: vscode.Position; uri?: vscode.Uri }): Promise<vscode.CodeLens> {
    if (!lens.pos || !lens.uri) return lens;
    const locs = await vscode.commands.executeCommand<(vscode.Location | vscode.LocationLink)[]>("vscode.executeImplementationProvider", lens.uri, lens.pos).then((x) => x || [], () => []);
    const names: string[] = [];
    const targets: vscode.Location[] = [];
    for (const l of locs) {
      const loc = "targetUri" in l ? new vscode.Location(l.targetUri, l.targetSelectionRange || l.targetRange) : l;
      if (loc.uri.fsPath === lens.uri.fsPath && loc.range.start.line === lens.pos.line) continue;
      try {
        const doc = await vscode.workspace.openTextDocument(loc.uri);
        const line = doc.lineAt(loc.range.start.line).text;
        const name = line.match(/^\s*(?:type\s+)?(\w+)/)?.[1];
        if (!name) continue;
        const pkg = doc.getText().match(/^package\s+(\w+)/m)?.[1];
        const own = path.dirname(loc.uri.fsPath) === path.dirname(lens.uri.fsPath);
        names.push(own || !pkg ? name : `${pkg}.${name}`);
        targets.push(loc);
      } catch { /* файл не открылся */ }
    }
    lens.command = names.length
      ? { title: "реализует: " + [...new Set(names)].slice(0, 5).join(", "), command: "editor.action.showReferences", arguments: [lens.uri, lens.pos, targets] }
      : { title: "", command: "" };
    return lens;
  }
}

export async function scratch(ctx: vscode.ExtensionContext) {
  const dir = path.join(ctx.globalStorageUri.fsPath, "go-scratch", new Date().toISOString().slice(0, 19).replace(/[:T]/g, "-"));
  fs.mkdirSync(dir, { recursive: true });
  fs.writeFileSync(path.join(dir, "go.mod"), "module scratch\n\ngo 1.23\n");
  const main = path.join(dir, "main.go");
  fs.writeFileSync(main, 'package main\n\nimport "fmt"\n\nfunc main() {\n\tfmt.Println("привет")\n}\n');
  const ed = await vscode.window.showTextDocument(vscode.Uri.file(main));
  ed.selection = new vscode.Selection(5, 1, 5, 1);
}

export function activate(ctx: vscode.ExtensionContext) {
  json2struct.activate(ctx);
  ctx.subscriptions.push(
    vscode.languages.registerCodeLensProvider({ language: "go", scheme: "file" }, new Lens()),
    vscode.commands.registerCommand("ownvim.go.run", run),
    vscode.commands.registerCommand("ownvim.go.debug", debug),
    vscode.commands.registerCommand("ownvim.go.scratch", () => scratch(ctx)),
  );
}
