// Подключение к базе проекта — одно на всех: запросы из .sql, дополнение по живой базе, статус миграций
// (как lua/own/sql/db.lua):
//   0. "ownvim.database.url" в настройках
//   1. DATABASE_URL из .env в корне проекта
//   2. сервис postgres из compose-файла: POSTGRES_USER / POSTGRES_PASSWORD / POSTGRES_DB (${VAR} — из .env)
//      и опубликованный порт («5433:5432» → localhost:5433)
//   3. есть DB_PASSWORD или go.mod — postgres://postgres:<DB_PASSWORD>@localhost:5432/<папка проекта>
// Локальная база (localhost) без sslmode — дописывается sslmode=disable: migrate без него не подключится.
import * as fs from "fs";
import * as path from "path";
import * as vscode from "vscode";
import { Client } from "pg";

const COMPOSE = ["compose.yaml", "compose.yml", "docker-compose.yml", "docker-compose.yaml"];

export function readEnv(file: string): Record<string, string> {
  const env: Record<string, string> = {};
  let text: string;
  try { text = fs.readFileSync(file, "utf8"); } catch { return env; }
  for (const line of text.split(/\r?\n/)) {
    const m = line.match(/^\s*(?:export\s+)?([\w.]+)\s*=\s*(.*?)\s*$/);
    if (!m) continue;
    let v = m[2];
    if (/^".*"$|^'.*'$/.test(v)) v = v.slice(1, -1);
    else v = v.replace(/\s+#.*$/, "");
    env[m[1]] = v;
  }
  return env;
}

function subst(v: string, env: Record<string, string>): string {
  const get = (k: string) => env[k] ?? process.env[k] ?? "";
  return v.replace(/\$\{(\w+)[^}]*\}/g, (_, k) => get(k)).replace(/\$(\w+)/g, (_, k) => get(k));
}

