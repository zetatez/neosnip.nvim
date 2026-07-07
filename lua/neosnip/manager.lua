local snippet_mod = require("neosnip.snippet")
local source_mod = require("neosnip.source")
local Position = require("neosnip.position")
local change_mod = require("neosnip.change")
local VimState = require("neosnip.vim_state").VimState

local M = {}

local function get_buf()
  local lines = vim.api.nvim_buf_get_lines(0, 0, -1, false)
  return lines
end

local function set_lines(start_line, end_line, lines)
  vim.api.nvim_buf_set_lines(0, start_line, end_line, false, lines)
end

local function get_line_till_cursor()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local line = vim.api.nvim_buf_get_lines(0, cursor[1] - 1, cursor[1], false)[1] or ""
  return line:sub(1, cursor[2])
end

local function buf_cursor()
  local c = vim.api.nvim_win_get_cursor(0)
  return Position:new(c[1] - 1, c[2])
end

local function set_buf_cursor(pos)
  local buf_lines = vim.api.nvim_buf_line_count(0)
  if buf_lines == 0 then return end
  local line = pos.line + 1
  if line < 1 then line = 1 end
  if line > buf_lines then line = buf_lines end
  local col = pos.col
  if col < 0 then col = 0 end
  vim.api.nvim_win_set_cursor(0, { line, col })
end

local function get_buffer_filetypes()
  local ft = vim.bo.filetype or ""
  local fts = {}
  for s in ft:gmatch("[^.]+") do
    table.insert(fts, s)
  end
  table.insert(fts, "all")
  return fts
end

local function ask_user(items, formatted)
  if #items == 0 then return nil end
  local ok, rv = pcall(vim.fn.inputlist, formatted)
  if not ok or rv == nil or rv == 0 then return nil end
  rv = tonumber(rv)
  if not rv or rv < 1 or rv > #items then return nil end
  return items[rv]
end

local function ask_snippets(snippets)
  local display = {}
  for i, s in ipairs(snippets) do
    table.insert(display, string.format("%d: %s (%s)", i, s:description(), s:location()))
  end
  return ask_user(snippets, display)
end

local function show_warning(msg)
  vim.cmd("echohl WarningMsg")
  vim.cmd('echom "' .. msg:gsub('"', '\\"') .. '"')
  vim.cmd("echohl None")
end

local SnippetManager = {}
SnippetManager.__index = SnippetManager

function SnippetManager:new()
  local obj = {
    _active_snippets = {},
    _added_buffer_filetypes = {},
    _removed_buffer_filetypes = {},
    _autotrigger = vim.g.NeoSnipAutoTrigger or 1,
    _last_change = { "", Position:new(-1, -1) },
    _inner_state_up = false,
    _snippet_buffer_number = nil,
    _snippet_sources = {},
    _ctab = nil,
    _ignore_movements = false,
    _should_update_textobjects = false,
    _should_reset_visual = false,
    _snip_expanded_in_action = false,
    _inside_action = false,
    _visual_content = { mode = "", text = "", placeholder = nil },
    _change_provider = nil,
    _vstate = nil,
    _last_failure_key = nil,
  }
  setmetatable(obj, self)

  obj._added_snippets_source = source_mod.AddedSnippetsSource:new()
  obj:register_source("neosnip_files", source_mod.NeoSnipFileSource:new())
  obj:register_source("added", obj._added_snippets_source)

  if vim.g.NeoSnipEnableSnipMate ~= 0 then
    obj:register_source("snipmate_files", source_mod.SnipMateFileSource:new())
  end

  return obj
end

function SnippetManager:register_source(name, source)
  table.insert(self._snippet_sources, { name, source })
end

function SnippetManager:unregister_source(name)
  for i, pair in ipairs(self._snippet_sources) do
    if pair[1] == name then
      table.remove(self._snippet_sources, i)
      break
    end
  end
end

function SnippetManager:get_buffer_filetypes()
  local bufnr = vim.api.nvim_get_current_buf()
  local removed = self._removed_buffer_filetypes[bufnr] or {}
  local added = self._added_buffer_filetypes[bufnr] or {}
  local fts = {}
  for _, ft in ipairs(added) do table.insert(fts, ft) end
  for _, ft in ipairs(get_buffer_filetypes()) do table.insert(fts, ft) end
  local result = {}
  for _, ft in ipairs(fts) do
    if not removed[ft] then table.insert(result, ft) end
  end
  return result
end

