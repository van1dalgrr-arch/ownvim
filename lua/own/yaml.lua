-- Отступы в YAML (compose, k8s, GitHub Actions) — свои, а не treesitter: тот после «- db» ставит курсор в колонку 0.
-- Новая строка (o, O, enter) получает отступ по строке выше:
--   ports:            → на шаг глубже          - name: api   → под name (вровень с ключом элемента)
--   - "8080:8080"     → вровень с «-»          command: |    → на шаг глубже (многострочный текст)
-- Строки, где уже есть текст, не двигаются: = и набор «:» не ломают то, что выровнено руками.
local M = {}

-- текст строки без комментария в конце (# внутри кавычек не трогаем — грубо, но для отступа хватает)
local function code(line)
  if not line:find("#", 1, true) then return line end
  local out, quote = {}, nil
  for i = 1, #line do
    local ch = line:sub(i, i)
    if quote then
      if ch == quote then quote = nil end
    elseif ch == '"' or ch == "'" then
      quote = ch
    elseif ch == "#" and (i == 1 or line:sub(i - 1, i - 1):match("%s")) then
      break
    end
    out[#out + 1] = ch
  end
  return table.concat(out)
end

function M.indent(lnum)
  lnum = lnum or vim.v.lnum
  if vim.fn.getline(lnum):match("%S") then return -1 end -- строка с текстом — оставить как есть
  local prev = vim.fn.prevnonblank(lnum - 1)
  if prev == 0 then return 0 end
  local pi = vim.fn.indent(prev)
  local line = vim.fn.getline(prev)
  if line:match("^%s*#") then return pi end
  local text = code(line):gsub("%s+$", "")
  local sw = vim.fn.shiftwidth()
  local dash = text:match("^%s*%-%s+()") -- «- …»: колонка, где начинается содержимое элемента
  local opens = text:match(":$") or text:match(":%s*[|>][-+%d]*$") or text:match("[%[{]$")
  if opens then return (dash and dash - 1 or pi) + sw end
  if dash and text:match("^%s*%-%s+[^%s:]+:%s") then return dash - 1 end -- «- name: api» → дальше ключи элемента
  return pi
end

function M.attach(buf)
  vim.bo[buf].indentexpr = "v:lua.require'own.yaml'.indent()"
  vim.bo[buf].indentkeys = "!^F,o,O"
  vim.bo[buf].autoindent = true
  vim.bo[buf].expandtab = true -- табы в YAML запрещены
  vim.bo[buf].shiftwidth = 2
  vim.bo[buf].tabstop = 2
end

return M
