local parser = require("neosnip.parser")
local SnippetInstance = require("neosnip.text_objects.snippet_instance")
local Position = require("neosnip.position")

local SnippetDefinition = {}
SnippetDefinition.__index = SnippetDefinition

function SnippetDefinition:new(priority, trigger, value, description, options, globals, location, context, actions)
  local obj = {
    _priority = tonumber(priority) or 0,
    _trigger = trigger,
    _value = value,
    _description = description or "",
    _opts = options or "",
    _matched = "",
    _last_re = nil,
    _globals = globals or {},
    _compiled_globals = nil,
    _location = location or "",
    _context_code = context,
    _context = nil,
    _actions = actions or {},
  }
  setmetatable(obj, self)
  obj:matches(obj._trigger)
  return obj
end

function SnippetDefinition:_words_for_line(trigger, before, num_words)
  if not num_words then
    num_words = #vim.split(trigger, "%s+")
  end
  local word_list = vim.split(before, "%s+")
  if #word_list <= num_words then
    return vim.trim(before or "")
  end
  local before_words = before
  for i = 1, num_words do
    local w = word_list[#word_list - i + 1]
    local left = before_words:sub(1, before_words:len() - w:len())
    left = left:gsub("%s+$", "")
    before_words = left
  end
  return before:sub(#before_words + 1):match("^%s*(.-)%s*$") or ""
end

function SnippetDefinition:has_option(opt)
  return self._opts:find(opt) ~= nil
end

function SnippetDefinition:description()
  return ("(%s) %s"):format(self._trigger, self._description):gsub("%s+$", "")
end

function SnippetDefinition:priority()
  return self._priority
end

function SnippetDefinition:trigger()
  return self._trigger
end

function SnippetDefinition:matched()
  return self._matched
end

function SnippetDefinition:location()
  return self._location
end

function SnippetDefinition:context()
  return self._context
end

function SnippetDefinition:matches(before, visual_content)
  self._matched = ""
  local words = self:_words_for_line(self._trigger, before)

  local match = false
  if self:has_option("r") then
    -- regex trigger
    local ok, result = pcall(function()
      return { vim.fn.matchstr(before, self._trigger) }
    end)
    if ok and result[1] ~= "" then
      match = true
      self._matched = result[1]
    end
  elseif self:has_option("w") then
    local words_len = #self._trigger
    local words_suffix = words:sub(-words_len)
    match = words_suffix == self._trigger
  elseif self:has_option("i") then
    match = words:sub(-#self._trigger) == self._trigger
  else
    match = words == self._trigger
  end

  if match and self._matched == "" then
    self._matched = self._trigger
  end

  if self:has_option("b") and match then
    local text_before = before:gsub("%s+$", "")
    text_before = text_before:sub(1, -#self._matched - 1)
    if text_before and text_before:match("%S") then
      self._matched = ""
      return false
    end
  end

  self._context = nil
  if match and self._context_code then
    local ctx_match = self:_context_match(visual_content, before)
    if not ctx_match then match = false end
  end

  return match
end

function SnippetDefinition:_context_match(visual_content, before)
  -- Simplified context matching using VimL eval
  local context_code = self._context_code
  if context_code then
    local ok, result = pcall(vim.fn.eval, context_code)
    if ok and result then
      self._context = result
      return result
    end
  end
  return true
end

function SnippetDefinition:could_match(before)
  self._matched = ""

  if before and before:match("^%s+$") then
    before = ""
  end
  if before and before:match("%S") ~= before then
    return false
  end

  local words = self:_words_for_line(self._trigger, before)

  local match = false
  if self:has_option("r") then
    local ok, result = pcall(function()
      return { vim.fn.matchstr(before, self._trigger) }
    end)
    if ok and result[1] ~= "" then match = true end
  elseif self:has_option("w") then
    local words_suffix = words
    match = self._trigger:find("^" .. vim.pesc(words_suffix)) == 1
    self._matched = words_suffix
  elseif self:has_option("i") then
    for i = 1, #words do
      local suffix = words:sub(i)
      if self._trigger:find("^" .. vim.pesc(suffix)) == 1 then
        match = true
        self._matched = suffix
        break
      end
    end
  else
    match = self._trigger:find("^" .. vim.pesc(words)) == 1
  end

  if match and self._matched == "" then
    self._matched = words
  end

  if self:has_option("b") and match then
    local text_before = before:gsub("%s+$", "")
    text_before = text_before:sub(1, -#self._matched - 1)
    if text_before and text_before:match("%S") then
      self._matched = ""
      return false
    end
  end

  return match
end

function SnippetDefinition:do_pre_expand(visual_content, snippets_stack)
  if self._actions.pre_expand then
    local ok, snip = pcall(vim.fn.eval, self._actions.pre_expand)
    return ok and true or false
  end
  return false
end

function SnippetDefinition:do_post_expand(start_pos, end_pos, snippets_stack)
  if self._actions.post_expand then
    pcall(vim.fn.eval, self._actions.post_expand)
  end
end

function SnippetDefinition:do_post_finish(snippet_instance)
  if self._actions.post_finish then
    pcall(vim.fn.eval, self._actions.post_finish)
  end
end

function SnippetDefinition:do_post_jump(tabstop_number, jump_direction, snippets_stack, current_snippet)
  if self._actions.post_jump then
    pcall(vim.fn.eval, self._actions.post_jump)
  end
end

function SnippetDefinition:launch(text_before, visual_content, parent, start_pos, end_pos)
  local indent_match = text_before:match("^[ \t]*") or ""
  local lines = {}
  for line in (self._value .. "\n"):gmatch("([^\n]*)\n?") do
    table.insert(lines, line)
  end

  local ind_util = { shiftwidth = vim.fn.shiftwidth() }

  local initial_text = {}
  for line_num, line in ipairs(lines) do
    local tabs = 0
    if not self:has_option("t") then
      tabs = line:match("^\t*"):len()
    end
    local line_ind = string.rep(" ", tabs * ind_util.shiftwidth)
    if line_num ~= 1 then
      line_ind = indent_match .. line_ind
    end
    local result_line = line_ind .. line:sub(tabs + 1)
    if self:has_option("m") then
      result_line = result_line:gsub("%s+$", "")
    end
    table.insert(initial_text, result_line)
  end

  local text = table.concat(initial_text, "\n")
  text = text:gsub("\n$", "")

  local snippet_instance = SnippetInstance:new(
    self, parent, text,
    start_pos, end_pos,
    visual_content,
    self._last_re,
    self._globals,
    self._context,
    self._compiled_globals
  )

  self:instantiate(snippet_instance, text, indent_match)
  snippet_instance:replace_initial_text(vim.api.nvim_buf_get_lines)

  for _ = 1, 10 do
    snippet_instance:update_textobjects(vim.api.nvim_buf_get_lines)
    local cur_text = snippet_instance:current_text()
    -- simplified convergence check
  end

  return snippet_instance
end

function SnippetDefinition:instantiate(snippet_instance, initial_text, indent)
  parser.parse_neosnip(snippet_instance, initial_text, indent)
end

local NeoSnipSnippetDefinition = setmetatable({}, { __index = SnippetDefinition })
NeoSnipSnippetDefinition.__index = NeoSnipSnippetDefinition

function NeoSnipSnippetDefinition:new(...)
  local obj = SnippetDefinition:new(...)
  setmetatable(obj, self)
  return obj
end

function NeoSnipSnippetDefinition:instantiate(snippet_instance, initial_text, indent)
  parser.parse_neosnip(snippet_instance, initial_text, indent)
end

local SnipMateSnippetDefinition = setmetatable({}, { __index = SnippetDefinition })
SnipMateSnippetDefinition.__index = SnipMateSnippetDefinition

SnipMateSnippetDefinition.SNIPMATE_PRIORITY = -1000

function SnipMateSnippetDefinition:new(trigger, value, description, location)
  local obj = SnippetDefinition:new(
    self.SNIPMATE_PRIORITY, trigger, value, description,
    "w", {}, location, nil, {}
  )
  setmetatable(obj, self)
  return obj
end

function SnipMateSnippetDefinition:instantiate(snippet_instance, initial_text, indent)
  parser.parse_snipmate(snippet_instance, initial_text, indent)
end

return {
  SnippetDefinition = SnippetDefinition,
  NeoSnipSnippetDefinition = NeoSnipSnippetDefinition,
  SnipMateSnippetDefinition = SnipMateSnippetDefinition,
}