function SnippetManager:add_buffer_filetypes(filetypes)
  local bufnr = vim.api.nvim_get_current_buf()
  if not self._added_buffer_filetypes[bufnr] then
    self._added_buffer_filetypes[bufnr] = {}
  end
  if not self._removed_buffer_filetypes[bufnr] then
    self._removed_buffer_filetypes[bufnr] = {}
  end
  local fts = self._added_buffer_filetypes[bufnr]
  local removed = self._removed_buffer_filetypes[bufnr]
  for ft in filetypes:gmatch("[^.]+") do
    ft = ft:match("^%s*(.-)%s*$") or ft
    if ft ~= "" then
      removed[ft] = nil
      local found = false
      for _, v in ipairs(fts) do if v == ft then found = true; break end end
      if not found then table.insert(fts, ft) end
    end
  end
end

function SnippetManager:remove_buffer_filetypes(filetypes)
  local bufnr = vim.api.nvim_get_current_buf()
  if not self._added_buffer_filetypes[bufnr] then
    self._added_buffer_filetypes[bufnr] = {}
  end
  if not self._removed_buffer_filetypes[bufnr] then
    self._removed_buffer_filetypes[bufnr] = {}
  end
  local removed = self._removed_buffer_filetypes[bufnr]
  local fts = self._added_buffer_filetypes[bufnr]
  for ft in filetypes:gmatch("[^.]+") do
    ft = ft:match("^%s*(.-)%s*$") or ft
    if ft ~= "" then
      removed[ft] = true
      for i, v in ipairs(fts) do
        if v == ft then table.remove(fts, i); break end
      end
    end
  end
end

function SnippetManager:expand()
  vim.g.neosnip_expand_res = 1
  if not self:_try_expand() then
    vim.g.neosnip_expand_res = 0
    self:_handle_failure(vim.g.NeoSnipExpandTrigger or "<tab>", true)
  end
end

function SnippetManager:expand_or_jump()
  vim.g.neosnip_expand_or_jump_res = 1
  local rv = self:_try_expand()
  if not rv then
    vim.g.neosnip_expand_or_jump_res = 2
    rv = self:_jump("FORWARD")
  end
  if not rv then
    vim.g.neosnip_expand_or_jump_res = 0
    self:_handle_failure(vim.g.NeoSnipExpandTrigger or "<tab>", true)
  end
end

function SnippetManager:jump_forwards()
  vim.g.neosnip_jump_forwards_res = 1
  vim.cmd("let &g:undolevels = &g:undolevels")
  if not self:_jump("FORWARD") then
    vim.g.neosnip_jump_forwards_res = 0
    self:_handle_failure(vim.g.NeoSnipJumpForwardTrigger or "<c-j>")
  end
end

function SnippetManager:jump_backwards()
  vim.g.neosnip_jump_backwards_res = 1
  vim.cmd("let &g:undolevels = &g:undolevels")
  if not self:_jump("BACKWARD") then
    vim.g.neosnip_jump_backwards_res = 0
    self:_handle_failure(vim.g.NeoSnipJumpBackwardTrigger or "<c-k>")
  end
end

