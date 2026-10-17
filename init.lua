-- ownvim: своя сборка Neovim без LazyVim. Запуск — ownvim (NVIM_APPNAME=ownvim nvim).
-- Всё настраивается в settings.jsonc; умолчания с объяснениями — defaults.jsonc. Код — lua/own/.
vim.loader.enable()
require("own").setup()
