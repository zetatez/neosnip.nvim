if exists('did_plugin_neosnip') || &cp
    finish
endif
let did_plugin_neosnip=1

" Load Lua backend - no Python dependency required
if !has('nvim')
   echohl WarningMsg
   echom  "NeoSnip Lua backend requires Neovim"
   echohl None
   finish
endif

lua require('neosnip.init').setup()

" The Commands we define (shadowed by Lua init for completion, but kept for
" Vim 9+ compatibility and :command visibility).
if !exists(':NeoSnipEdit')
    command! -bang -nargs=? -complete=customlist,NeoSnip#FileTypeComplete NeoSnipEdit
        \ :call NeoSnip#Edit(<q-bang>, <q-args>)
endif

if !exists(':NeoSnipAddFiletypes')
    command! -nargs=1 NeoSnipAddFiletypes :call NeoSnip#AddFiletypes(<q-args>)
endif

if !exists(':NeoSnipRemoveFiletypes')
    command! -nargs=1 NeoSnipRemoveFiletypes :call NeoSnip#RemoveFiletypes(<q-args>)
endif

if !exists(':NeoSnipListLocations')
    command! NeoSnipListLocations :call NeoSnip#ListSnippetLocations()
endif

" vim: ts=8 sts=4 sw=4
