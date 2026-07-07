local manager_mod = require("neosnip.manager")
local change_mod = require("neosnip.change")
local vim_state_mod = require("neosnip.vim_state")
local snippet_mod = require("neosnip.snippet")
local source_mod = require("neosnip.source")

local M = {}

local manager = manager_mod.create()
M.manager = manager

local vstate = vim_state_mod.VimState:new()
M.vstate = vstate

local change_provider = change_mod.NvimChangeProvider:new()
M.change_provider = change_provider

local visual_content = vim_state_mod.VisualContentPreserver:new()
M.visual_content = visual_content

local any_buffer_file_loaded = false

local function ensure_snippet_files_loaded()
  if not any_buffer_file_loaded then
    for _, pair in ipairs(manager._snippet_sources) do
      local _, source = pair[1], pair[2]
      if source.ensure then
        source:ensure(manager:get_buffer_filetypes())
      end
    end
    any_buffer_file_loaded = true
  end
end

local function compensate_for_pum()
  if vim.fn.pumvisible() == 1 then
    manager:_cursor_moved()
  end
end

-- Define VimL-callable functions that replace the Python-based autoload
-- NOTE: These used to be in autoload/NeoSnip.vim but we use Lua callbacks now.
-- These are kept for backward compatibility only.
local function define_vim_functions()
end

function M.expand_snippet()
  compensate_for_pum()
  manager:expand()
end

function M.expand_or_jump()
  compensate_for_pum()
  manager:expand_or_jump()
end

function M.jump_forwards()
  compensate_for_pum()
  manager:jump_forwards()
end

function M.jump_backwards()
  compensate_for_pum()
  manager:jump_backwards()
end

function M.list_snippets()
  compensate_for_pum()
  manager:list_snippets()
end

function M.snippets_in_current_scope()
  compensate_for_pum()
  manager:snippets_in_current_scope(false)
end

function M.can_expand()
  return manager:can_expand()
end

function M.can_jump_forwards()
  return manager:can_jump_forwards()
end

function M.can_jump_backwards()
  return manager:can_jump_backwards()
end

function M.add_filetypes(filetypes)
  manager:add_buffer_filetypes(filetypes)
end

function M.remove_filetypes(filetypes)
  manager:remove_buffer_filetypes(filetypes)
end

function M.edit(bang, type)
  local file = manager:_file_to_edit(type or "", bang ~= "")
  if not file or #file == 0 then return end

  local mode = "e"
  if vim.g.NeoSnipEditSplit then
    local split = vim.g.NeoSnipEditSplit
    if split == "vertical" then
      mode = "vs"
    elseif split == "horizontal" then
      mode = "sp"
    elseif split == "tabdo" then
      mode = "tabedit"
    elseif split == "context" then
      mode = "vs"
      local tw = vim.bo.tw
      if tw == 0 then tw = 80 end
      if vim.fn.winwidth(0) <= 2 * tw then
        mode = "sp"
      end
    end
  end
  vim.cmd(mode .. " " .. vim.fn.fnameescape(file))
end

function M.save_last_visual_selection()
  visual_content:conserve()
  manager._visual_content = {
    mode = visual_content:mode(),
    text = visual_content:text(),
    placeholder = visual_content:placeholder(),
  }
end

function M.add_snippet_with_priority()
  local trigger = vim.eval("a:trigger")
  local value = vim.eval("a:value")
  local description = vim.eval("a:description")
  local options = vim.eval("a:options")
  local filetype = vim.eval("a:filetype")
  local priority = vim.eval("a:priority")
  manager:add_snippet(trigger, value, description, options, filetype, priority)
end

function M.anon_expand()
  local args = vim.eval("a:000")
  local value = vim.eval("a:value")
  manager:expand_anon(value, table.unpack(args))
end

function M.cursor_moved()
  manager:_cursor_moved()
end

function M._leaving_insert_mode()
  -- Placeholder for insert mode leave handling
end

function M._track_change()
  if manager._autotrigger == 0 then return end
  if #manager._active_snippets > 0 then
    manager:_cursor_moved()
    return
  end
  manager:_try_expand(true)
end

function M._refresh_snippets()
  any_buffer_file_loaded = false
  ensure_snippet_files_loaded()
end

function M._leaving_buffer()
  manager:_leaving_buffer()
end

function M._toggle_autotrigger()
  manager._autotrigger = manager._autotrigger == 0 and 1 or 0
  return manager._autotrigger
end

function M._file_to_edit(type, bang)
  return manager:_file_to_edit(type, bang)
end

local function set_default(var, value)
  if vim.g[var] == nil then vim.g[var] = value end
end

local function _feed_on_fail(trigger)
  if manager._last_failure_key then
    manager._last_failure_key = nil
    vim.api.nvim_feedkeys(
      vim.api.nvim_replace_termcodes(trigger, true, true, true),
      "n", true
    )
  end
end

