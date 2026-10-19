-- :Plugins — магазин плагинов, как панель Extensions в VS Code: каталог awesome-neovim (~1400 плагинов по разделам)
-- с поиском; справа — описание и раздел, ● — уже стоит. enter — поставить (дописывается в "plugins" settings.jsonc,
-- ставится при перезапуске — ownvim предложит его сразу), ctrl-x — убрать, ctrl-o — открыть страницу на GitHub. Каталог кэшируется на сутки.
local settings = require("own.settings")

local M = {}

local URL = "https://raw.githubusercontent.com/rockerBOO/awesome-neovim/main/README.md"
local CACHE = vim.fn.stdpath("cache") .. "/own-awesome-neovim.md"
local DAY = 24 * 3600

local function parse(text)
  local items, section, sub = {}, "", nil
  for line in text:gmatch("[^\n]+") do
    local h2 = line:match("^## (.+)")
    local h3 = line:match("^### (.+)")
    if h2 then section, sub = h2, nil
    elseif h3 then sub = h3
    else
      local repo, desc = line:match("^%- %[([%w%-_%.]+/[%w%-_%.]+)%]%(https://github%.com/[^)]+%)%s*%-%s*(.*)$")
      if repo and section ~= "Contents" then
        items[#items + 1] = { repo = repo, desc = desc, section = sub and (section .. " › " .. sub) or section }
      end
    end
  end
  return items
end

local function fetch(done)
  local st = vim.uv.fs_stat(CACHE)
  if st and os.time() - st.mtime.sec < DAY then
    local f = assert(io.open(CACHE))
    local t = f:read("*a")
    f:close()
    return done(parse(t))
  end
  vim.notify("загружаю каталог плагинов…")
  vim.system({ "curl", "-fsSL", "-o", CACHE, URL }, {}, vim.schedule_wrap(function(r)
    if r.code ~= 0 and not st then return vim.notify("каталог не скачался: " .. (r.stderr or ""), vim.log.levels.ERROR) end
    local f = assert(io.open(CACHE))
    local t = f:read("*a")
    f:close()
    done(parse(t))
  end))
end

-- стоит ли плагин: в "plugins" settings.jsonc или среди загруженных lazy.nvim
local function installed(repo)
  local name = repo:match("/(.+)$")
  local mine = ((settings.current or {}).plugins or {})[repo]
  if mine == false then return false end
  if mine then return true end
  local ok, cfg = pcall(require, "lazy.core.config")
  return ok and cfg.plugins[name] ~= nil
end

local function set(repo, value)
  local plugins = vim.deepcopy((settings.current or {}).plugins or {})
  plugins[repo] = value
  settings.set("plugins", next(plugins) and plugins or vim.empty_dict()) -- пустой — {} в JSON, а не []
end

function M.open()
  fetch(function(items)
    for _, it in ipairs(items) do
      it.text = it.repo .. " " .. it.desc .. " " .. it.section
      it.preview = {
        text = ("# %s\n\n%s\n\nРаздел: %s\n\nhttps://github.com/%s\n\nenter — поставить · ctrl-x — убрать · ctrl-o — открыть на GitHub")
          :format(it.repo, it.desc, it.section, it.repo),
        ft = "markdown",
      }
    end
    Snacks.picker.pick({
      title = ("Плагины · %d в каталоге"):format(#items),
      items = items,
      format = function(item)
        local on = installed(item.repo)
        return {
          { on and "● " or "  ", on and "DiagnosticOk" or "Comment" },
          { item.repo, on and "DiagnosticOk" or "Normal" },
          { "  " .. item.section, "Comment" },
        }
      end,
      preview = "preview",
      confirm = function(picker, item)
        picker:close()
        if not item then return end
        if installed(item.repo) then return vim.notify(item.repo .. " уже стоит") end
        set(item.repo, true)
        -- lazy.nvim ставит недостающие плагины на старте — перезапуск и есть установка
        vim.schedule(function()
          local answer = vim.fn.confirm(("%s добавлен в settings.jsonc. Перезапустить ownvim и поставить сейчас?"):format(item.repo), "&Да\n&Позже", 1)
          if answer == 1 then vim.cmd("restart") else vim.notify("поставится при следующем запуске (:restart)") end
        end)
      end,
      actions = {
        own_remove = function(picker, item)
          if not item then return end
          picker:close()
          local mine = ((settings.current or {}).plugins or {})[item.repo]
          -- свой плагин — убрать строку; плагин модуля — выключить (false)
          if mine then set(item.repo, nil) else set(item.repo, false) end
          vim.notify(item.repo .. " убран — после :restart (:Lazy clean — удалить файлы)")
        end,
        own_browse = function(_, item)
          if item then vim.ui.open("https://github.com/" .. item.repo) end
        end,
      },
      win = {
        input = {
          keys = {
            ["<c-x>"] = { "own_remove", mode = { "n", "i" } },
            ["<c-o>"] = { "own_browse", mode = { "n", "i" } },
          },
        },
      },
    })
  end)
end

function M.setup()
  vim.api.nvim_create_user_command("Plugins", M.open, { desc = "Магазин плагинов (awesome-neovim)" })
end

return M
