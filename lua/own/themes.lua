-- Выбор темы с предпросмотром: alt-s (или пробел u C). Курсор по списку — весь редактор сразу в этой теме,
-- справа под списком — твой же код; enter — применить и запомнить (nvim стартует с ней), esc — вернуть как было.
-- Запомненная тема лежит в ~/.local/state/ownvim/colorscheme; по умолчанию — tokyonight.
-- В settings.jsonc "theme" с именем темы важнее запомненной; "auto" — запомненная.
local M = {}

local DEFAULT = "tokyonight"
local file = vim.fn.stdpath("state") .. "/colorscheme"

function M.saved()
  local f = io.open(file)
  if not f then return nil end
  local name = vim.trim(f:read("*l") or "")
  f:close()
  return name ~= "" and name or nil
end

-- при старте: запомненная тема, а если её плагин удалили — tokyonight
function M.load()
  local name = M.saved() or DEFAULT
  if not pcall(vim.cmd.colorscheme, name) then vim.cmd.colorscheme(DEFAULT) end
end

-- кусок кода для предпросмотра, когда открыт не файл (стартовый экран, дерево)
local function sample()
  local path = vim.fn.stdpath("cache") .. "/theme-sample.go"
  if not vim.uv.fs_stat(path) then
    vim.fn.writefile({
      "// Package api — пример для предпросмотра темы.",
      "package api",
      "",
      'import (',
      '\t"context"',
      '\t"fmt"',
      '\t"net/http"',
      ')',
      "",
      "// User — строка таблицы users.",
      "type User struct {",
      '\tID    int64  `json:"id"`',
      '\tEmail string `json:"email"`',
      "}",
      "",
      "const maxUsers = 100",
      "",
      "func (h *Handler) Get(ctx context.Context, id int64) (*User, error) {",
      '\trow := h.db.QueryRowContext(ctx, `SELECT id, email FROM users WHERE id = $1`, id)',
      "\tvar u User",
      "\tif err := row.Scan(&u.ID, &u.Email); err != nil {",
      '\t\treturn nil, fmt.Errorf("get user %d: %w", id, err)',
      "\t}",
      "\tif u.ID > maxUsers || u.Email == \"\" {",
      "\t\treturn nil, http.ErrNoLocation // TODO: своя ошибка",
      "\t}",
      "\treturn &u, nil",
      "}",
    }, path)
  end
  return { file = path, pos = { 18, 0 } }
end

function M.pick()
  local cur = vim.api.nvim_buf_get_name(0)
  local show = (vim.bo.buftype == "" and cur ~= "" and vim.uv.fs_stat(cur))
      and { file = cur, pos = vim.api.nvim_win_get_cursor(0) }
    or sample()
  local runtime = vim.fs.normalize(vim.env.VIMRUNTIME)
  -- kanagawa-dragon и др. называют себя просто «kanagawa» — тогда текущая та, что запомнена
  local saved = M.saved()
  local active = (saved and vim.g.colors_name and vim.startswith(saved, vim.g.colors_name)) and saved or vim.g.colors_name

  Snacks.picker.pick({
    title = "Тема · enter — применить и запомнить · esc — вернуть",
    finder = function()
      local items = {}
      for _, it in ipairs(require("snacks.picker.source.vim").colorschemes()) do
        -- встроенные темы vim (blue, desert, morning…) не нужны
        if not vim.fs.normalize(it.file):find(runtime, 1, true) then items[#items + 1] = it end
      end
      table.sort(items, function(a, b) return a.text < b.text end)
      return items
    end,
    format = function(item)
      local on = item.text == active
      return { { on and "● " or "  ", "Special" }, { item.text, on and "Special" or "Normal" } }
    end,
    -- предпросмотр: тема на весь редактор, в окне — твой код в ней
    preview = function(ctx)
      local state = ctx.preview.state
      if not state.colorscheme then
        state.colorscheme = active or DEFAULT
        state.background = vim.o.background
        ctx.preview.win:on("WinClosed", function()
          vim.schedule(function()
            if not state.colorscheme then return end -- выбрали enter — возвращать нечего
            pcall(vim.cmd.colorscheme, state.colorscheme)
            vim.o.background = state.background
          end)
        end, { win = true })
      end
      local name = ctx.item.text
      vim.schedule(function() pcall(vim.cmd.colorscheme, name) end)
      local item = ctx.item
      ctx.item = vim.tbl_extend("force", {}, item, show)
      Snacks.picker.preview.file(ctx)
      ctx.item = item
    end,
    -- список справа, под ним код: редактор за ним виден целиком (без затемнения)
    layout = {
      layout = {
        backdrop = false,
        position = "right",
        width = 0.42,
        min_width = 60,
        height = 0.9,
        border = "none",
        box = "vertical",
        { win = "input", height = 1, border = "rounded", title = "{title}", title_pos = "center" },
        { win = "list", height = 0.35, border = "rounded" },
        { win = "preview", border = "rounded", title = "{preview}" },
      },
    },
    on_show = function(picker)
      -- курсор сразу на текущей теме
      for i, it in ipairs(picker:items()) do
        if it.text == active then return picker.list:view(i) end
      end
    end,
    confirm = function(picker, item)
      picker.preview.state.colorscheme = nil
      picker:close()
      if not item then return end
      vim.schedule(function()
        vim.cmd.colorscheme(item.text)
        vim.fn.mkdir(vim.fn.fnamemodify(file, ":h"), "p")
        vim.fn.writefile({ item.text }, file)
        vim.notify("тема: " .. item.text .. " — запомнил, nvim будет стартовать с ней")
      end)
    end,
  })
end

return M
