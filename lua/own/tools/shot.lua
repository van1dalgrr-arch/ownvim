-- Красивый скриншот кода: выделил → пробел P → PNG в окне с тенью, в цветах текущей темы, с номерами строк.
-- Картинка сразу в буфере обмена (⌘V в Telegram) и в ~/Pictures/code. Без выделения — функция под курсором.
-- Рисует freeze (charmbracelet); темы — те же, что в nvim, а если у freeze такой нет — ближайшая.
local M = {}

-- темы, которые freeze знает под тем же именем
local same = {}
for _, n in ipairs({
  "tokyonight-night", "tokyonight-moon", "tokyonight-storm", "tokyonight-day", "rose-pine", "rose-pine-moon",
  "rose-pine-dawn", "catppuccin-mocha", "catppuccin-macchiato", "catppuccin-frappe", "catppuccin-latte",
  "gruvbox", "gruvbox-light", "nord", "dracula",
}) do same[n] = true end

local function theme()
  local name = vim.g.colors_name or ""
  if same[name] then return name end
  local light = vim.o.background == "light"
  if name:match("^tokyonight") then return light and "tokyonight-day" or "tokyonight-night" end
  if name:match("^rose%-pine") then return light and "rose-pine-dawn" or "rose-pine" end
  if name:match("^catppuccin") then return light and "catppuccin-latte" or "catppuccin-mocha" end
  if name:match("^gruvbox") then return light and "gruvbox-light" or "gruvbox" end
  return light and "tokyonight-day" or "tokyonight-night" -- kanagawa, nightfox, vesper… — у freeze их нет
end

-- функция или метод под курсором (treesitter), иначе весь файл
local function current_function()
  local ok, node = pcall(vim.treesitter.get_node)
  while ok and node do
    local t = node:type()
    if t:match("function") or t:match("method") then
      local s, _, e = node:range()
      return s + 1, e + 1
    end
    node = node:parent()
  end
  return 1, vim.api.nvim_buf_line_count(0)
end

function M.shot(l1, l2)
  if vim.fn.executable("freeze") == 0 then
    return vim.notify("нужен freeze: brew install charmbracelet/tap/freeze", vim.log.levels.ERROR)
  end
  if not l1 then l1, l2 = current_function() end
  local name = vim.fn.expand("%:t")
  if name == "" then name = "code." .. (vim.bo.filetype ~= "" and vim.bo.filetype or "txt") end
  -- рисуем то, что в буфере (даже несохранённое); имя файла — чтобы freeze понял язык
  local tmp = vim.fn.stdpath("cache") .. "/shot/" .. name
  vim.fn.mkdir(vim.fs.dirname(tmp), "p")
  vim.fn.writefile(vim.api.nvim_buf_get_lines(0, 0, -1, false), tmp)
  local out = vim.fn.expand("~/Pictures/code/") .. vim.fn.fnamemodify(name, ":r") .. os.date("-%Y%m%d-%H%M%S") .. ".png"
  vim.fn.mkdir(vim.fs.dirname(out), "p")
  vim.system({
    "freeze", tmp, "--lines", l1 .. "," .. l2, "--theme", theme(),
    "--window", "--show-line-numbers", "--font.family", "JetBrainsMono Nerd Font", "--font.size", "14",
    "--border.radius", "10", "--shadow.blur", "20", "--shadow.y", "8", "--padding", "20,28", "--margin", "32",
    "-o", out,
  }, { text = true }, vim.schedule_wrap(function(res)
    if res.code ~= 0 then return vim.notify("freeze: " .. (res.stderr or ""), vim.log.levels.ERROR) end
    -- PNG в буфер обмена macOS: ⌘V вставит картинку
    vim.system({ "osascript", "-e", ('set the clipboard to (read (POSIX file "%s") as «class PNGf»)'):format(out) })
    vim.notify(("строки %d–%d → картинка в буфере обмена (⌘V)\n%s"):format(l1, l2, out:gsub(vim.env.HOME, "~")), vim.log.levels.INFO, { title = "скриншот кода" })
  end))
end

return M