const unquote = (v: string) => v.trim().replace(/^['"](.*)['"]$/, "$1");

function fromCompose(dir: string, env: Record<string, string>): Record<string, string> | undefined {
  for (const name of COMPOSE) {
    let text: string;
    try { text = fs.readFileSync(path.join(dir, name), "utf8"); } catch { continue; }
    const svc: string[][] = [];
    let cur: string[] | undefined;
    for (const l of text.split(/\r?\n/)) {
      const ind = l.match(/^(\s*)[\w.-]+:\s*$/);
      if (ind && ind[1].length === 2) { cur = []; svc.push(cur); }
      else if (/^\S/.test(l)) cur = undefined;
      else if (cur) cur.push(l);
    }
    for (const lines of svc) {
      const image = lines.join("\n").match(/image:\s*([^\n]+)/)?.[1] || "";
      if (!/postgres|postgis|timescale/.test(image)) continue;
      const out: Record<string, string> = { port: "5432" };
      for (const l of lines) {
        const kv = l.match(/^\s*-?\s*(POSTGRES_[A-Z_]+)\s*[:=]\s*(.*?)\s*$/);
        if (kv) out[kv[1]] = subst(unquote(kv[2]), env);
        const host = l.match(/^\s*-\s*['"]?[\d.]*:?(\d+):5432/);
        if (host) out.port = host[1];
      }
      return out;
    }
  }
  return undefined;
}

function localSsl(url: string): string {
  if (/@(localhost|127\.0\.0\.1)[:/]/.test(url) && !url.includes("sslmode=")) url += (url.includes("?") ? "&" : "?") + "sslmode=disable";
  return url;
}

/** Корень проекта для файла: ближайшая папка вверх с go.mod / .env / compose / .git, иначе папка workspace */
export function projectRoot(file?: string): string | undefined {
  const ws = file ? vscode.workspace.getWorkspaceFolder(vscode.Uri.file(file))?.uri.fsPath : undefined;
  const top = ws || vscode.workspace.workspaceFolders?.[0]?.uri.fsPath;
  if (!file) return top;
  let d = path.dirname(file);
  for (;;) {
    if (["go.mod", ".env", ...COMPOSE, ".git"].some((f) => fs.existsSync(path.join(d, f)))) return d;
    const up = path.dirname(d);
    if (up === d || (top && !up.startsWith(top))) return top;
    d = up;
  }
}

/** URL базы проекта и имя подключения; undefined — не нашлось */
export function projectUrl(dir?: string): { url: string; name: string } | undefined {
  const own = vscode.workspace.getConfiguration("ownvim.database").get<string>("url");
  dir = dir || projectRoot(vscode.window.activeTextEditor?.document.uri.fsPath);
  if (!dir) return own ? { url: own, name: "своё" } : undefined;
  const name = path.basename(dir);
  if (own) return { url: own, name };
  const env = readEnv(path.join(dir, ".env"));
  if (env.DATABASE_URL) return { url: localSsl(subst(env.DATABASE_URL, env)), name };
  const c = fromCompose(dir, env);
  if (c) {
    const user = c.POSTGRES_USER || "postgres";
    const pass = c.POSTGRES_PASSWORD || env.DB_PASSWORD || "postgres";
    const db = c.POSTGRES_DB || user;
    return { url: `postgres://${user}:${encodeURIComponent(pass)}@localhost:${c.port}/${db}?sslmode=disable`, name };
  }
  if (env.DB_PASSWORD || fs.existsSync(path.join(dir, "go.mod")))
    return { url: `postgres://postgres:${encodeURIComponent(env.DB_PASSWORD || "postgres")}@localhost:5432/${name}?sslmode=disable`, name };
  return undefined;
}

/** pg не понимает sslmode=disable так, как libpq — убрать и выключить ssl явно */
function clientConfig(url: string) {
  const u = new URL(url);
  const mode = u.searchParams.get("sslmode");
  u.searchParams.delete("sslmode");
  return { connectionString: u.toString(), ssl: !mode || mode === "disable" ? false : { rejectUnauthorized: mode === "verify-full" }, connectionTimeoutMillis: 3000 };
}

export async function withClient<T>(url: string, fn: (c: Client) => Promise<T>): Promise<T> {
  const c = new Client(clientConfig(url));
  await c.connect();
  try { return await fn(c); } finally { c.end().catch(() => undefined); }
}

export interface LiveSchema { tables: Map<string, { name: string; cols: { name: string; type: string; notes: string }[] }>; enums: Map<string, string[]>; at: number }
const live = new Map<string, LiveSchema | "pending" | number>(); // number — когда не подключилось

/** Таблицы и колонки живой базы (кэш на 30 с); пока не загрузилось — undefined */
export function liveSchema(url: string): LiveSchema | undefined {
  const c = live.get(url);
  if (c === "pending" || (typeof c === "number" && Date.now() - c < 30_000)) return undefined;
  if (c && typeof c === "object" && Date.now() - c.at < 30_000) return c;
  live.set(url, "pending");
  withClient(url, async (cl) => {
    const cols = await cl.query(`SELECT c.table_name, c.column_name, c.udt_name, c.is_nullable, c.column_default
      FROM information_schema.columns c JOIN information_schema.tables t USING (table_schema, table_name)
      WHERE c.table_schema = 'public' ORDER BY c.table_name, c.ordinal_position`);
    const en = await cl.query(`SELECT t.typname, e.enumlabel FROM pg_type t JOIN pg_enum e ON e.enumtypid = t.oid ORDER BY t.typname, e.enumsortorder`);
    const s: LiveSchema = { tables: new Map(), enums: new Map(), at: Date.now() };
    for (const r of cols.rows) {
      if (!s.tables.has(r.table_name)) s.tables.set(r.table_name, { name: r.table_name, cols: [] });
      const notes = [r.is_nullable === "NO" ? "not null" : "", r.column_default ? "= " + r.column_default : ""].filter(Boolean).join(", ");
      s.tables.get(r.table_name)!.cols.push({ name: r.column_name, type: r.udt_name, notes });
    }
    for (const r of en.rows) s.enums.set(r.typname, [...(s.enums.get(r.typname) || []), r.enumlabel]);
    live.set(url, s);
  }).catch(() => live.set(url, Date.now()));
  return undefined;
}
