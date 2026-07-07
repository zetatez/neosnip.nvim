# NeoSnip

A pure-Lua snippet engine for Neovim. Drop-in spiritual successor to
[UltiSnips](https://github.com/SirVer/ultisnips) with zero Python
dependency, matching feature coverage, and no external requirements beyond
Neovim itself.

## Features

- **Pure Lua** – no Python, no external processes, no dependencies.
- **UltiSnips-compatible snippet syntax** – reuse your existing `.snippets`
  files with minimal or no changes.
- **`!p` Python bridge** – existing Python-powered snippets still work via
  Neovim's built-in `py3eval`.
- **`!v` VimL evaluation** – inline Vimscript expressions.
- **`` ` `` shell commands** – inline shell execution.
- **Tab stop jumping** – `${1}`, `${2}`, `$0` with forward/backward
  navigation.
- **Mirrors** – `$1` mirrors live text of tabstop 1.
- **Transformations** – `${1/pattern/replacement/flags}` with regex
  substitution, case transforms (`\u`/`\l`/`\U...\E`/`\L...\E`), and
  conditional replacements (`?(N)true:false`).
- **Choices** – `${1|opt1,opt2,...|}` interactive selection.
- **Visual placeholders** – `${VISUAL}` / `${VISUAL:...}` captures
  selection at expansion time.
- **Context and actions** – `context "expr"`, `pre_expand`,
  `post_expand`, `post_jump`, `post_finish`.
- **Auto-trigger** – snippets with the `A` flag expand as you type.
- **SnipMate compatibility** – loads `.snippets` from `snippets/`
  directories.
- **Change tracking** – Neovim `on_bytes`-based edit detection for live
  mirror/transformation updates.
- **Word boundary / in-word / regex / beginning-of-line triggers** with
  priority sorting.
- **`global !p`** Python shared variables across snippets.
- **`extends`, `clearsnippets`, `priority`** – full snippet file
  organization.

## Requirements

- Neovim ≥ 0.8.0 (with `vim.fn.py3eval` if using `!p` snippets).

## Installation

### lazy.nvim

```lua
{
  "zetatez/neosnip",
  config = true,
}
```

### packer.nvim

```lua
use({
  "zetatez/neosnip",
  config = function()
    require("neosnip").setup()
  end,
})
```

### vim-plug

```vim
Plug 'zetatez/neosnip'
" Manually call in your config:
" lua require('neosnip').setup()
```

No manual `setup()` call is needed if the plugin directory is on
`runtimepath` – the plugin/neosnip.vim entry point loads automatically.

## Quick Start

1. Create a snippet file:

   ```bash
   mkdir -p ~/.config/nvim/neosnip
   touch ~/.config/nvim/neosnip/all.snippets
   ```

2. Add a snippet:

   ```snippets
   snippet hello "Say hello"
   Hello, world!
   endsnippet
   ```

3. Restart Neovim, type `hello`, and press `<Tab>`.

## Configuration

```lua
require("neosnip").setup()
```

Or with overrides:

```lua
-- These can be set before or after setup():
vim.g.NeoSnipExpandTrigger = "<tab>"
vim.g.NeoSnipJumpForwardTrigger = "<c-j>"
vim.g.NeoSnipJumpBackwardTrigger = "<c-k>"
vim.g.NeoSnipListSnippets = "<c-tab>"
vim.g.NeoSnipSnippetDirectories = { "neosnip" }
vim.g.NeoSnipEnableSnipMate = 1    -- set to 0 to disable SnipMate

require("neosnip").setup()
```

 | Variable                            | Default         | Description                            |
 | ---                                 | ---             | ---                                    |
 | `g:NeoSnipExpandTrigger`            | `<tab>`         | Expand a snippet                       |
 | `g:NeoSnipJumpForwardTrigger`       | `<c-j>`         | Jump to next tab stop                  |
 | `g:NeoSnipJumpBackwardTrigger`      | `<c-k>`         | Jump to previous tab stop              |
 | `g:NeoSnipListSnippets`             | `<c-tab>`       | List available snippets                |
 | `g:NeoSnipExpandOrJumpTrigger`      | (none)          | Single key for expand-or-jump          |
 | `g:NeoSnipJumpOrExpandTrigger`      | (none)          | Alias for ExpandOrJumpTrigger          |
 | `g:NeoSnipSnippetDirectories`       | `{ "neosnip" }` | Directories on `runtimepath` to search |
 | `g:NeoSnipEnableSnipMate`           | `1`             | Load SnipMate snippets                 |
 | `g:NeoSnipEditSplit`                | `"normal"`      | Split direction for `:NeoSnipEdit`     |
 | `g:NeoSnipAutoTrigger`              | `1`             | Enable auto-trigger snippets           |
 | `g:NeoSnipRemoveSelectModeMappings` | `1`             | Clean up select-mode mappings          |
 | `g:NeoSnipMappingsToIgnore`         | `{}`            | Keys to skip mapping                   |
 | `b:NeoSnipSnippetDirectories`       | (none)          | Per-buffer override                    |

## Commands

 | Command                         | Description                        |
 | ---                             | ---                                |
 | `:NeoSnipEdit {filetype}`       | Open snippet file for editing      |
 | `:NeoSnipAddFiletypes {fts}`    | Add extra filetypes                |
 | `:NeoSnipRemoveFiletypes {fts}` | Remove filetypes                   |
 | `:NeoSnipListLocations`         | Show snippet locations in quickfix |

## Snippet Syntax

### Basic

```snippets
snippet trigger "description" options
snippet body
endsnippet
```

### Options (flags)

 | Flag | Meaning                          |
 | ---  | ---                              |
 | `b`  | Beginning of line only           |
 | `i`  | In-word expansion                |
 | `w`  | Word boundary                    |
 | `r`  | Trigger is a regex               |
 | `A`  | Auto-trigger                     |
 | `t`  | Expand tabs in snippet           |
 | `m`  | Trim trailing whitespace         |
 | `x`  | Exit insert mode after snippet   |
 | `s`  | Trim spaces on selected tab stop |

### Tab stops

```
${1}         simple tab stop
${1:hello}   tab stop with default text
${1/.*/\U$0/}  transformation on tab stop 1
$0           exit marker
```

### Mirrors and transformations

```
$1                     mirrors tab stop 1
${1/pattern/repl/}     regex substitution
${1/pattern/repl/g}    global substitution
${1/pattern/repl/i}    case-insensitive
\U$0\E                 uppercase the match
\L$0\E                 lowercase the match
\u$0                   uppercase next char
\l$0                   lowercase next char
?(1)yes:no             conditional (if tab 1 non-empty)
```

### Inline codes

```
`!p snip.rv = t[1].upper()`       Python (via py3eval)
`!v tr(expand("%:t"), ".", "_")`   VimL expression
`echo hello | tr a-z A-Z`          Shell command
```

### Placeholders

```
${VISUAL}                         inserts visual selection
${VISUAL:pattern/repl/}            selection with transformation
```

### Choices

```
${1|apple,banana,cherry|}          interactive choice
```

### Context and actions

```snippets
snippet log "Log to file" b
context "expand('%:e') == 'py'"
pre_expand "call mkdir('logs', 'p')"
post_expand "call writefile(['...'], 'logs/output.log')"
post_jump "echo 'at tab ' . tabpagenr()"
post_finish "echom 'snippet done'"
endsnippet
```

### File-wide directives

```snippets
extends html css js          inherit snippets from other filetypes
clearsnippets                clear current filetype snippets
priority 10                  default priority for all snippets in file

global !p
import os
path = os.path.dirname(__file__)
endglobal
```

## Python Bridge (`!p`)

Python `!p` blocks execute via Neovim's `py3eval`. Available variables:

 | Variable        | Description                         |
 | ---             | ---                                 |
 | `snip.rv`       | Set to replace the placeholder text |
 | `snip.ct`       | Current text of this placeholder    |
 | `snip.fn`       | Current filename                    |
 | `snip.path`     | Full file path                      |
 | `snip.basename` | File basename (without extension)   |
 | `snip.ft`       | Filetype                            |
 | `t[n]`          | Read/write tab stop `n`             |
 | `fn`            | Shorthand for `snip.fn`             |
 | `path`          | Shorthand for `snip.path`           |
 | `basename`      | Shorthand for `snip.basename`       |
 | `ft`            | Shorthand for `snip.ft`             |

Pre-imported modules: `os`, `json`, `re`, `string`, `random`, `sys`.

### Examples

```snippets
snippet upper "Uppercase"
`!p snip.rv = t[1].upper()`
endsnippet

snippet date "Insert date"
`!p import time; snip.rv = time.strftime("%Y-%m-%d")`
endsnippet

snippet tpl "Template with tab write"
${1:name} `!p t[1] = t[1].title()
snip.rv = ""`
endsnippet

global !p
def greet(name):
    return f"Hello, {name}!"
endglobal

snippet hi "Greeting"
`!p snip.rv = greet(t[1])`
endsnippet
```

## SnipMate Compatibility

NeoSnip loads SnipMate-format snippets from `runtimepath/snippets/` by
default. To disable:

```lua
vim.g.NeoSnipEnableSnipMate = 0
```

## Migrating from UltiSnips

1. Point `g:NeoSnipSnippetDirectories` to your existing snippet folders:

   ```lua
   vim.g.NeoSnipSnippetDirectories = { "UltiSnips" }
   ```

2. Most `.snippets` files work as-is.

3. Replace `UltiSnips` commands/keys with NeoSnip equivalents:

   - `:UltiSnipsEdit` → `:NeoSnipEdit`
   - `g:UltiSnipsExpandTrigger` → `g:NeoSnipExpandTrigger`
   - `g:UltiSnipsSnippetDirectories` → `g:NeoSnipSnippetDirectories`
   - etc.

## API

```lua
local neosnip = require("neosnip")
neosnip.setup()

-- Programmatic snippet management
neosnip.manager:add_snippet(trigger, body, desc, opts, ft, priority, context, actions)
neosnip.manager:expand_anon(body, trigger, desc, opts, context, actions)

-- Manual control
neosnip.expand_snippet()
neosnip.jump_forwards()
neosnip.jump_backwards()
neosnip.list_snippets()
```

## License

Same as the original UltiSnips project — GPLv3 or later.
