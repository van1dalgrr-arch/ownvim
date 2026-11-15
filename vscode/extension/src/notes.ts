// Заметки о неудобствах (lua/own/tools/notes.lua) — общий файл с nvim: ~/.local/share/ownvim/own-notes.json.
//   пробел ? — «вот тут неудобно», записывается с местом (проект, файл, строка, выделение, редактор «vscode»).
//   пробел N — список: enter — к месту, ✓ — решено (убрать), кнопка сверху — всё в буфер обмена (markdown).
// Скриншот кода (lua/own/tools/shot.lua): пробел P — выделенное или функция под курсором → PNG (freeze) в окне
//   с тенью, в буфер обмена (⌘V в Telegram) и в ~/Pictures/code.
import * as fs from "fs";
import * as os from "os";
import * as path from "path";
import * as vscode from "vscode";
import { data, root, run } from "./core";

const file = path.join(data, "own-notes.json");
type Note = { time: string; project: string; file: string; line: number; col: number; mode: string; ft: string; text: string; selection?: string; last_cmd?: string };

function read(): Note[] {
  try { const v = JSON.parse(fs.readFileSync(file, "utf8")); return Array.isArray(v) ? v : []; } catch { return []; }
}
function write(list: Note[]) {
  fs.mkdirSync(path.dirname(file), { recursive: true });
  fs.writeFileSync(file, JSON.stringify(list));
}
const pad = (n: number) => String(n).padStart(2, "0");
const stamp = (d = new Date()) => `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())} ${pad(d.getHours())}:${pad(d.getMinutes())}`;
const home = (p: string) => p.replace(os.homedir(), "~");

export function markdown(list: Note[]) {
  const out = ["# Неудобства ownvim", ""];
  for (const n of list) {
    const where = n.file ? ` — \`${home(n.file)}:${n.line}\`` : "";
    out.push(`- **${n.text}** · ${n.project || "?"} · режим ${n.mode || "?"} · ${n.time || ""}${where}`);
    if (n.selection) out.push("  выделено: `" + n.selection.replace(/\n/g, "⏎") + "`");
  }
  return out.join("\n");
}

async function add() {
  const ed = vscode.window.activeTextEditor;
  const doc = ed?.document;
  const n: Note = {
    time: stamp(), project: path.basename(root()), file: doc && !doc.isUntitled ? doc.uri.fsPath : "",
    line: (ed?.selection.active.line ?? 0) + 1, col: (ed?.selection.active.character ?? 0) + 1,
    mode: ed && !ed.selection.isEmpty ? "v" : "vscode", ft: doc?.languageId || "", text: "",
  };
  if (ed && !ed.selection.isEmpty) n.selection = doc!.getText(ed.selection).slice(0, 500);
  const where = n.file ? ` · ${path.basename(n.file)}:${n.line}` : "";
  const text = await vscode.window.showInputBox({ title: "Что неудобно?" + where, placeHolder: "записывается вместе с местом — потом разберём" });
  if (!text?.trim()) return;
  n.text = text.trim();
  const list = read();
  list.push(n);
  write(list);
  vscode.window.setStatusBarMessage(`записал — заметок: ${list.length} (пробел N — список)`, 4000);
}

async function list() {
  const all = read();
  if (!all.length) return vscode.window.showInformationMessage("заметок нет — пробел ? записать неудобство");
  const done = { iconPath: new vscode.ThemeIcon("check"), tooltip: "решено — убрать" };
  const copy = { iconPath: new vscode.ThemeIcon("copy"), tooltip: "всё в буфер обмена (markdown)" };
  type Item = vscode.QuickPickItem & { i: number };
  const qp = vscode.window.createQuickPick<Item>();
  const fill = () => {
    const l = read();
    qp.title = `Неудобства · ${l.length}`;
    qp.items = l.map((n, i) => ({
      label: n.text, description: `${n.project || ""}${n.file ? " · " + path.basename(n.file) + ":" + n.line : ""}`,
      detail: `${(n.time || "").slice(5)}${n.selection ? " · выделено: " + n.selection.replace(/\n/g, "⏎").slice(0, 80) : ""}`,
      buttons: [done], i,
    })).reverse();
  };
  qp.buttons = [copy];
  fill();
  qp.onDidTriggerButton(async () => { await vscode.env.clipboard.writeText(markdown(read())); vscode.window.setStatusBarMessage("все заметки в буфере обмена", 3000); });
  qp.onDidTriggerItemButton((e) => {
    const l = read();
    l.splice(e.item.i, 1);
    write(l);
    if (!l.length) return qp.hide();
    fill();
  });
  qp.onDidAccept(async () => {
    const it = qp.selectedItems[0];
    qp.hide();
    const n = it && read()[it.i];
    if (!n?.file || !fs.existsSync(n.file)) return;
    const ed = await vscode.window.showTextDocument(vscode.Uri.file(n.file));
    const p = new vscode.Position(Math.max(n.line - 1, 0), Math.max(n.col - 1, 0));
    ed.selection = new vscode.Selection(p, p);
    ed.revealRange(new vscode.Range(p, p), vscode.TextEditorRevealType.InCenter);
  });
  qp.onDidHide(() => qp.dispose());
  qp.show();
}

