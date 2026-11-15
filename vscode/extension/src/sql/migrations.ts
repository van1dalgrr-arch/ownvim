// Миграции: golang-migrate (000001_name.up.sql + .down.sql) и goose (один файл с -- +goose Up / Down)
// (как lua/own/sql/migrations.lua):
//   новая — пара файлов с номером по порядку, up — заготовка по имени (create_orders, add_phone_to_users)
//   down  — пишется сам при сохранении up, пока его не правили руками
//   статус — в первой строке миграции: ✓ применена / ○ ждёт / ✗ dirty (версия — прямо из базы проекта)
//   up / down / redo — migrate или goose с базой проекта, в терминале
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import * as schema from "./schema";
import { projectRoot, projectUrl, withClient } from "./db";

const CANDIDATES = ["migrations", "db/migrations", "database/migrations", "sql/migrations", "internal/db/migrations",
  "internal/migrations", "internal/database/migrations", "schema/migrations", "migrate", "db/migrate"];

const cfg = () => vscode.workspace.getConfiguration("ownvim.sql");
const hasSql = (d: string) => { try { return fs.readdirSync(d).some((f) => f.endsWith(".sql")); } catch { return false; } };

export const isMigration = (file: string) => /[\\/]\d+_[^\\/]*\.sql$/.test(file);

/** Папка миграций проекта (или та, где лежит открытый .sql с номером в имени) */
export function dir(file = vscode.window.activeTextEditor?.document.uri.fsPath): string | undefined {
  if (file && isMigration(file)) return path.dirname(file);
  const root = projectRoot(file);
  if (!root) return undefined;
  const own = cfg().get<string>("migrations");
  if (own) {
    const d = path.isAbsolute(own) ? own : path.join(root, own);
    if (fs.existsSync(d)) return d;
  }
  for (const c of CANDIDATES) {
    const d = path.join(root, c);
    if (hasSql(d)) return d;
  }
  return findMigrations(root, 0);
}

function findMigrations(d: string, depth: number): string | undefined {
  if (depth > 4) return undefined;
  let ents: fs.Dirent[];
  try { ents = fs.readdirSync(d, { withFileTypes: true }); } catch { return undefined; }
  for (const e of ents) {
    if (!e.isDirectory() || e.name.startsWith(".") || e.name === "node_modules" || e.name === "vendor") continue;
    const p = path.join(d, e.name);
    if (e.name === "migrations" && hasSql(p)) return p;
    const deeper = findMigrations(p, depth + 1);
    if (deeper) return deeper;
  }
  return undefined;
}

/** Чем пользуется проект: goose или migrate */
export function tool(d: string): "goose" | "migrate" {
  const own = cfg().get<string>("tool");
  if (own === "goose" || own === "migrate") return own;
  for (const f of schema.files(d)) {
    if (f.endsWith(".up.sql")) return "migrate";
    try { if (fs.readFileSync(path.join(d, f), "utf8").slice(0, 400).includes("+goose")) return "goose"; } catch { /* нет файла */ }
  }
  return "migrate";
}

/** 000003_create_x.up.sql → [3, "create_x"] */
export function parseName(file: string): [number, string] | undefined {
  const m = path.basename(file).match(/^(\d+)_(.*?)\./);
  return m ? [Number(m[1]), m[2]] : undefined;
}

/** up ↔ down (goose — undefined, всё в одном файле) */
export function pair(file: string): string | undefined {
  if (file.endsWith(".up.sql")) return file.replace(/\.up\.sql$/, ".down.sql");
  if (file.endsWith(".down.sql")) return file.replace(/\.down\.sql$/, ".up.sql");
  return undefined;
}

// ───── заготовки ─────

function idColumn(d: string): string {
  let uuid = 0, other = 0;
  for (const t of schema.load(d).tables.values()) {
    const f = t.cols[0];
    if (f?.name === "id") { if (f.type.includes("uuid")) uuid++; else other++; }
  }
  return uuid > other ? "id uuid PRIMARY KEY DEFAULT gen_random_uuid()" : "id bigint GENERATED ALWAYS AS IDENTITY PRIMARY KEY";
}

/** Заготовка up по имени: строки и (с 0) строка, где встать курсором */
function template(d: string, name: string): [string[], number] {
  const t = name.match(/^create_(.*?)_table$/)?.[1] || name.match(/^create_(.+)$/)?.[1];
  if (t) return [[`CREATE TABLE IF NOT EXISTS ${t} (`, "    " + idColumn(d) + ",", "    ",
    "    created_at timestamptz NOT NULL DEFAULT now(),", "    updated_at timestamptz NOT NULL DEFAULT now()", ");"], 2];
  const add = name.match(/^add_(.*?)_to_(.+)$/);
  if (add) return [[`ALTER TABLE ${add[2]} ADD COLUMN ${add[1]} ;`], 0];
  return [[""], 0];
}

