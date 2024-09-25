vim9script


def CanMap(mode: string, lhs: string): bool
    return (index(g:vim9cutlass_exclude, mode .. lhs) < 0) && (maparg(lhs, mode) == '')
enddef

def CreateMapping(mode: string, lhs: string, rhs: string)
    execute(mode .. 'noremap' .. ' <silent> <special> ' .. lhs .. ' ' .. rhs)
enddef

def RedirectToRegister(mode: string, lhs: string, reg: string)
    CreateMapping(mode, lhs, '"' .. reg .. lhs)
enddef


def OverrideChangeMappings()
    for mode in ['n', 'x']
        for lhs in ['c', 'C', 's', 'S']
            if CanMap(mode, lhs)
                RedirectToRegister(mode, lhs, g:vim9cutlass_registers.change)
            endif
        endfor
    endfor

    for mode in ['n']
        for lhs in ['cc']
            if CanMap(mode, lhs)
                RedirectToRegister(mode, lhs, g:vim9cutlass_registers.change)
            endif
        endfor
    endfor
enddef

def OverrideDeleteMappings()
    for mode in ['n', 'x']
        for lhs in ['d', 'D', 'x', 'X', '<Del>']
            if CanMap(mode, lhs)
                RedirectToRegister(mode, lhs, g:vim9cutlass_registers.delete)
            endif
        endfor
    endfor

    for mode in ['n']
        for lhs in ['dd']
            if CanMap(mode, lhs)
                RedirectToRegister(mode, lhs, g:vim9cutlass_registers.delete)
            endif
        endfor
    endfor
enddef

def OverrideSelectMappings()
    var mode = 's'

    var code = 33
    while code <= 126
        var lhs = escape(nr2char(code), '|')
        if CanMap(mode, lhs)
            CreateMapping(mode, lhs, '<C-O>"' .. g:vim9cutlass_registers.select .. 'c' .. lhs)
        endif
        code += 1
    endwhile

    for lhs in ['<CR>', '<NL>', '<Space>']
        if CanMap(mode, lhs)
            CreateMapping(mode, lhs, '<C-O>"' .. g:vim9cutlass_registers.select .. 'c' .. lhs)
        endif
    endfor

    for lhs in ['<BS>', '<C-H>']
        if CanMap(mode, lhs)
            CreateMapping(mode, lhs, '<C-O>"' .. g:vim9cutlass_registers.select .. 'c')
        endif
    endfor
enddef

export def OverrideDefaultMappings()
    OverrideChangeMappings()
    OverrideDeleteMappings()
    OverrideSelectMappings()
enddef


export def CreateCutMappings()
    if g:vim9cutlass_cut == v:null
        return
    endif

    CreateMapping('n', g:vim9cutlass_cut, 'd')
    CreateMapping('x', g:vim9cutlass_cut, 'd')
    CreateMapping('n', g:vim9cutlass_cut .. g:vim9cutlass_cut, 'dd')
    CreateMapping('n', g:vim9cutlass_cut -> toupper(), 'D')
enddef
