local Mirror = require("neosnip.text_objects.mirror")

local _find_closing_brace
local _split_conditional
local _replace_conditional
local _CleverReplace
local TextObjectTransformation

_find_closing_brace = function(string, start_pos)
  local bracks_open = 1
  local escaped = false
  for idx = start_pos, #string do
    local char = string:sub(idx, idx)
    if char == "(" then
      if not escaped then bracks_open = bracks_open + 1 end
    elseif char == ")" then
      if not escaped then bracks_open = bracks_open - 1 end
      if bracks_open == 0 then return idx + 1 end
    end
    escaped = (char == "\\") and not escaped or false
  end
end

_split_conditional = function(string)
  local bracks_open = 0
  local args = {}
  local carg = ""
  local escaped = false
  for idx = 1, #string do
    local char = string:sub(idx, idx)
    if char == "(" then
      if not escaped then bracks_open = bracks_open + 1 end
    elseif char == ")" then
      if not escaped then bracks_open = bracks_open - 1 end
    elseif char == ":" and bracks_open == 0 and not escaped then
      table.insert(args, carg)
      carg = ""
      escaped = false
      goto continue
    end
    carg = carg .. char
    ::continue::
    escaped = (char == "\\") and not escaped or false
  end
  table.insert(args, carg)
  return args
end

_replace_conditional = function(match_subject, string)
  local _CONDITIONAL_PATTERN = "%?%((%d+)%):"
  while true do
    local s, e, group_num = string:find(_CONDITIONAL_PATTERN)
    if not s then break end
    local start = s
    local end_pos = _find_closing_brace(string, start + 4)
    local condition_text = string:sub(start + 4, end_pos - 2)
    local args = _split_conditional(condition_text)
    local rv = ""
    if tonumber(group_num) and match_subject[tonumber(group_num)] then
      local txt = args[1]
      rv = _replace_conditional(match_subject, txt:gsub("\\\\(.)", "%1"))
    elseif #args > 1 then
      local txt = args[2]
      rv = _replace_conditional(match_subject, txt:gsub("\\\\(.)", "%1"))
    end
    string = string:sub(1, start - 1) .. rv .. string:sub(end_pos)
  end
  return string
end

_CleverReplace = {}
_CleverReplace.__index = _CleverReplace

function _CleverReplace:new(expression)
  return setmetatable({ _expression = expression }, self)
end

function _CleverReplace:replace(match_subject)
  local transformed = self._expression
  local ESCAPED_BSLASH = "\x00"

  transformed = transformed:gsub("%$(%d+)", function(n)
    local g = match_subject[tonumber(n)] or ""
    return g:gsub("\\", ESCAPED_BSLASH)
  end)

  transformed = transformed:gsub("\\\\\\\\", ESCAPED_BSLASH)

  transformed = transformed:gsub("\\([ul])(.)", function(m, ch)
    if m == "u" then return ch:upper() end
    return ch:lower()
  end)

  transformed = transformed:gsub("\\([UL])(.-)\\E", function(m, text)
    if m == "U" then return text:upper() end
    return text:lower()
  end)

  transformed = _replace_conditional(match_subject, transformed)

  transformed = transformed:gsub("\\n", "\n")
  transformed = transformed:gsub("\\t", "\t")
  transformed = transformed:gsub("\\r", "\r")

  transformed = transformed:gsub(ESCAPED_BSLASH, "\\")
  transformed = transformed:gsub("\\(.)", "%1")

  return transformed
end

TextObjectTransformation = {}
TextObjectTransformation.__index = TextObjectTransformation

function TextObjectTransformation:new(token)
  local obj = {}
  obj._convert_to_ascii = false
  obj._find = nil
  obj._match_this_many = 1

  if token.search then
    local flags = ""
    if token.options then
      if token.options:find("g") then obj._match_this_many = 0 end
      if token.options:find("i") then flags = flags .. "i" end
      if token.options:find("m") then flags = flags .. "m" end
      if token.options:find("a") then obj._convert_to_ascii = true end
    end
    obj._find = { pattern = token.search, flags = flags }
    obj._replace = _CleverReplace:new(token.replace)
  end
  return setmetatable(obj, self)
end

function TextObjectTransformation:_transform(text)
  if self._convert_to_ascii then
    pcall(function()
      text = vim.fn.substitute(text, ".", "\\=iconv(submatch(0), 'utf-8', 'ascii//TRANSLIT')", "g")
    end)
  end
  if not self._find then return text end
  if not self._replace then return text end
  local r = self._replace
  local flags = self._find.flags .. (self._match_this_many == 0 and "g" or "")
  local result = vim.fn.substitute(text, self._find.pattern,
    function()
      local match = {}
      for i = 0, 9 do match[i] = vim.fn.submatch(i) end
      return r:replace(match)
    end,
    flags
  )
  return result
end

local Transformation = setmetatable({}, { __index = Mirror })
Transformation.__index = Transformation

function Transformation:new(parent, ts, token)
  local obj = Mirror.new(self, parent, ts, token)
  local trans = TextObjectTransformation:new(token)
  obj._convert_to_ascii = trans._convert_to_ascii
  obj._find = trans._find
  obj._replace = trans._replace
  return obj
end

function Transformation:_get_text()
  return self:_transform(self._ts:current_text())
end

function Transformation:_transform(text)
  if self._find then
    local r = self._replace
    local flags = self._find.flags .. (self._match_this_many == 0 and "g" or "")
    local result = vim.fn.substitute(text, self._find.pattern,
      function()
        local match = {}
        for i = 0, 9 do
          match[i] = vim.fn.submatch(i)
        end
        return r:replace(match)
      end,
      flags
    )
    return result
  end
  return text
end

return Transformation