function nextPrefix(d: string): string {
  let width = 6, max = 0, stamp = false;
  for (const f of fs.readdirSync(d)) {
    const num = f.match(/^(\d+)_/)?.[1];
    if (!num || !f.endsWith(".sql")) continue;
    if (num.length >= 12) stamp = true;
    width = num.length;
    max = Math.max(max, Number(num));
  }
  if (stamp) {
    const n = new Date(), p = (x: number) => String(x).padStart(2, "0");
    return `${n.getFullYear()}${p(n.getMonth() + 1)}${p(n.getDate())}${p(n.getHours())}${p(n.getMinutes())}${p(n.getSeconds())}`;
  }
  return String(max + 1).padStart(width, "0");
}

export async function create(name?: string) {
  let d = dir();
  if (!d) {
    const root = projectRoot(vscode.window.activeTextEditor?.document.uri.fsPath);
    if (!root) return vscode.window.showWarningMessage("Открой папку проекта — миграции лягут в migrations/");
    d = path.join(root, "migrations");
    fs.mkdirSync(d, { recursive: true });
  }
  name ??= await vscode.window.showInputBox({ prompt: "Новая миграция", placeHolder: "create_orders, add_phone_to_users" });
  if (!name?.trim()) return;
  const n = name.trim().toLowerCase().replace(/[\s-]+/g, "_").replace(/[^\w]/g, "");
  const prefix = nextPrefix(d);
  let [lines, row] = template(d, n);
  let up: string;
  if (tool(d) === "goose") {
    up = path.join(d, `${prefix}_${n}.sql`);
    fs.writeFileSync(up, ["-- +goose Up", ...lines, "", "-- +goose Down", ""].join("\n"));
    row++;
  } else {
    up = path.join(d, `${prefix}_${n}.up.sql`);
    fs.writeFileSync(up, lines.join("\n") + "\n");
    fs.writeFileSync(pair(up)!, "");
  }
  const doc = await vscode.workspace.openTextDocument(up);
  if (pair(up)) {
    writeDown(doc);
    await vscode.window.showTextDocument(vscode.Uri.file(pair(up)!), { viewColumn: vscode.ViewColumn.Beside, preserveFocus: true, preview: false });
  }
  const ed = await vscode.window.showTextDocument(doc, { viewColumn: vscode.ViewColumn.One, preview: false });
  const line = doc.lineAt(row).text;
  const col = Math.max(0, line.length - (line.endsWith(" ;") ? 1 : 0));
  ed.selection = new vscode.Selection(row, col, row, col);
}

// ───── down по up ─────

export function downFor(text: string): string[] {
  const out: string[] = [];
  const sts = schema.statements(schema.upPart(text));
  for (let i = sts.length - 1; i >= 0; i--) {
    const p = sts[i];
    switch (p.kind) {
      case "create_table": out.push(`DROP TABLE IF EXISTS ${p.table};`); break;
      case "create_enum": out.push(`DROP TYPE IF EXISTS ${p.name};`); break;
      case "create_index": if (p.name) out.push(`DROP INDEX ${p.concurrently ? "CONCURRENTLY " : ""}IF EXISTS ${p.name};`); break;
      case "create_extension": out.push(`DROP EXTENSION IF EXISTS ${p.name};`); break;
      case "create_function": out.push(`DROP FUNCTION IF EXISTS ${p.name};`); break;
      case "create_trigger": out.push(`DROP TRIGGER IF EXISTS ${p.name} ON ${p.table};`); break;
      case "create_view": out.push(`DROP ${p.materialized ? "MATERIALIZED " : ""}VIEW IF EXISTS ${p.name};`); break;
      case "alter_table": {
        let tbl = p.table;
        for (let j = p.actions.length - 1; j >= 0; j--) {
          const a = p.actions[j];
          if (a.op === "add_column" && a.col) out.push(`ALTER TABLE ${tbl} DROP COLUMN IF EXISTS ${a.col.name};`);
          else if (a.op === "rename_column") out.push(`ALTER TABLE ${tbl} RENAME COLUMN ${a.to} TO ${a.from};`);
          else if (a.op === "rename_table") { out.push(`ALTER TABLE ${a.to} RENAME TO ${tbl};`); tbl = a.to; }
          else if (a.op === "add_constraint" && a.name) out.push(`ALTER TABLE ${tbl} DROP CONSTRAINT IF EXISTS ${a.name};`);
          else out.push(`-- откатить вручную: ALTER TABLE ${tbl} ${a.text.replace(/\s+/g, " ")}`);
        }
        break;
      }
      default:
        if (!(p.kind === "other" && /^\s*insert/i.test(p.source))) out.push("-- откатить вручную: " + p.source.replace(/\s+/g, " ").slice(0, 80));
    }
  }
  return out;
}

