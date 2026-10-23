" Entry point of a test process, kept in legacy script on purpose.
"
" Keys are fed from here so that command lines typed during a case are
" parsed with the rules a user gets at the keyboard, not with the Vim9
" rules of the script that called feedkeys().

if !has('vim9script')
    " The plugin itself refuses such builds; run.sh checks them separately.
    cquit!
endif

function CutlassFeed(keys) abort
    silent! call feedkeys(a:keys, 'xt')
endfunction

execute 'source' fnameescape(expand('<sfile>:p:h') .. '/harness.vim')
