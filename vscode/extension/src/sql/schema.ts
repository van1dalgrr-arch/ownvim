// Схема базы из файлов миграций — без подключения к базе и с ещё не применёнными миграциями
// (как lua/own/sql/schema.lua). Читает по порядку имён *.up.sql (golang-migrate) или *.sql (goose — только
// часть «-- +goose Up») и проигрывает CREATE/ALTER/DROP TABLE, CREATE TYPE … AS ENUM, ALTER TYPE … ADD VALUE.
import * as fs from "fs";
import * as path from "path";

export interface Ref { table: string; col: string }
export interface Column { name: string; type: string; notes: string; ref?: Ref; file?: string }
export interface Table { name: string; cols: Column[]; file?: string; view?: boolean }
export interface Schema { tables: Map<string, Table>; enums: Map<string, string[]>; dir?: string }

export type Action =
  | { op: "rename_table"; to: string; text: string }
  | { op: "add_constraint"; name?: string; fk?: { cols: string[]; table: string; col: string }; text: string }
  | { op: "add_column"; col?: Column; text: string }
  | { op: "drop_constraint"; text: string }
  | { op: "drop_column"; col: string; text: string }
  | { op: "rename_column"; from: string; to: string; text: string }
  | { op: "alter_type"; col: string; type: string; text: string }
  | { op: "other"; text: string };

export type Statement = { source: string; start: number } & (
  | { kind: "create_table"; table: string; cols: Column[] }
  | { kind: "create_enum"; name: string; values: string[] }
  | { kind: "enum_add"; name: string; value?: string }
  | { kind: "drop_table" | "drop_type" | "drop_view"; names: string[] }
  | { kind: "alter_table"; table: string; actions: Action[] }
  | { kind: "create_index"; name: string; concurrently: boolean; table?: string }
  | { kind: "create_extension" | "create_function"; name: string }
  | { kind: "create_trigger"; name: string; table: string }
  | { kind: "create_view"; name: string; materialized: boolean }
  | { kind: "other" }
);

export const KEYWORDS = new Set(`select from where join left right inner outer full cross on using and or not null is in as
  group by order having limit offset union all distinct returning set values into update delete insert
  with case when then else end exists between like ilike asc desc natural lateral window over`.split(/\s+/));

const NAME = String.raw`("?\w+"?\.?"?\w*"?)`;