function SnippetManager:_current_snippet()
  if #self._active_snippets == 0 then return nil end
  return self._active_snippets[#self._active_snippets]
end

function SnippetManager:_snips(before, partial, autotrigger_only)
  local filetypes = {}
  for _, ft in ipairs(self:get_buffer_filetypes()) do
    table.insert(filetypes, ft)
  end
  -- reverse
  local rev = {}
  for i = #filetypes, 1, -1 do table.insert(rev, filetypes[i]) end
  filetypes = rev

  for _, pair in ipairs(self._snippet_sources) do
    pair[2]:ensure(filetypes)
  end

  local clear_priority = nil
  local cleared = {}
  for _, pair in ipairs(self._snippet_sources) do
    local scp = pair[2]:get_clear_priority(filetypes)
    if scp and (not clear_priority or scp > clear_priority) then
      clear_priority = scp
    end
    for key, value in pairs(pair[2]:get_cleared(filetypes)) do
      if not cleared[key] or value > cleared[key] then
        cleared[key] = value
      end
    end
  end

  local matching = {}
  for _, pair in ipairs(self._snippet_sources) do
    local snips = pair[2]:get_snippets(filetypes, before, partial, autotrigger_only, self._visual_content)
    for _, s in ipairs(snips) do
      local ok = true
      if clear_priority and s:priority() <= clear_priority then ok = false end
      if cleared[s:trigger()] and s:priority() <= cleared[s:trigger()] then ok = false end
      if ok then
        if not matching[s:trigger()] then matching[s:trigger()] = {} end
        table.insert(matching[s:trigger()], s)
      end
    end
  end

  local snippets = {}
  for _, snips in pairs(matching) do
    local maxp = snips[1]:priority()
    for _, s in ipairs(snips) do
      if s:priority() > maxp then maxp = s:priority() end
    end
    for _, s in ipairs(snips) do
      if s:priority() == maxp then table.insert(snippets, s) end
    end
  end

  if partial then return snippets end

  if #snippets == 0 then return snippets end
  local maxp = snippets[1]:priority()
  for _, s in ipairs(snippets) do
    if s:priority() > maxp then maxp = s:priority() end
  end
  local result = {}
  for _, s in ipairs(snippets) do
    if s:priority() == maxp then table.insert(result, s) end
  end
  return result
end

function SnippetManager:_try_expand(autotrigger_only)
  if #self._active_snippets > 0 then
    self:_cursor_moved()
  end

  local before = get_line_till_cursor()
  local snippets = self:_snips(before, false, autotrigger_only)

  if #snippets == 0 then return false end

  local with_context = {}
  for _, s in ipairs(snippets) do
    if s.context then table.insert(with_context, s) end
  end
  if #with_context > 0 then snippets = with_context end

  vim.cmd("let &g:undolevels = &g:undolevels")

  local snippet
  if #snippets == 1 then
    snippet = snippets[1]
  else
    snippet = ask_snippets(snippets)
    if not snippet then return true end
  end

  self:_do_snippet(snippet, before)
  vim.cmd("let &g:undolevels = &g:undolevels")
  return true
end

function SnippetManager:_do_snippet(snippet, before)
  self:_setup_inner_state()
  self._snip_expanded_in_action = false
  self._should_update_textobjects = false

  local text_before = before
  if snippet:matched() ~= "" and snippet:matched() ~= snippet:trigger() then
    text_before = before:sub(1, -#snippet:matched() - 1)
  elseif snippet:matched() == snippet:trigger() then
    text_before = before:sub(1, -#snippet:matched() - 1)
  end

  local cursor_pos = buf_cursor()
  local start_pos = Position:new(cursor_pos.line, #text_before)
  local end_pos = Position:new(cursor_pos.line, #before)

  local parent = nil
  if self:_current_snippet() then
    -- Handle trigger overlapping with parent text objects
    local edit_actions = {
      { "D", start_pos.line, start_pos.col, snippet:matched() },
      { "I", start_pos.line, start_pos.col, snippet:matched() },
    }
    self._active_snippets[1]:replay_user_edits(edit_actions)
    parent = self:_current_snippet():find_parent_for_new_to(start_pos)
  end

  local snippet_instance = snippet:launch(
    text_before, self._visual_content, parent, start_pos, end_pos
  )

  vim.cmd("normal! zv")
  self._visual_content = { mode = "", text = "", placeholder = nil }
  table.insert(self._active_snippets, snippet_instance)

  -- Park cursor at snippet end
  set_buf_cursor(Position:new(snippet_instance._end.line, snippet_instance._end.col))

  snippet:do_post_expand(snippet_instance._start, snippet_instance._end, self._active_snippets)

  if self._vstate then
    self._vstate:remember_buffer(snippet_instance)
  end

  -- Jump to first tabstop
  self:_jump("FORWARD")
end

function SnippetManager:_cursor_moved()
  self._should_update_textobjects = false

  if self._ignore_movements then
    self._ignore_movements = false
    return
  end

  if #self._active_snippets == 0 then return end

  local cur_buf = vim.api.nvim_get_current_buf()
  if cur_buf ~= self._snippet_buffer_number then
    self:_leaving_buffer()
    return
  end

  local snip = self:_current_snippet()
  if not snip then return end

  -- Consume edits from change provider
  if self._change_provider and self._vstate then
    local buf = vim.api.nvim_buf_get_lines(0, 0, -1, false)
    local edits = self._change_provider:consume_edits(buf, snip, self._vstate)
    if edits == change_mod.DROP_SNIPPET then
      self:_current_snippet_done()
      return
    end
    if edits and #edits > 0 then
      -- Replay edits and update text objects
      snip:replay_user_edits(edits, self._ctab)
      snip:update_textobjects(nil, self._ctab)
    else
      -- No edits, just update text objects
      snip:update_textobjects(nil, self._ctab)
    end
    -- Remember buffer state for next comparison
    self._vstate:remember_buffer(snip)
  end

  self:_check_if_still_inside()
end

function SnippetManager:_check_if_still_inside()
  if not self:_current_snippet() then return end
  local cursor = buf_cursor()
  local snip = self:_current_snippet()
  if not (snip._start <= cursor and cursor <= snip._end) then
    self:_current_snippet_done()
  end
end

function SnippetManager:_current_snippet_done()
  if #self._active_snippets == 0 then return end
  local si = self._active_snippets[#self._active_snippets]
  si.snippet:do_post_finish(si)
  table.remove(self._active_snippets)
  if #self._active_snippets == 0 then
    self:_teardown_inner_state()
  end
end

function SnippetManager:_jump(direction)
  if self._should_update_textobjects then
    self._should_reset_visual = false
    self:_cursor_moved()
  end

  vim.opt.virtualedit = "onemore"
  local jumped = false
  local stack_for_action = {}
  for _, s in ipairs(self._active_snippets) do table.insert(stack_for_action, s) end

  local ntab = nil
  local snippet_for_action = nil
  if self:_current_snippet() then
    snippet_for_action = self:_current_snippet()
  elseif #stack_for_action > 0 then
    snippet_for_action = stack_for_action[#stack_for_action]
  end

  local move_cmd = ""
  if self:_current_snippet() then
    ntab = self:_current_snippet():select_next_tab(direction)
    if ntab then
      if self:_current_snippet().snippet:has_option("s") then
        local line = vim.api.nvim_buf_get_lines(0, ntab._start.line, ntab._start.line + 1, false)[1] or ""
        vim.api.nvim_buf_set_lines(0, ntab._start.line, ntab._start.line + 1, false, { line:gsub("%s+$", "") })
      end
      set_buf_cursor(ntab._start)
      jumped = true
      self._ctab = ntab
      self._visual_content.placeholder = {
        current_text = ntab:current_text(),
        start = ntab._start,
        end_pos = ntab._end,
      }
      self:_current_snippet().current_placeholder = self._visual_content.placeholder
      self._should_reset_visual = false
      self._active_snippets[1]:update_textobjects(nil, self._ctab)
      vim.cmd("normal! zv")

      if ntab._number == 0 and #self._active_snippets > 0 then
        local finish_normal = self:_current_snippet().snippet:has_option("x")
        self:_current_snippet_done()
        if finish_normal then
          vim.cmd([[call feedkeys("\<Esc>", "in")]])
          move_cmd = ""
        end
      end
    else
      self:_current_snippet_done()
      jumped = self:_jump(direction)
    end
  end

  if jumped and ntab then
    snippet_for_action.snippet:do_post_jump(
      ntab._number,
      direction == "FORWARD" and 1 or -1,
      stack_for_action,
      snippet_for_action
    )
  end

  vim.opt.virtualedit = ""

  return jumped
end

function SnippetManager:_setup_inner_state()
  if self._inner_state_up then return end

  self._change_provider = change_mod.NvimChangeProvider:new()
  self._vstate = VimState:new()

  vim.cmd("silent doautocmd <nomodeline> User NeoSnipEnterFirstSnippet")
  self._snippet_buffer_number = vim.api.nvim_get_current_buf()
  self._change_provider:attach(self._snippet_buffer_number)
  self._inner_state_up = true

  -- Setup autocommands
  local augroup = vim.api.nvim_create_augroup("NeoSnipLua", { clear = true })
  vim.api.nvim_create_autocmd("CursorMovedI", {
    group = augroup,
    callback = function() self:_cursor_moved() end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = augroup,
    callback = function() self:_cursor_moved() end,
  })
  vim.api.nvim_create_autocmd("InsertLeave", {
    group = augroup,
    callback = function() end,
  })
  vim.api.nvim_create_autocmd("BufEnter", {
    group = augroup,
    callback = function()
      vim.defer_fn(function()
        self:_leaving_buffer()
      end, 0)
    end,
  })
end

function SnippetManager:_teardown_inner_state()
  if not self._inner_state_up then return end
  vim.cmd("silent doautocmd <nomodeline> User NeoSnipExitLastSnippet")

  if self._change_provider then
    self._change_provider:detach()
    self._change_provider = nil
  end
  self._vstate = nil

  local augroup = vim.api.nvim_get_autocmds({ group = "NeoSnipLua" })
  if #augroup > 0 then
    pcall(vim.api.nvim_del_augroup_by_name, "NeoSnipLua")
  end

  self._snippet_buffer_number = nil
  self._inner_state_up = false
end

function SnippetManager:_leaving_buffer()
  while #self._active_snippets > 0 do
    self:_current_snippet_done()
  end
  self._ctab = nil
  self._ignore_movements = false
end

function SnippetManager:_handle_failure(trigger, pass_through)
  if trigger:lower() == "<tab>" or trigger:lower() == "<s-tab>" or
     (pass_through and vim.g.NeoSnipInsertTriggerOnNoMatch ~= 0) then
    self._last_failure_key = trigger
  end
end

function SnippetManager:add_snippet(trigger, value, description, options, ft, priority, context, actions)
  ft = ft or "all"
  priority = priority or 0
  local def = snippet_mod.NeoSnipSnippetDefinition:new(
    priority, trigger, value, description, options, {}, "added", context, actions
  )
  self._added_snippets_source:add_snippet(ft, def)
end

function SnippetManager:expand_anon(value, trigger, description, options, context, actions)
  trigger = trigger or ""
  description = description or ""
  options = options or ""
  local before = get_line_till_cursor()
  local snip = snippet_mod.NeoSnipSnippetDefinition:new(
    0, trigger, value, description, options, {}, "", context, actions
  )
  if trigger == "" or snip:matches(before, self._visual_content) then
    self:_do_snippet(snip, before)
    return true
  end
  return false
end

function SnippetManager:can_expand()
  local before = get_line_till_cursor()
  local snippets = self:_snips(before, false, false)
  return #snippets > 0
end

function SnippetManager:can_jump(direction)
  local snip = self:_current_snippet()
  if not snip then return false end
  return snip:has_next_tab(direction)
end

function SnippetManager:can_jump_forwards()
  return self:can_jump("FORWARD")
end

function SnippetManager:can_jump_backwards()
  return self:can_jump("BACKWARD")
end

function SnippetManager:list_snippets()
  local before = get_line_till_cursor()
  local snippets = self:_snips(before, true)
  if #snippets == 0 then
    self:_handle_failure(vim.g.NeoSnipListSnippets or "<c-tab>")
    return
  end
  table.sort(snippets, function(a, b) return a:trigger() < b:trigger() end)
  local snippet = ask_snippets(snippets)
  if snippet then
    self:_do_snippet(snippet, before)
  end
end

function SnippetManager:snippets_in_current_scope(search_all)
  local before = ""
  if not search_all then before = get_line_till_cursor() end
  local snippets = self:_snips(before, true)

  table.sort(snippets, function(a, b) return a:trigger() < b:trigger() end)
  local neosnip_dict = {}
  local neosnip_dict_info = {}
  for _, snip in ipairs(snippets) do
    local desc = snip:description()
    local loc = snip:location()
    local key = snip:trigger()
    if desc:find(key) then
      desc = desc:sub(desc:find(key) + #key + 2)
    end
    if #desc > 2 and desc:sub(1,1) == desc:sub(-1) and (desc:sub(1,1) == "'" or desc:sub(1,1) == '"') then
      desc = desc:sub(2, -2)
    end
    neosnip_dict[key] = desc
    neosnip_dict_info[key] = { description = desc, location = loc }
  end
  vim.g.current_neosnip_dict = neosnip_dict
  vim.g.current_neosnip_dict_info = neosnip_dict_info
end

function SnippetManager:_file_to_edit(ft, bang)
  if not ft or #ft == 0 then
    ft = vim.bo.filetype or ""
  end

  local dirs = source_mod.find_all_snippet_directories()
  for _, dir in ipairs(dirs) do
    local files = source_mod.find_snippet_files(ft, dir)
    if #files > 0 then
      return files[1]
    end
  end

  if not bang then return "" end

  if #dirs > 0 then
    local dir = dirs[1]
    vim.fn.mkdir(dir, "p")
    return dir .. "/" .. ft .. ".snippets"
  end

  local first_rtp = vim.o.runtimepath:match("^[^,]+")
  local dir = first_rtp .. "/neosnip"
  vim.fn.mkdir(dir, "p")
  return dir .. "/" .. ft .. ".snippets"
end

-- Public API
M.SnippetManager = SnippetManager

function M.create()
  return SnippetManager:new()
end

return M
