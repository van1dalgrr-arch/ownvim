-- Русская раскладка не мешает: «о» = j, «л» = k, «вв» = dd, «Ж» = : — переключать язык ради hjkl и :w
-- не нужно. В режиме вставки буквы печатаются как есть. alt-буквы (alt-щ = alt-o) дублируются
-- в разделе keys сами: langmap на сочетания с alt не действует.
-- Настройки: "langmap": false — без раскладки для команд; "alt_keys": false — без дублей alt.
local M = {}

-- строчные написаны явно: string.lower в Lua понимает только латиницу
local RU, ru = [[ФИСВУАПРШОЛДЬТЩЗЙКЫЕГМЦЧНЯ]], [[фисвуапршолдьтщзйкыегмцчня]]
local EN, en = [[ABCDEFGHIJKLMNOPQRSTUVWXYZ]], [[abcdefghijklmnopqrstuvwxyz]]
local LANGMAP = RU .. ";" .. EN .. "," .. ru .. ";" .. en .. [[,Х{,х[,Ъ},ъ],Ж:,ж\;,Э",э',Б<,б\,,Ю>,ю.,ё`,Ё~]]

function M.setup(opts) M.reload(opts) end

function M.reload(opts)
  vim.o.langmap = opts.langmap == false and "" or LANGMAP
end

return M
