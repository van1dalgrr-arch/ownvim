// Сниппеты ownvim (snippets/*.json — уже в формате VS Code) → в расширение
const fs = require("fs");
const path = require("path");
const src = path.join(__dirname, "../../../snippets"), out = path.join(__dirname, "../snippets");
fs.mkdirSync(out, { recursive: true });
for (const f of fs.readdirSync(src).filter((x) => x.endsWith(".json"))) fs.copyFileSync(path.join(src, f), path.join(out, f));