/** "public"."Users" → users; public.users → users */
export function ident(s: string | undefined): string {
  if (!s) return "";
  s = s.replace(/"/g, "");
  const m = s.match(/^\w+\.(\w+)$/);
  return (m ? m[1] : s).toLowerCase();
}

/** Текст без комментариев (той же длины — позиции сохраняются); кавычки и $$-тела не трогаем */
export function stripComments(text: string): string {
  let out = "";
  let i = 0;
  const n = text.length;
  while (i < n) {
    const c = text[i], two = text.slice(i, i + 2);
    if (two === "--") {
      let e = text.indexOf("\n", i);
      if (e < 0) e = n;
      out += " ".repeat(e - i);
      i = e;
    } else if (two === "/*") {
      let e = text.indexOf("*/", i + 2);
      e = e < 0 ? n : e + 2;
      out += text.slice(i, e).replace(/[^\n]/g, " ");
      i = e;
    } else if (c === "'") {
      let e = i + 1;
      while (e < n) {
        if (text[e] === "'") { if (text[e + 1] === "'") e += 2; else break; } else e++;
      }
      out += text.slice(i, e + 1);
      i = e + 1;
    } else if (c === "$" && /^\$\w*\$/.test(text.slice(i))) {
      const tag = text.slice(i).match(/^\$\w*\$/)![0];
      const e = text.indexOf(tag, i + tag.length);
      const stop = e < 0 ? n : e + tag.length;
      out += text.slice(i, stop);
      i = stop;
    } else {
      out += c;
      i++;
    }
  }
  return out;
}

/** Разбить по разделителю sep вне скобок, кавычек и $$-тел; с позицией начала каждой части */
export function splitAt(text: string, sep = ";"): { text: string; start: number }[] {
  const parts: { text: string; start: number }[] = [];
  let depth = 0, start = 0, i = 0;
  const n = text.length;
  while (i < n) {
    const c = text[i];
    if (c === "'" || c === '"') {
      const e = text.indexOf(c, i + 1);
      i = (e < 0 ? n : e) + 1;
    } else if (c === "$" && /^\$\w*\$/.test(text.slice(i))) {
      const tag = text.slice(i).match(/^\$\w*\$/)![0];
      const e = text.indexOf(tag, i + tag.length);
      i = e < 0 ? n : e + tag.length;
    } else {
      if (c === "(") depth++;
      else if (c === ")") depth = Math.max(0, depth - 1);
      else if (c === sep && depth === 0) {
        parts.push({ text: text.slice(start, i), start });
        start = i + 1;
      }
      i++;
    }
  }
  parts.push({ text: text.slice(start), start });
  const out: { text: string; start: number }[] = [];
  for (const p of parts) {
    const lead = p.text.length - p.text.trimStart().length;
    const t = p.text.trim();
    if (t) out.push({ text: t, start: p.start + lead });
  }
  return out;
}

export function split(text: string, sep = ";"): string[] { return splitAt(text, sep).map((p) => p.text); }

/** Содержимое первых скобок: "(a, b(1))" → "a, b(1)" */
export function parens(s: string, from = 0): string | undefined {
  const open = s.indexOf("(", from);
  if (open < 0) return undefined;
  let depth = 0;
  for (let i = open; i < s.length; i++) {
    if (s[i] === "(") depth++;
    else if (s[i] === ")") { depth--; if (depth === 0) return s.slice(open + 1, i); }
  }
  return s.slice(open + 1);
}

const STOP = new Set(["not", "null", "default", "primary", "references", "unique", "check", "generated", "collate", "constraint"]);

/** "email TEXT UNIQUE NOT NULL" → { name: "email", type: "text", notes: "unique, not null" } */
export function column(def: string): Column | undefined {
  const m = def.match(/^\s*("?\w+"?)\s+([\s\S]*)$/);
  if (!m) return undefined;
  const [, name, rest] = m;
  const words = rest.split(/\s+/).filter(Boolean);
  const typ: string[] = [], notes: string[] = [];
  let i = 0;
  while (i < words.length && !STOP.has(words[i].toLowerCase().replace(/[^\w].*$/, ""))) typ.push(words[i++]);
  const tail = words.slice(i).join(" ").toLowerCase();
  if (tail.includes("primary key")) notes.push("первичный ключ");
  if (tail.includes("not null")) notes.push("not null");
  if (tail.includes("unique")) notes.push("unique");
  const ref = tail.match(new RegExp("references\\s+" + NAME))?.[1];
  if (ref) notes.push("→ " + ident(ref));
  const refCol = ref ? tail.match(/references\s+[^\s(]+\s*\(\s*"?(\w+)/)?.[1] : undefined;
  let defV = rest.match(/default\s+(.*?)\s*$/i)?.[1];
  if (defV) {
    defV = defV.replace(/\s+not\s+null.*$/i, "").replace(/\s+references.*$/i, "");
    notes.push("= " + defV);
  }
  if (tail.includes("generated")) notes.push("generated");
  return {
    name: ident(name), type: typ.join(" ").toLowerCase(), notes: notes.join(", "),
    ref: ref ? { table: ident(ref), col: refCol || "id" } : undefined,
  };
}

const TABLE_CONSTRAINT = new Set(["constraint", "primary", "unique", "check", "foreign", "exclude", "like"]);

function fkOf(flat: string): { cols: string[]; table: string; col: string } | undefined {
  const m = flat.match(new RegExp("foreign key ?\\(([^)]*)\\) ?references " + NAME));
  if (!m) return undefined;
  const col = flat.match(/references [^\s(]+ ?\(\s*"?(\w+)/)?.[1] || "id";
  return { cols: m[1].split(/[,\s]+/).filter(Boolean).map(ident), table: ident(m[2]), col };
}

function first(l: string, pats: string[]): string | undefined {
  for (const p of pats) {
    const m = l.match(new RegExp(p));
    if (m) return m[1];
  }
  return undefined;
}

type Parsed = Statement extends infer S ? (S extends { source: string; start: number } ? Omit<S, "source" | "start"> : never) : never;

/** Разобрать одно выражение */
export function statement(st: string): Parsed {
  const s = st.replace(/\s+/g, " ");
  const l = s.toLowerCase();

  // CREATE TABLE
  let name = first(l, ["^create\\s+[\\w\\s]*?table\\s+if\\s+not\\s+exists\\s+" + NAME, "^create\\s+[\\w\\s]*?table\\s+" + NAME]);
  if (name && !/^create\s+[\w\s]*?table\s+[^(]*?\sas\s/.test(l)) {
    const cols: Column[] = [];
    const fks = new Map<string, Ref>();
    for (const item of split(parens(s) || "", ",")) {
      const f = item.match(/^(\S+)/)?.[1];
      if (f && !TABLE_CONSTRAINT.has(f.toLowerCase())) {
        const c = column(item);
        if (c) cols.push(c);
      } else if (f) {
        const fk = fkOf(item.toLowerCase().replace(/\s+/g, " "));
        if (fk) for (const c of fk.cols) fks.set(c, { table: fk.table, col: fk.col });
      }
    }
    for (const c of cols) {
      const r = fks.get(c.name);
      if (r) { c.notes += (c.notes ? ", " : "") + "→ " + r.table; c.ref = r; }
    }
    return { kind: "create_table", table: ident(name), cols };
  }

  // CREATE TYPE … AS ENUM
  name = l.match(new RegExp("^create\\s+type\\s+" + NAME + "\\s+as\\s+enum"))?.[1];
  if (name) {
    const values = [...(parens(s) || "").matchAll(/'([^']*)'/g)].map((m) => m[1]);
    return { kind: "create_enum", name: ident(name), values };
  }
  name = l.match(new RegExp("^alter\\s+type\\s+" + NAME + "\\s+add\\s+value"))?.[1];
  if (name) return { kind: "enum_add", name: ident(name), value: s.match(/'([^']*)'/)?.[1] };

  // DROP
  let dm = l.match(/^drop\s+(\w+)\s+(.*)$/);
  if (dm && dm[1] === "materialized") { const v = l.match(/^drop\s+materialized\s+view\s+(.*)$/); dm = v ? [v[0], "view", v[1]] as any : null; }
  if (dm && (dm[1] === "table" || dm[1] === "type" || dm[1] === "view")) {
    const list = dm[2].replace(/^if\s+exists\s+/, "").replace(/\s+(cascade|restrict)\s*$/, "");
    return { kind: ("drop_" + dm[1]) as "drop_table", names: list.split(/[,\s]+/).filter(Boolean).map(ident) };
  }

  // ALTER TABLE
  for (const pat of ["^alter\\s+table\\s+if\\s+exists\\s+only\\s+", "^alter\\s+table\\s+if\\s+exists\\s+", "^alter\\s+table\\s+only\\s+", "^alter\\s+table\\s+"]) {
    const m = l.match(new RegExp(pat + NAME));
    if (!m) continue;
    const tbl = ident(m[1]);
    const actions: Action[] = [];
    for (const a of split(s.slice(m[0].length), ",")) {
      const al = a.toLowerCase();
      let act: Action | undefined;
      const to = al.match(new RegExp("^rename\\s+to\\s+" + NAME))?.[1];
      if (to) act = { op: "rename_table", to: ident(to), text: a };
      else if (/^add\s+constraint/.test(al) || /^add\s+foreign/.test(al)) {
        const n = al.match(new RegExp("^add\\s+constraint\\s+" + NAME))?.[1];
        act = { op: "add_constraint", name: n ? ident(n) : undefined, fk: fkOf(al.replace(/\s+/g, " ")), text: a };
      } else if (/^add\s/.test(al) && !/^add\s+(primary|unique|foreign|check)/.test(al)) {
        const def = a.replace(/^\s*add\s+/i, "").replace(/^column\s+/i, "").replace(/^if\s+not\s+exists\s+/i, "");
        act = { op: "add_column", col: column(def), text: a };
      } else if (/^drop\s+constraint/.test(al)) act = { op: "drop_constraint", text: a };
      else if (/^drop\s/.test(al)) {
        const c = al.replace(/^drop\s+/, "").replace(/^column\s+/, "").replace(/^if\s+exists\s+/, "").match(new RegExp("^" + NAME))?.[1];
        act = { op: "drop_column", col: ident(c), text: a };
      } else {
        const r = al.match(new RegExp("^rename\\s+column\\s+" + NAME + "\\s+to\\s+" + NAME)) || al.match(new RegExp("^rename\\s+" + NAME + "\\s+to\\s+" + NAME));
        if (r) act = { op: "rename_column", from: ident(r[1]), to: ident(r[2]), text: a };
        else {
          const t = al.match(new RegExp("^alter\\s+column\\s+" + NAME + "\\s+set\\s+data\\s+type\\s+(.*?)\\s*$"))
            || al.match(new RegExp("^alter\\s+column\\s+" + NAME + "\\s+type\\s+(.*?)\\s*$"))
            || al.match(new RegExp("^alter\\s+" + NAME + "\\s+type\\s+(.*?)\\s*$"));
          act = t ? { op: "alter_type", col: ident(t[1]), type: t[2].replace(/\s+using\s.*$/, ""), text: a } : { op: "other", text: a };
        }
      }
      actions.push(act);
    }
    return { kind: "alter_table", table: tbl, actions };
  }

  // то, что нужно для отката (down) и проверок
  const idx = l.match(new RegExp("^create\\s+(?:unique\\s+)?index\\s+(concurrently\\s+)?(?:if\\s+not\\s+exists\\s+)?" + NAME + "\\s+on\\s+(?:only\\s+)?" + NAME));
  if (idx) return { kind: "create_index", name: ident(idx[2]), concurrently: !!idx[1], table: ident(idx[3]) };
  const anon = l.match(new RegExp("^create\\s+(?:unique\\s+)?index\\s+(concurrently\\s+)?on\\s+(?:only\\s+)?" + NAME));
  if (anon) return { kind: "create_index", name: "", concurrently: !!anon[1], table: ident(anon[2]) };
  name = first(l, ["^create\\s+extension\\s+if\\s+not\\s+exists\\s+" + NAME, "^create\\s+extension\\s+" + NAME]);
  if (name) return { kind: "create_extension", name: ident(name) };
  name = first(l, ["^create\\s+or\\s+replace\\s+function\\s+" + NAME, "^create\\s+function\\s+" + NAME]);
  if (name) return { kind: "create_function", name: ident(name) };
  const trig = l.match(new RegExp("^create\\s+[\\w\\s]*?trigger\\s+" + NAME + ".*?\\son\\s+" + NAME));
  if (trig) return { kind: "create_trigger", name: ident(trig[1]), table: ident(trig[2]) };
  const mat = l.match(new RegExp("^create\\s+[\\w\\s]*?materialized\\s+view\\s+" + NAME));
  const view = mat?.[1] || first(l, ["^create\\s+or\\s+replace\\s+view\\s+" + NAME, "^create\\s+view\\s+" + NAME]);
  if (view) return { kind: "create_view", name: ident(view), materialized: !!mat };
  return { kind: "other" };
}

const GOOSE_UP = /--\s*\+goose\s+up/i;
const GOOSE_DOWN = /--\s*\+goose\s+down/i;

/** Часть up: goose — между «-- +goose Up» и «-- +goose Down» (остальное — пробелами, позиции те же), иначе весь файл */
export function upPart(text: string): string {
  const u = text.match(GOOSE_UP);
  if (!u) return text;
  const from = text.indexOf("\n", u.index!) + 1;
  const d = text.slice(from).search(GOOSE_DOWN);
  const to = d < 0 ? text.length : from + d;
  const blank = (s: string) => s.replace(/[^\n]/g, " ");
  return blank(text.slice(0, from)) + text.slice(from, to) + blank(text.slice(to));
}

/** Выражения текста по порядку, уже разобранные; start — смещение в исходном тексте */
export function statements(text: string): Statement[] {
  return splitAt(stripComments(text)).map((p) => ({ ...statement(p.text), source: p.text, start: p.start }) as Statement);
}

function apply(schema: Schema, p: Statement, file: string) {
  const t = schema.tables;
  switch (p.kind) {
    case "create_table":
      for (const c of p.cols) c.file = file;
      t.set(p.table, { name: p.table, cols: p.cols, file });
      break;
    case "create_view":
      if (!t.has(p.name)) t.set(p.name, { name: p.name, cols: [], file, view: true });
      break;
    case "drop_table": case "drop_view":
      for (const n of p.names) t.delete(n);
      break;
    case "drop_type":
      for (const n of p.names) schema.enums.delete(n);
      break;
    case "create_enum":
      schema.enums.set(p.name, p.values);
      break;
    case "enum_add":
      if (p.value) schema.enums.set(p.name, [...(schema.enums.get(p.name) || []), p.value]);
      break;
    case "alter_table": {
      let tbl = t.get(p.table);
      if (!tbl) return;
      for (const a of p.actions) {
        if (a.op === "add_column" && a.col) { a.col.file = file; tbl.cols.push(a.col); }
        else if (a.op === "add_constraint" && a.fk) {
          for (const c of tbl.cols) if (a.fk.cols.includes(c.name)) {
            c.ref = { table: a.fk.table, col: a.fk.col };
            if (!c.notes.includes("→")) c.notes += (c.notes ? ", " : "") + "→ " + a.fk.table;
          }
        } else if (a.op === "drop_column") tbl.cols = tbl.cols.filter((c) => c.name !== a.col);
        else if (a.op === "rename_column") { for (const c of tbl.cols) if (c.name === a.from) c.name = a.to; }
        else if (a.op === "alter_type") { for (const c of tbl.cols) if (c.name === a.col) c.type = a.type; }
        else if (a.op === "rename_table") { t.delete(tbl.name); tbl.name = a.to; t.set(a.to, tbl); }
      }
    }
  }
}

/** Файлы миграций (up) по порядку */
export function files(dir: string): string[] {
  try {
    return fs.readdirSync(dir).filter((f) => f.endsWith(".sql") && !f.endsWith(".down.sql")).sort();
  } catch { return []; }
}

const cache = new Map<string, { key: string; schema: Schema }>();

/** Схема по папке миграций; пересчитывается, только если файлы поменялись. override — несохранённые тексты */
export function load(dir: string, override: Map<string, string> = new Map()): Schema {
  const fl = files(dir);
  const sig = fl.map((f) => { try { return f + ":" + fs.statSync(path.join(dir, f)).mtimeMs; } catch { return f; } });
  for (const [p, text] of override) sig.push(p + "#" + text.length + ":" + hash(text));
  const key = sig.join("|");
  const c = cache.get(dir);
  if (c && c.key === key) return c.schema;
  const schema: Schema = { tables: new Map(), enums: new Map(), dir };
  for (const f of fl) {
    const p = path.join(dir, f);
    let text = override.get(p);
    if (text === undefined) { try { text = fs.readFileSync(p, "utf8"); } catch { text = ""; } }
    for (const st of statements(upPart(text))) apply(schema, st, f);
  }
  cache.set(dir, { key, schema });
  return schema;
}

function hash(s: string): number {
  let h = 0;
  for (let i = 0; i < s.length; i++) h = (h * 31 + s.charCodeAt(i)) | 0;
  return h;
}