const generated = new Map<string, string>(); // путь down → что мы туда написали (правили руками — не трогаем)
const blank = (s: string) => s.trim() === "";

/** После сохранения up: down пуст или ещё наш — переписать по up */
export async function writeDown(doc: vscode.TextDocument) {
  if (cfg().get<boolean>("autoDown") === false) return;
  const file = doc.uri.fsPath;
  const text = doc.getText();
  const down = downFor(text);
  if (!down.length) return;
  const body = down.join("\n") + "\n";

  if (!file.endsWith(".up.sql")) {
    // goose: часть Down внутри того же файла
    if (!text.includes("+goose")) return;
    const lines = text.split("\n");
    let at = -1;
    lines.forEach((l, i) => { if (/^--\s*\+goose\s+down/i.test(l)) at = i; });
    if (at < 0) return;
    const rest = lines.slice(at + 1).join("\n");
    const key = file + "#down";
    if (!(blank(rest) || rest === generated.get(key)) || rest === body) return;
    const ed = new vscode.WorkspaceEdit();
    ed.replace(doc.uri, new vscode.Range(at + 1, 0, doc.lineCount, 0), body);
    generated.set(key, body);
    await vscode.workspace.applyEdit(ed);
    await doc.save();
    return;
  }

  const p = pair(file)!;
  const open = vscode.workspace.textDocuments.find((d) => d.uri.fsPath === p);
  const cur = open ? open.getText() : fs.existsSync(p) ? fs.readFileSync(p, "utf8") : "";
  if (!(blank(cur) || cur === generated.get(p)) || cur === body) return;
  generated.set(p, body);
  if (open) {
    const ed = new vscode.WorkspaceEdit();
    ed.replace(open.uri, new vscode.Range(0, 0, open.lineCount, 0), body);
    await vscode.workspace.applyEdit(ed);
    await open.save();
  } else fs.writeFileSync(p, body);
}

// ───── статус ─────

interface Status { version?: number; dirty?: boolean; err?: string; at: number }
const status = new Map<string, Status>();
const changed = new vscode.EventEmitter<string>();
export const onStatus = changed.event;

/** Версия базы прямо из таблицы миграций (не чаще раза в 5 с на папку, force — сразу) */
export async function refresh(d: string, force = false): Promise<Status> {
  const st = status.get(d);
  if (!force && st && Date.now() - st.at < 5000) return st;
  const u = projectUrl(projectRoot(path.join(d, "x")));
  if (!u) return { err: "нет базы проекта", at: Date.now() };
  status.set(d, { ...(st || {}), at: Date.now() });
  let s: Status;
  try {
    s = await withClient(u.url, async (c) => {
      if (tool(d) === "goose") {
        const r = await c.query(`SELECT version_id FROM goose_db_version WHERE is_applied ORDER BY id DESC LIMIT 1`).catch(() => undefined);
        return { version: Number(r?.rows[0]?.version_id ?? 0), at: Date.now() };
      }
      const r = await c.query(`SELECT version, dirty FROM schema_migrations LIMIT 1`).catch(() => undefined);
      return { version: Number(r?.rows[0]?.version ?? 0), dirty: !!r?.rows[0]?.dirty, at: Date.now() };
    });
  } catch (e: any) {
    s = { err: String(e?.message || e), at: Date.now() };
  }
  status.set(d, s);
  changed.fire(d);
  return s;
}

export function cached(d: string) { return status.get(d); }

/** ✓ / ○ / ✗ для файла миграции по известному статусу */
export function markOf(file: string): { text: string; color: string } | undefined {
  const n = parseName(file)?.[0];
  const st = status.get(path.dirname(file));
  if (n === undefined || !st || st.err || st.version === undefined) return undefined;
  if (st.dirty && n === st.version) return { text: `✗ dirty — упала на середине: исправь и migrate force ${Math.max(0, n - 1)}`, color: "errorForeground" };
  if (n <= st.version) return { text: "✓ применена", color: "testing.iconPassed" };
  return { text: "○ ждёт применения", color: "editorWarning.foreground" };
}

// ───── запуск ─────