// ── скриншот кода ────────────────────────────────────────────────────────────

async function shot() {
  const ed = vscode.window.activeTextEditor;
  if (!ed) return;
  const doc = ed.document;
  let l1 = ed.selection.start.line + 1, l2 = ed.selection.end.line + 1;
  if (ed.selection.isEmpty) {
    // функция под курсором — по символам языкового сервера
    const syms = await vscode.commands.executeCommand<vscode.DocumentSymbol[]>("vscode.executeDocumentSymbolProvider", doc.uri).then((x) => x || [], () => []);
    const kinds = [vscode.SymbolKind.Function, vscode.SymbolKind.Method, vscode.SymbolKind.Constructor, vscode.SymbolKind.Class, vscode.SymbolKind.Struct];
    let best: vscode.DocumentSymbol | undefined;
    const walk = (list: vscode.DocumentSymbol[]) => {
      for (const s of list) {
        if (!s.range.contains(ed.selection.active)) continue;
        if (kinds.includes(s.kind) && (!best || best.range.contains(s.range))) best = s;
        walk(s.children || []);
      }
    };
    walk(syms);
    if (best) { l1 = best.range.start.line + 1; l2 = best.range.end.line + 1; }
    else { l1 = 1; l2 = doc.lineCount; }
  }
  const name = doc.isUntitled ? `code.${doc.languageId}` : path.basename(doc.uri.fsPath);
  const tmp = path.join(os.tmpdir(), "ownvim-shot", name);
  fs.mkdirSync(path.dirname(tmp), { recursive: true });
  fs.writeFileSync(tmp, doc.getText());
  const out = path.join(os.homedir(), "Pictures", "code", `${path.parse(name).name}-${stamp().replace(/[-: ]/g, "")}.png`);
  fs.mkdirSync(path.dirname(out), { recursive: true });
  const light = [vscode.ColorThemeKind.Light, vscode.ColorThemeKind.HighContrastLight].includes(vscode.window.activeColorTheme.kind);
  const r = await run("freeze", [tmp, "--lines", `${l1},${l2}`, "--theme", light ? "tokyonight-day" : "tokyonight-night",
    "--window", "--show-line-numbers", "--font.family", "JetBrainsMono Nerd Font", "--font.size", "14",
    "--border.radius", "10", "--shadow.blur", "20", "--shadow.y", "8", "--padding", "20,28", "--margin", "32", "-o", out]);
  if (r.code !== 0) return vscode.window.showErrorMessage("freeze: " + (r.err || "нужен freeze: brew install charmbracelet/tap/freeze"));
  await run("osascript", ["-e", `set the clipboard to (read (POSIX file "${out}") as «class PNGf»)`]);
  const a = await vscode.window.showInformationMessage(`строки ${l1}–${l2} → картинка в буфере обмена (⌘V) · ${home(out)}`, "Открыть");
  if (a) vscode.env.openExternal(vscode.Uri.file(out));
}

export function activate(ctx: vscode.ExtensionContext) {
  ctx.subscriptions.push(
    vscode.commands.registerCommand("ownvim.notes.add", add),
    vscode.commands.registerCommand("ownvim.notes", list),
    vscode.commands.registerCommand("ownvim.shot", shot),
  );
}
