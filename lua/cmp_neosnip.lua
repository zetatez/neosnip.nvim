local cmp_neosnip = {}

local has_neosnip, neosnip = pcall(require, "neosnip")

function cmp_neosnip.is_available()
  return has_neosnip
end

function cmp_neosnip.get_keyword_pattern()
  return [[\k\+]]
end

function cmp_neosnip.complete(self, params, callback)
  if not has_neosnip then
    callback()
    return
  end

  local manager = neosnip.manager
  local before = vim.fn.strcharpart(params.context.cursor_before_line, 0, params.offset)
  local items = {}

  -- Get matching snippets for current filetype
  local snippets = manager:_snips(before, true)
  for _, s in ipairs(snippets) do
    local trigger = s:trigger()
    if trigger and #trigger > 0 then
      local description = s:description() or ""
      -- Filter by prefix match (nvim-cmp handles only prefix matching in source)
      if trigger:sub(1, #before) == before then
        table.insert(items, {
          label = trigger,
          kind = 15, -- vim.lsp.protocol.CompletionItemKind.Snippet
          insertText = s._value,
          insertTextFormat = 2, -- Snippet format
          detail = " [NeoSnip]",
          documentation = {
            kind = "markdown",
            value = ("```\n%s\n```\n\n%s"):format(
              s._value or "",
              description
            ),
          },
          sortText = ("%04d"):format(s:priority() or 0),
        })
      end
    end
  end

  callback({ items = items, isIncomplete = true })
end

function cmp_neosnip.resolve(completion_item, callback)
  callback(completion_item)
end

function cmp_neosnip.execute(completion_item, callback)
  callback(completion_item)
end

return cmp_neosnip
