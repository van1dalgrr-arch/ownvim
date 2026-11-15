// ctrl-a / ctrl-x как dial.nvim в ownvim: слово под курсором — по кругу (true → false, := → =, GET → POST…),
// иначе число под курсором или правее на строке — ±1 (с повтором: 5 ctrl-a → +5 не нужен, хватает и так).
import * as vscode from "vscode";

const COMMON = [["true", "false"], ["True", "False"], ["yes", "no"], ["on", "off"], ["and", "or"], ["&&", "||"],
  ["==", "!="], ["<", ">"], ["<=", ">="], ["first", "last"], ["min", "max"], ["left", "right"], ["up", "down"],
  ["enable", "disable"], ["enabled", "disabled"], ["public", "private"], ["width", "height"]];

// как в ownvim (defaults.jsonc → dial)
const BY_LANG: Record<string, string[][]> = {
  go: [[":=", "="], ["var", "const"], ["Error", "Fatal"], ["Errorf", "Fatalf"], ["Println", "Printf"], ["nil", "err"],
    ["http.MethodGet", "http.MethodPost", "http.MethodPut", "http.MethodPatch", "http.MethodDelete"],
    ["StatusOK", "StatusCreated", "StatusNoContent", "StatusBadRequest", "StatusNotFound", "StatusInternalServerError"]],
  javascript: [["const", "let"], ["===", "!=="], ["log", "warn", "error"], ["GET", "POST", "PUT", "PATCH", "DELETE"], ["async", "sync"]],
  typescript: [["const", "let"], ["===", "!=="], ["log", "warn", "error"], ["GET", "POST", "PUT", "PATCH", "DELETE"], ["async", "sync"]],
  python: [["True", "False"], ["==", "!="], ["debug", "info", "warning", "error", "critical"], ["is", "is not"], ["None", "0"]],
  sql: [["ASC", "DESC"], ["asc", "desc"], ["AND", "OR"], ["INNER", "LEFT", "RIGHT", "FULL"], ["up", "down"], ["NULL", "NOT NULL"]],
  http: [["GET", "POST", "PUT", "PATCH", "DELETE"]],
};

export async function dial(step: 1 | -1) {
  const ed = vscode.window.activeTextEditor;
  if (!ed) return;
  const pos = ed.selection.active;
  const line = ed.document.lineAt(pos.line).text;
  const groups = [...(BY_LANG[ed.document.languageId] || []), ...COMMON];

  // слово / оператор под курсором — самое длинное совпадение, накрывающее курсор
  let best: { s: number; e: number; next: string } | undefined;
  for (const g of groups) for (let i = 0; i < g.length; i++) {
    const w = g[i];
    for (let s = line.indexOf(w); s >= 0; s = line.indexOf(w, s + 1)) {
      const e = s + w.length;
      if (pos.character < s || pos.character >= e) continue;
      const word = /^\w/.test(w);
      if (word && (/\w/.test(line[s - 1] || "") || /\w/.test(line[e] || ""))) continue;
      if (!word && (/[=<>!&|:]/.test(line[s - 1] || "") || /[=<>!&|]/.test(line[e] || ""))) continue;
      if (!best || e - s > best.e - best.s) best = { s, e, next: g[(i + step + g.length) % g.length] };
    }
  }
  if (best) {
    const b = best;
    await ed.edit((x) => x.replace(new vscode.Range(pos.line, b.s, pos.line, b.e), b.next));
    ed.selection = new vscode.Selection(pos.line, b.s, pos.line, b.s);
    return;
  }

  // число под курсором или правее (как ctrl-a в Vim)
  for (const m of line.matchAll(/-?\d+/g)) {
    const s = m.index!, e = s + m[0].length;
    if (e <= pos.character) continue;
    const n = String(Number(m[0]) + step);
    await ed.edit((x) => x.replace(new vscode.Range(pos.line, s, pos.line, e), n));
    const c = s + n.length - 1;
    ed.selection = new vscode.Selection(pos.line, c, pos.line, c);
    return;
  }
}

export function activate(ctx: vscode.ExtensionContext) {
  ctx.subscriptions.push(
    vscode.commands.registerCommand("ownvim.dial.inc", () => dial(1)),
    vscode.commands.registerCommand("ownvim.dial.dec", () => dial(-1)),
  );
}
