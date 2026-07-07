local NTO = require("neosnip.text_object").NoneditableTextObject

local PythonCode = setmetatable({}, { __index = NTO })
PythonCode.__index = PythonCode

local _py_initialized = false

local PY_INIT_SCRIPT = [[
py3 << PYEOF
import os, json, re, string, random, sys
class _Snip:
    def __init__(self, **k):
        for a, v in k.items():
            setattr(self, a, v)
        self._rv = ""
        self._rv_changed = False
    @property
    def rv(self):
        return self._rv
    @rv.setter
    def rv(self, v):
        self._rv = v
        self._rv_changed = True
class _Tabs:
    def __init__(self, vals):
        self._data = {}
        self._changed = set()
        if isinstance(vals, list):
            vals = {}
        for k, v in vals.items():
            if isinstance(k, str) and k.isdigit():
                self._data[int(k)] = v
            else:
                self._data[k] = v
    def __getitem__(self, k):
        return self._data.get(k, "")
    def __setitem__(self, k, v):
        self._data[k] = v
        self._changed.add(k)
def _run_us(code, ctx_json):
    ctx = json.loads(ctx_json)
    g = globals()
    d = dict(ctx)
    d['snip'] = _Snip(**ctx)
    d['t'] = _Tabs(ctx.get('t', {}))
    d['changed'] = False
    exec(code, g, d)
    snip_obj = d.get('snip', _Snip())
    rv = snip_obj._rv if snip_obj._rv_changed else None
    tab_data = dict(d.get('t', _Tabs({}))._data)
    tab_changed = list(d.get('t', _Tabs({}))._changed)
    err = sys.exc_info()[1]
    if err is not None:
        err = str(err)
    return json.dumps({'rv': rv, 'err': err, 'tab_data': tab_data, 'tab_changed': tab_changed, 'changed': d.get('changed', False)})
PYEOF
]]

local function _ensure_py_init()
  if _py_initialized then return true end
  local ok, exists = pcall(vim.fn.py3eval, [['_run_us' in dir()]])
  if ok and exists then
    _py_initialized = true
    return true
  end
  local ok_err, msg = pcall(vim.cmd, PY_INIT_SCRIPT)
  if not ok_err then
    vim.notify("NeoSnip: failed to init Python bridge: " .. tostring(msg), vim.log.levels.ERROR)
    return false
  end
  _py_initialized = true
  return true
end

function PythonCode:new(parent, token)
  self._locals = {}
  self._visual_text = ""
  self._visual_mode = ""
  do
    local snippet = parent
    while snippet do
      if snippet.locals then
        self._locals = snippet.locals
        self._visual_text = snippet.visual_content and snippet.visual_content.text or ""
        self._visual_mode = snippet.visual_content and snippet.visual_content.mode or ""
        break
      end
      snippet = snippet._parent
    end
  end

  self._indent = token.indent
  self._code = token.code:gsub("\\`", "`")

  local obj = NTO.new(self, parent, token.start, token.end_pos, token.initial_text)
  return obj
end

function PythonCode:_update(done, buf)
  if not _ensure_py_init() then return true end

  local path = vim.fn.expand("%") or ""
  local fn = vim.fn.expand("%:t") or ""
  local basename = fn:match("^(.+)%.[^.]*$") or fn
  local ft = vim.bo.filetype or ""
  local ct = self:current_text()

  -- Build tabstop text dict for t[n] access
  local tabstop_texts = {}
  do
    local seen = {}
    local function collect(obj)
      if not obj or seen[obj] then return end
      seen[obj] = true
      if rawget(obj, "_tabstops") then
        for no, ts in pairs(obj._tabstops) do
          if no ~= 0 then
            local ok, text = pcall(function() return ts:current_text() end)
            if ok then tabstop_texts[tostring(no)] = text end
          end
        end
      end
      if obj._children then
        for _, child in ipairs(obj._children) do collect(child) end
      end
    end
    collect(self._parent)
  end

  -- Build globals code
  local globals_code = ""
  if self._locals and self._locals.globals then
    local gp = self._locals.globals["!p"]
    if gp then globals_code = table.concat(gp, "\n") .. "\n" end
  end

  -- Combine globals code with user code
  local combined_code = globals_code .. self._code

  -- Build context dict
  local context = {
    ct = ct,
    fn = fn,
    path = path,
    basename = basename,
    ft = ft,
    t = tabstop_texts,
  }
  local context_json = vim.fn.json_encode(context)

  -- Call _run_us via py3eval
  local code_arg = vim.inspect(combined_code)
  local ctx_arg = vim.inspect(context_json)
  local expr = "_run_us(" .. code_arg .. ", " .. ctx_arg .. ")"

  local ok, output = pcall(vim.fn.py3eval, expr)
  if not ok or not output or type(output) ~= "string" then
    return true
  end

  local ok_decode, result = pcall(vim.fn.json_decode, output)
  if not ok_decode or type(result) ~= "table" then
    return true
  end

  -- Apply t[] changes
  if result.tab_data and type(result.tab_data) == "table" then
    for no, text in pairs(result.tab_data) do
      local n = tonumber(no)
      if not n then n = no end
      if self._parent then
        local ts = self._parent:_get_tabstop(self, n)
        if ts then
          ts:overwrite(buf, text)
        end
      end
    end
  end

  -- Apply rv change
  local rv = result.rv
  if rv ~= vim.NIL and rv ~= nil and rv ~= ct then
    self:overwrite(buf, rv)
    return false
  end
  return true
end

return PythonCode
