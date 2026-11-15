// Запрос из файла — в базу проекта (как vim-dadbod в ownvim): выделение или выражение под курсором,
// результат — таблицей в панели справа. cmd-enter / пробел S.
import * as vscode from "vscode";
import * as schema from "./schema";
import { projectRoot, projectUrl, withClient } from "./db";

let panel: vscode.WebviewPanel | undefined;

function statementAt(ed: vscode.TextEditor): string {
  if (!ed.selection.isEmpty) return ed.document.getText(ed.selection);
  const text = ed.document.getText();
  const off = ed.document.offsetAt(ed.selection.active);
  const parts = schema.splitAt(schema.stripComments(text));
  for (const p of parts) {
    // курсор в выражении или сразу после его «;»
    if (off >= p.start && off <= p.start + p.text.length + 1) return text.slice(p.start, p.start + p.text.length);
  }
  return parts.length ? text.slice(parts[parts.length - 1].start) : "";
}

const esc = (v: unknown) => {
  if (v === null || v === undefined) return '<span class="null">NULL</span>';
  const s = v instanceof Date ? v.toISOString() : typeof v === "object" ? JSON.stringify(v) : String(v);
  return s.replace(/&/g, "&amp;").replace(/</g, "&lt;");
};

function html(sql: string, body: string, meta: string) {
  return `<!doctype html><html><head><meta charset="utf-8"><style>
  body{font-family:var(--vscode-editor-font-family);font-size:var(--vscode-editor-font-size);color:var(--vscode-foreground);padding:8px}
  .meta{color:var(--vscode-descriptionForeground);margin:4px 0 10px}
  pre{color:var(--vscode-descriptionForeground);white-space:pre-wrap;margin:0 0 6px;max-height:6em;overflow:auto}
  table{border-collapse:collapse}
  th,td{border:1px solid var(--vscode-panel-border);padding:3px 8px;text-align:left;white-space:nowrap;max-width:420px;overflow:hidden;text-overflow:ellipsis}
  th{position:sticky;top:0;background:var(--vscode-editorWidget-background);color:var(--vscode-textLink-foreground)}
  tr:nth-child(even) td{background:var(--vscode-list-hoverBackground)}
  .null{color:var(--vscode-disabledForeground);font-style:italic}
  .err{color:var(--vscode-errorForeground);white-space:pre-wrap}
  </style></head><body><pre>${esc(sql.trim())}</pre><div class="meta">${meta}</div>${body}</body></html>`;
}

export async function run() {
  const ed = vscode.window.activeTextEditor;
  if (!ed) return;
  const sql = statementAt(ed).trim();
  if (!sql) return;
  const u = projectUrl(projectRoot(ed.document.uri.fsPath));
  if (!u) return vscode.window.showWarningMessage("Не нашёл базу проекта: DATABASE_URL в .env, postgres в compose или ownvim.database.url");
  if (!panel) {
    panel = vscode.window.createWebviewPanel("ownvim.sql", "Результат", { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true });
    panel.onDidDispose(() => (panel = undefined));
  }
  panel.title = "⏳ " + u.name;
  const t0 = Date.now();
  try {
    const r = await withClient(u.url, (c) => c.query({ text: sql, rowMode: "array" }));
    const res = Array.isArray(r) ? r[r.length - 1] : r;
    const ms = Date.now() - t0;
    const fields: string[] = (res.fields || []).map((f: any) => f.name);
    const rows: unknown[][] = res.rows || [];
    const body = fields.length
      ? `<table><tr>${fields.map((f) => `<th>${esc(f)}</th>`).join("")}</tr>${rows.slice(0, 2000).map((row) => `<tr>${row.map((v) => `<td>${esc(v)}</td>`).join("")}</tr>`).join("")}</table>`
      : "";
    const meta = `${u.name} · ${res.command || ""} · ${fields.length ? rows.length + " строк" : (res.rowCount ?? 0) + " затронуто"} · ${ms} мс${rows.length > 2000 ? " · показаны первые 2000" : ""}`;
    panel.webview.html = html(sql, body, meta);
    panel.title = "▦ " + u.name;
  } catch (e: any) {
    panel.webview.html = html(sql, `<div class="err">${esc(e?.message || e)}${e?.position ? `\n\nпозиция ${e.position}` : ""}</div>`, u.name);
    panel.title = "✗ " + u.name;
  }
}

/** Какая база у проекта — показать и скопировать */
export async function info() {
  const u = projectUrl();
  if (!u) return vscode.window.showWarningMessage("База проекта не найдена: DATABASE_URL в .env, postgres в compose или ownvim.database.url");
  const hidden = u.url.replace(/:[^:@/]*@/, ":•••@");
  const pick = await vscode.window.showInformationMessage(`База проекта: ${hidden}`, "Скопировать URL");
  if (pick) vscode.env.clipboard.writeText(u.url);
}
