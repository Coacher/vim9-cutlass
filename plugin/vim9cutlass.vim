if !has('vim9script')
    echoerr 'vim9-cutlass requires vim9script feature enabled'
    finish
endif

vim9script


if exists('g:vim9cutlass_loaded')
    finish
endif

g:vim9cutlass_loaded = 1


g:vim9cutlass_cut = get(g:, 'vim9cutlass_cut', v:null)

g:vim9cutlass_exclude = get(g:, 'vim9cutlass_exclude', [])

g:vim9cutlass_registers = get(
    g:, 'vim9cutlass_registers', {
        change: '_',
        delete: '_',
        select: '_',
    }
)


import autoload '../autoload/vim9cutlass.vim'

vim9cutlass.OverrideDefaultMappings()
vim9cutlass.CreateCutMappings()