function command(d: string, args: string[]): string | undefined {
  const u = projectUrl(projectRoot(path.join(d, "x")));
  if (!u) { vscode.window.showWarningMessage("Не нашёл базу проекта: DATABASE_URL в .env или postgres в compose"); return; }
  const q = (s: string) => `'${s.replace(/'/g, `'\\''`)}'`;
  if (tool(d) === "goose") return `go run github.com/pressly/goose/v3/cmd/goose@latest -dir ${q(d)} postgres ${q(u.url)} ${args.join(" ")}`;
  return `migrate -path ${q(d)} -database ${q(u.url)} ${args.join(" ")}`;
}

function run(d: string, args: string[], title: string) {
  const c = command(d, args);
  if (!c) return;
  const exec = new vscode.ShellExecution(c, { cwd: path.dirname(d) });
  const task = new vscode.Task({ type: "ownvim", migrate: args.join(" ") }, vscode.TaskScope.Workspace, title, "миграции", exec);
  task.presentationOptions = { reveal: vscode.TaskRevealKind.Always, panel: vscode.TaskPanelKind.Shared, clear: true };
  vscode.tasks.executeTask(task);
  const sub = vscode.tasks.onDidEndTaskProcess((e) => {
    if (e.execution.task.name !== title) return;
    sub.dispose();
    refresh(d, true);
  });
}

function need(): string | undefined {
  const d = dir();
  if (!d) vscode.window.showInformationMessage("Папки миграций нет — «новая миграция» создаст migrations/");
  return d;
}

export function up() { const d = need(); if (d) run(d, ["up"], "миграции вверх"); }

export async function down() {
  const d = need();
  if (!d) return;
  const s = await refresh(d, true);
  if (s.err) return vscode.window.showWarningMessage("База: " + s.err);
  if (!s.version) return vscode.window.showInformationMessage("Откатывать нечего — миграций в базе нет");
  const name = schema.files(d).map(parseName).find((p) => p?.[0] === s.version)?.[1] || "";
  const ok = await vscode.window.showWarningMessage(`Откатить ${s.version} ${name}?`, { modal: true }, "Да, откатить");
  if (ok) run(d, tool(d) === "goose" ? ["down"] : ["down", "1"], `откат ${s.version}`);
}

export function redo() {
  const d = need();
  if (!d) return;
  if (tool(d) === "goose") return run(d, ["redo"], "redo");
  const a = command(d, ["down", "1"]), b = command(d, ["up", "1"]);
  if (a && b) {
    const task = new vscode.Task({ type: "ownvim", migrate: "redo" }, vscode.TaskScope.Workspace, "redo", "миграции", new vscode.ShellExecution(`${a} && ${b}`));
    vscode.tasks.executeTask(task);
    const sub = vscode.tasks.onDidEndTaskProcess((e) => { if (e.execution.task.name === "redo") { sub.dispose(); refresh(d, true); } });
  }
}

export async function showStatus() {
  const d = need();
  if (!d) return;
  const s = await refresh(d, true);
  if (s.err) return vscode.window.showWarningMessage("База: " + s.err);
  const items = schema.files(d).flatMap((f) => {
    const p = parseName(f);
    if (!p) return [];
    const m = s.dirty && p[0] === s.version ? "$(error)" : p[0] <= (s.version || 0) ? "$(pass-filled)" : "$(circle-large-outline)";
    return [{ label: `${m} ${p[0]} ${p[1]}`, file: path.join(d, f) }];
  });
  const pick = await vscode.window.showQuickPick(items, { title: `База: версия ${s.version || 0}${s.dirty ? " (dirty)" : ""}` });
  if (pick) vscode.window.showTextDocument(vscode.Uri.file(pick.file));
}

/** cmd-shift-t в миграции: up ↔ down */
export function toggle() {
  const f = vscode.window.activeTextEditor?.document.uri.fsPath;
  const p = f && pair(f);
  if (p) vscode.window.showTextDocument(vscode.Uri.file(p));
}

export async function menu() {
  const d = dir();
  const items = [
    { label: "$(add) новая миграция", run: () => create() },
    { label: "$(arrow-up) up — применить все", run: up },
    { label: "$(arrow-down) down — откатить последнюю", run: down },
    { label: "$(sync) redo — откатить и применить последнюю", run: redo },
    { label: "$(list-unordered) статус", run: showStatus },
  ];
  const rel = d ? vscode.workspace.asRelativePath(d) : "";
  const pick = await vscode.window.showQuickPick(d ? items : items.slice(0, 1), { title: "Миграции" + (rel ? " · " + rel : "") });
  pick?.run();
}
