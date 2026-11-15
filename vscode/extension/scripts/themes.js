// Темы ownvim (themes/*.json: palette + syntax) → темы VS Code в themes/ и список для package.json
const fs = require("fs");
const path = require("path");
const src = path.join(__dirname, "../../../themes");
const out = path.join(__dirname, "../themes");

const read = (f) => JSON.parse(fs.readFileSync(f, "utf8").replace(/^\s*\/\/.*$/gm, ""));
const alpha = (hex, a) => hex + Math.round(a * 255).toString(16).padStart(2, "0");

function theme(t) {
  const p = t.palette;
  const c = (v) => (typeof v === "string" && v.startsWith("#") ? v : p[v] || v);
  const syn = (k) => { const v = t.syntax[k]; if (!v) return {}; if (typeof v === "string") return { foreground: c(v) };
    return { foreground: c(v.fg), fontStyle: [v.italic && "italic", v.bold && "bold"].filter(Boolean).join(" ") || undefined }; };
  const dark = t.type !== "light";
  const colors = {
    "editor.background": p.bg, "editor.foreground": p.fg, "editorCursor.foreground": p.accent,
    "editor.lineHighlightBackground": p.bg_highlight, "editor.lineHighlightBorder": "#00000000",
    "editor.selectionBackground": p.bg_visual, "editor.inactiveSelectionBackground": alpha(p.bg_visual.slice(0, 7), 0.6),
    "editor.wordHighlightBackground": alpha(p.accent, 0.15), "editor.findMatchBackground": alpha(p.yellow, 0.35), "editor.findMatchHighlightBackground": alpha(p.yellow, 0.18),
    "editorLineNumber.foreground": p.fg_muted, "editorLineNumber.activeForeground": p.accent,
    "editorIndentGuide.background1": p.border, "editorIndentGuide.activeBackground1": alpha(p.accent, 0.5),
    "editorWhitespace.foreground": p.border, "editorRuler.foreground": p.border,
    "editorBracketMatch.background": alpha(p.accent, 0.2), "editorBracketMatch.border": alpha(p.accent, 0.6),
    "editorGutter.addedBackground": p.green, "editorGutter.modifiedBackground": p.blue, "editorGutter.deletedBackground": p.red,
    "editorError.foreground": p.red, "editorWarning.foreground": p.yellow, "editorInfo.foreground": p.cyan, "editorHint.foreground": p.fg_muted,
    "editorInlayHint.foreground": p.fg_muted, "editorInlayHint.background": "#00000000", "editorCodeLens.foreground": p.fg_muted,
    "editorWidget.background": p.bg_alt, "editorWidget.border": p.border, "editorHoverWidget.background": p.bg_alt, "editorHoverWidget.border": p.border,
    "editorSuggestWidget.background": p.bg_alt, "editorSuggestWidget.border": p.border, "editorSuggestWidget.selectedBackground": p.bg_visual,
    "editorSuggestWidget.highlightForeground": p.accent, "editorSuggestWidget.focusHighlightForeground": p.accent,
    "editorStickyScroll.background": p.bg, "editorStickyScrollHover.background": p.bg_highlight,
    "editorGroupHeader.tabsBackground": p.bg, "editorGroupHeader.noTabsBackground": p.bg, "editorGroup.border": p.border,
    "tab.activeBackground": p.bg, "tab.inactiveBackground": p.bg, "tab.activeForeground": p.fg, "tab.inactiveForeground": p.fg_muted,
    "tab.activeBorderTop": p.accent, "tab.border": p.bg, "tab.unfocusedActiveBorderTop": p.border,
    "titleBar.activeBackground": p.bg, "titleBar.inactiveBackground": p.bg, "titleBar.activeForeground": p.fg_dim, "titleBar.border": p.border,
    "activityBar.background": p.bg, "activityBar.foreground": p.accent, "activityBar.inactiveForeground": p.fg_muted, "activityBar.border": p.border,
    "activityBar.activeBorder": p.accent, "activityBarBadge.background": p.accent, "activityBarBadge.foreground": p.bg,
    "sideBar.background": p.bg, "sideBar.foreground": p.fg_dim, "sideBar.border": p.border, "sideBarSectionHeader.background": p.bg,
    "sideBarSectionHeader.foreground": p.fg_muted, "sideBarSectionHeader.border": p.border, "sideBarTitle.foreground": p.fg_muted,
    "list.activeSelectionBackground": p.bg_visual, "list.activeSelectionForeground": p.fg, "list.inactiveSelectionBackground": p.bg_highlight,
    "list.hoverBackground": p.bg_highlight, "list.focusOutline": alpha(p.accent, 0.6), "list.highlightForeground": p.accent,
    "list.errorForeground": p.red, "list.warningForeground": p.yellow, "tree.indentGuidesStroke": p.border,
    "statusBar.background": p.bg, "statusBar.foreground": p.fg_dim, "statusBar.border": p.border, "statusBar.noFolderBackground": p.bg,
    "statusBar.debuggingBackground": p.orange, "statusBar.debuggingForeground": p.bg, "statusBarItem.remoteBackground": p.accent, "statusBarItem.remoteForeground": p.bg,
    "panel.background": p.bg, "panel.border": p.border, "panelTitle.activeForeground": p.fg, "panelTitle.inactiveForeground": p.fg_muted, "panelTitle.activeBorder": p.accent,
    "terminal.background": p.bg, "terminal.foreground": p.fg, "terminalCursor.foreground": p.accent,
    "terminal.ansiBlack": dark ? p.bg_alt : p.fg, "terminal.ansiRed": p.red, "terminal.ansiGreen": p.green, "terminal.ansiYellow": p.yellow,
    "terminal.ansiBlue": p.blue, "terminal.ansiMagenta": p.purple, "terminal.ansiCyan": p.cyan, "terminal.ansiWhite": dark ? p.fg : p.bg_alt,
    "terminal.ansiBrightBlack": p.fg_muted, "terminal.ansiBrightRed": p.red, "terminal.ansiBrightGreen": p.green, "terminal.ansiBrightYellow": p.yellow,
    "terminal.ansiBrightBlue": p.blue, "terminal.ansiBrightMagenta": p.pink, "terminal.ansiBrightCyan": p.cyan, "terminal.ansiBrightWhite": dark ? "#ffffff" : p.fg_dim,
    "input.background": p.bg_alt, "input.border": p.border, "input.placeholderForeground": p.fg_muted, "inputOption.activeBorder": p.accent,
    "dropdown.background": p.bg_alt, "dropdown.border": p.border, "focusBorder": alpha(p.accent, 0.6), "foreground": p.fg_dim,
    "button.background": p.accent, "button.foreground": p.bg, "button.hoverBackground": alpha(p.accent, 0.85),
    "badge.background": p.accent, "badge.foreground": p.bg, "progressBar.background": p.accent, "textLink.foreground": p.accent,
    "quickInput.background": p.bg_alt, "quickInputList.focusBackground": p.bg_visual, "pickerGroup.foreground": p.accent, "pickerGroup.border": p.border,
    "widget.shadow": "#00000040", "scrollbarSlider.background": alpha(p.fg_muted, 0.2), "scrollbarSlider.hoverBackground": alpha(p.fg_muted, 0.35),
    "minimap.background": p.bg, "breadcrumb.foreground": p.fg_muted, "breadcrumb.focusForeground": p.fg,
    "gitDecoration.modifiedResourceForeground": p.blue, "gitDecoration.untrackedResourceForeground": p.green, "gitDecoration.deletedResourceForeground": p.red,
    "gitDecoration.ignoredResourceForeground": p.fg_muted, "gitDecoration.conflictingResourceForeground": p.orange,
    "diffEditor.insertedTextBackground": alpha(p.green, 0.15), "diffEditor.removedTextBackground": alpha(p.red, 0.15),
    "testing.iconPassed": p.green, "testing.iconFailed": p.red, "debugIcon.breakpointForeground": p.red,
    "notifications.background": p.bg_alt, "notifications.border": p.border, "menu.background": p.bg_alt, "menu.selectionBackground": p.bg_visual,
    "errorLens.errorForeground": p.red, "errorLens.warningForeground": p.yellow, "errorLens.infoForeground": p.cyan, "errorLens.hintForeground": p.fg_muted,
    "errorLens.errorBackground": alpha(p.red, 0.08), "errorLens.warningBackground": alpha(p.yellow, 0.08), "errorLens.infoBackground": "#00000000", "errorLens.hintBackground": "#00000000",
    "errorForeground": p.red, "disabledForeground": p.fg_muted, "descriptionForeground": p.fg_muted,
  };
  const tok = (scope, k) => ({ scope, settings: syn(k) });
  const tokenColors = [
    tok(["comment", "punctuation.definition.comment"], "comment"),
    tok(["keyword", "storage", "storage.type", "keyword.control", "keyword.other.sql"], "keyword"),
    tok(["entity.name.function", "support.function", "meta.function-call.generic"], "function"),
    tok(["string", "string.quoted", "punctuation.definition.string"], "string"),
    tok(["entity.name.type", "support.type", "storage.type.numeric.go", "storage.type.string.go", "entity.name.class", "support.class"], "type"),
    tok(["constant.numeric"], "number"), tok(["constant", "support.constant", "variable.other.constant"], "constant"),
    tok(["constant.language.boolean", "constant.language"], "boolean"), tok(["variable", "meta.definition.variable"], "variable"),
    tok(["variable.other.property", "variable.other.object.property", "entity.name.tag.yaml", "support.type.property-name"], "property"),
    tok(["entity.other.attribute-name", "entity.name.tag"], "attribute"),
    tok(["keyword.operator"], "operator"), tok(["punctuation", "meta.brace"], "punctuation"),
    tok(["support.function.builtin", "variable.language", "support.function.builtin.go"], "builtin"),
    tok(["variable.parameter"], "parameter"), tok(["entity.name.package", "entity.name.namespace", "entity.name.import.go"], "namespace"),
    { scope: ["markup.heading"], settings: { foreground: p.accent, fontStyle: "bold" } },
    { scope: ["markup.inline.raw", "markup.fenced_code"], settings: { foreground: c(t.syntax.string) } },
  ].filter((x) => x.settings.foreground);
  const sem = (k) => syn(k).foreground && { foreground: syn(k).foreground, ...(syn(k).fontStyle?.includes("italic") ? { italic: true } : {}) };
  const semanticTokenColors = Object.fromEntries(Object.entries({
    function: sem("function"), method: sem("function"), type: sem("type"), class: sem("type"), struct: sem("type"), interface: sem("type"),
    typeParameter: sem("type"), namespace: sem("namespace"), parameter: sem("parameter"), variable: sem("variable"),
    "variable.readonly": sem("constant"), property: sem("property"), keyword: sem("keyword"), string: sem("string"),
    number: sem("number"), comment: sem("comment"), "*.defaultLibrary": sem("builtin"), enumMember: sem("constant"),
  }).filter(([, v]) => v));
  return { name: t.name, type: dark ? "dark" : "light", semanticHighlighting: true, colors, tokenColors, semanticTokenColors };
}

fs.mkdirSync(out, { recursive: true });
const list = [];
for (const f of fs.readdirSync(src).filter((x) => x.endsWith(".json")).sort()) {
  const t = read(path.join(src, f));
  const id = f.replace(/\.json$/, "");
  fs.writeFileSync(path.join(out, id + ".json"), JSON.stringify(theme(t), null, 1));
  list.push({ label: t.name, uiTheme: t.type === "light" ? "vs" : "vs-dark", path: "./themes/" + id + ".json" });
}
const pkgPath = path.join(__dirname, "../package.json");
const pkg = JSON.parse(fs.readFileSync(pkgPath, "utf8"));
pkg.contributes.themes = list;
fs.writeFileSync(pkgPath, JSON.stringify(pkg, null, 2) + "\n");
console.log(list.length + " тем");
