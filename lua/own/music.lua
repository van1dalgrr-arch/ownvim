-- Музыка в статусной строке: « Трек — Исполнитель» из «Сейчас играет» macOS — Яндекс Музыка (приложение или
-- music.yandex.ru в браузере), Apple Music, Spotify — что играет. Клик — пауза, правый клик — следующий трек,
-- средний — предыдущий. Пауза — блок бледный, ничего не играет — блока нет.
-- Читает media-control (brew install media-control): один процесс в фоне присылает изменения сам, без опроса.
-- Раздел "statusline": { "music": { "apps": ["ru.yandex.desktop.music"], "max": 40, "paused": true } }
--   apps — только эти приложения (bundle id; [] — любое), max — длиннее — обрезать с «…», paused — показывать на паузе
local settings = require("own.settings")

local M = {}

local function o() return ((settings.current or {}).statusline or {}).music or {} end

local now = {} -- последнее, что прислал media-control: title, artist, playing, bundleIdentifier…
local proc, restarts = nil, 0

local function start()
  if proc or restarts > 3 or vim.fn.executable("media-control") == 0 then return end
  local rest = ""
  local ok, p = pcall(vim.system, { "media-control", "stream", "--no-diff", "--no-artwork", "--debounce=150" }, {
    text = true,
    stdout = function(_, data)
      if not data then return end
      rest = rest .. data
      for line in rest:gmatch("([^\n]*)\n") do
        local okj, msg = pcall(vim.json.decode, line)
        if okj and type(msg) == "table" and msg.type == "data" then
          now = type(msg.payload) == "table" and msg.payload or {}
          vim.schedule(function() vim.cmd("redrawstatus") end)
        end
      end
      rest = rest:match("[^\n]*$")
    end,
  }, function()
    -- процесс упал (например, после сна Mac) — поднять заново, но не крутиться бесконечно
    proc, now = nil, {}
    restarts = restarts + 1
    vim.defer_fn(start, 2000)
  end)
  if ok then proc = p end
end

local function allowed()
  local apps = o().apps or {}
  if #apps == 0 then return true end
  local id = now.bundleIdentifier or ""
  local parent = now.parentApplicationBundleIdentifier or ""
  return vim.tbl_contains(apps, id) or vim.tbl_contains(apps, parent)
end

local function cut(s, n)
  if vim.fn.strchars(s) <= n then return s end
  return vim.fn.strcharpart(s, 0, n - 1) .. "…"
end

--- текст блока (без %-кодов) и играет ли сейчас; nil — показывать нечего
function M.text()
  start()
  local title = now.title
  if not title or title == "" or not allowed() then return nil end
  local playing = now.playing == true
  if not playing and o().paused == false then return nil end
  local artist = now.artist ~= "" and now.artist or nil
  local s = cut(artist and (title .. " — " .. artist) or title, o().max or 40)
  return (playing and "\u{f075a} " or "\u{f03e4} ") .. s, playing
end

_G.OwnMusicClick = function(_, _, button)
  local cmd = ({ l = "toggle-play-pause", r = "next-track", m = "previous-track" })[button]
  if cmd then vim.system({ "media-control", cmd }) end
end

function M.stop()
  if proc then
    restarts = math.huge -- выходим сами — не поднимать
    pcall(function() proc:kill(15) end)
  end
end

vim.api.nvim_create_autocmd("VimLeavePre", { group = vim.api.nvim_create_augroup("own.music", { clear = true }), callback = M.stop })

return M