function M._map_keys()
  set_default("NeoSnipExpandTrigger", "<tab>")
  set_default("NeoSnipListSnippets", "<c-tab>")
  set_default("NeoSnipJumpForwardTrigger", "<c-j>")
  set_default("NeoSnipJumpBackwardTrigger", "<c-k>")
  set_default("NeoSnipRemoveSelectModeMappings", 1)
  set_default("NeoSnipMappingsToIgnore", {})
  set_default("NeoSnipEditSplit", "normal")
  set_default("NeoSnipSnippetDirectories", { "neosnip" })
  set_default("NeoSnipEnableSnipMate", 1)

  local expand = vim.g.NeoSnipExpandTrigger
  local jump_fwd = vim.g.NeoSnipJumpForwardTrigger
  local list_snips = vim.g.NeoSnipListSnippets

  if vim.g.NeoSnipExpandOrJumpTrigger ~= nil then
    local t = vim.g.NeoSnipExpandOrJumpTrigger
    vim.keymap.set("i", t, function() M.expand_or_jump(); _feed_on_fail(t) end, { silent = true })
    vim.keymap.set("s", t, function() M.expand_or_jump() end, { silent = true })
  elseif vim.g.NeoSnipJumpOrExpandTrigger ~= nil then
    local t = vim.g.NeoSnipJumpOrExpandTrigger
    vim.keymap.set("i", t, function() M.expand_or_jump(); _feed_on_fail(t) end, { silent = true })
    vim.keymap.set("s", t, function() M.expand_or_jump() end, { silent = true })
  elseif expand == jump_fwd then
    vim.keymap.set("i", expand, function() M.expand_or_jump(); _feed_on_fail(expand) end, { silent = true })
    vim.keymap.set("s", expand, function() M.expand_or_jump() end, { silent = true })
  else
    vim.keymap.set("i", expand, function() M.expand_snippet(); _feed_on_fail(expand) end, { silent = true })
    vim.keymap.set("s", expand, function() M.expand_snippet() end, { silent = true })
  end
  vim.keymap.set("x", expand, function() M.save_last_visual_selection()
    vim.cmd('normal! gv"_s')
  end, { silent = true })

  if #tostring(list_snips) > 0 then
    vim.keymap.set("i", list_snips, function() M.list_snippets(); _feed_on_fail(list_snips) end, { silent = true })
    vim.keymap.set("s", list_snips, function() M.list_snippets() end, { silent = true })
  end

  vim.keymap.set("s", "<BS>", "<c-g>\"_c", { silent = true })
  vim.keymap.set("s", "<DEL>", "<c-g>\"_c", { silent = true })
  vim.keymap.set("s", "<c-h>", "<c-g>\"_c", { silent = true })
  vim.keymap.set("s", "<c-r>", "<c-g>\"_c<c-r>", { silent = true })
end

function M.setup()
  vim.g.did_plugin_neosnip_lua = 1
  vim.g._neosnip_reg_cache = {}

  define_vim_functions()

  vim.api.nvim_create_user_command("NeoSnipEdit", function(opts)
    M.edit(opts.bang == "bang", opts.args)
  end, { nargs = "?", complete = function(ArgLead, CmdLine, CursorPos)
    local items = vim.fn.sort(vim.fn.uniq(vim.fn.map(vim.fn.split(vim.fn.globpath(vim.o.runtimepath, "syntax/*.vim"), "\n"), "fnamemodify(v:val, ':t:r')")))
    table.insert(items, "all")
    local ret = {}
    for _, item in ipairs(items) do
      if item:find("^" .. ArgLead) then
        table.insert(ret, item)
      end
    end
    return ret
  end, bang = true })

  vim.api.nvim_create_user_command("NeoSnipAddFiletypes", function(opts)
    M.add_filetypes(opts.args)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("NeoSnipRemoveFiletypes", function(opts)
    M.remove_filetypes(opts.args)
  end, { nargs = 1 })

  vim.api.nvim_create_user_command("NeoSnipListLocations", function()
    M.snippets_in_current_scope()
    local info = vim.g.current_neosnip_dict_info or {}
    local items = {}
    for trigger, info_t in pairs(info) do
      local idx = info_t.location:match(".*():")
      if idx == nil then
        local lnum_str = info_t.location:match(":(%d+)$")
        local filename = info_t.location:match("^(.-):%d+$")
        local lnum = tonumber(lnum_str) or 0
        if lnum > 0 and filename then
          local text = trigger
          if info_t.description and #info_t.description > 0 then
            text = text .. " - " .. info_t.description
          end
          table.insert(items, { filename = filename, lnum = lnum, text = text })
        end
      end
    end
    table.sort(items, function(a, b) return a.text < b.text end)
    if #items == 0 then
      vim.notify("NeoSnip: no snippet definitions with file locations found.", vim.log.levels.INFO)
      return
    end
    vim.fn.setqflist({}, 'r', { title = 'NeoSnip snippet locations', items = items })
    vim.cmd("copen")
  end, {})

  -- Auto-trigger: InsertCharPre + TextChangedI + TextChangedP
  local auto_augroup = vim.api.nvim_create_augroup("NeoSnip_AutoTrigger_Lua", { clear = true })
  vim.api.nvim_create_autocmd("InsertCharPre", {
    group = auto_augroup,
    callback = function() M._track_change() end,
  })
  vim.api.nvim_create_autocmd("TextChangedI", {
    group = auto_augroup,
    callback = function() M._track_change() end,
  })
  vim.api.nvim_create_autocmd("TextChangedP", {
    group = auto_augroup,
    callback = function() M._track_change() end,
  })

  -- Ensure snippets loaded on VimEnter
  vim.api.nvim_create_autocmd("VimEnter", {
    group = auto_augroup,
    callback = function()
      ensure_snippet_files_loaded()
    end,
  })

  vim.api.nvim_create_autocmd("FileType", {
    group = auto_augroup,
    callback = function()
      -- Reset loaded state so sources re-ensure for new filetypes
      any_buffer_file_loaded = false
    end,
  })

  M._map_keys()

  ensure_snippet_files_loaded()
end

return M
