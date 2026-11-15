// Автосохранение как в ownvim (lua/own/modules/autosave.lua): вышел из вставки, поправил в обычном режиме
// (dd, p, u…), ушёл в другое окно — файл записан. Запись — как cmd-s, поэтому срабатывают
// форматирование и импорты (formatOnSave, codeActionsOnSave).
//   Выход из вставки: Esc / ctrl-[ / ctrl-c во вставке — ownvim.escape (keybindings.json): выйти и записать.
//   Остальное (jk, правки в обычном режиме): режим Vim расширениям не виден, но VSCodeVim меняет форму
//   курсора — во вставке черта, иначе блок (vim.cursorStylePerMode); её и смотрим.
import * as vscode from "vscode";

const on = () => vscode.workspace.getConfiguration("ownvim").get<boolean>("autosave") !== false;
const inserting = (ed?: vscode.TextEditor) => ed?.options.cursorStyle === vscode.TextEditorCursorStyle.Line;

let saving = false;
async function save(doc: vscode.TextDocument) {
  if (saving || !on() || !doc.isDirty || doc.isUntitled || doc.uri.scheme !== "file") return;
  saving = true;
  try {
    const ed = vscode.window.activeTextEditor;
    // активный файл — как cmd-s (форматирование и импорты наверняка), остальные — через API
    if (ed?.document === doc) await vscode.commands.executeCommand("workbench.action.files.save");
    else await doc.save();
  } finally { saving = false; }
}

export function activate(ctx: vscode.ExtensionContext) {
  let timer: NodeJS.Timeout | undefined;
  const later = (doc: vscode.TextDocument, ms: number) => {
    clearTimeout(timer);
    timer = setTimeout(() => { if (!inserting(vscode.window.activeTextEditor)) save(doc); }, ms);
  };

  // форма курсора — раз в 150 мс: событие о смене опций приходит не всегда
  let was = vscode.window.activeTextEditor?.options.cursorStyle;
  const poll = setInterval(() => {
    const ed = vscode.window.activeTextEditor;
    const now = ed?.options.cursorStyle;
    if (ed && was === vscode.TextEditorCursorStyle.Line && now !== vscode.TextEditorCursorStyle.Line) later(ed.document, 30);
    was = now;
  }, 150);

  ctx.subscriptions.push(
    vscode.commands.registerCommand("ownvim.escape", async () => {
      await vscode.commands.executeCommand("extension.vim_escape");
      const ed = vscode.window.activeTextEditor;
      if (ed) await save(ed.document);
    }),
    vscode.window.onDidChangeTextEditorOptions((e) => {
      if (e.textEditor === vscode.window.activeTextEditor && was === vscode.TextEditorCursorStyle.Line && e.options.cursorStyle !== vscode.TextEditorCursorStyle.Line) later(e.textEditor.document, 30);
      if (e.textEditor === vscode.window.activeTextEditor) was = e.options.cursorStyle;
    }),
    // правка в обычном режиме: dd, p, u, >>… (не во время набора)
    vscode.workspace.onDidChangeTextDocument((e) => {
      const ed = vscode.window.activeTextEditor;
      if (saving || !e.contentChanges.length || ed?.document !== e.document || inserting(ed)) return;
      later(e.document, 300);
    }),
    // ушёл в другой файл или из окна — записать
    vscode.window.onDidChangeActiveTextEditor((ed) => {
      was = ed?.options.cursorStyle;
      for (const d of vscode.workspace.textDocuments) if (d !== ed?.document && d.isDirty) save(d);
    }),
    vscode.window.onDidChangeWindowState((s) => {
      if (!s.focused) for (const d of vscode.workspace.textDocuments) if (d.isDirty) d.save();
    }),
    { dispose: () => { clearTimeout(timer); clearInterval(poll); } },
  );
}
