vim9script


const has_clipboard = has('clipboard')
const put_register_names = ['"', '-'] + mapnew(range(10), (_, n) => string(n))

var put_registers: dict<dict<any>> = {}
var put_changedtick = 0
var put_pending = false
var put_replaced: dict<any> = {}


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
        for lhs in ['d', 'D', 'x', 'X']
            if CanMap(mode, lhs)
                RedirectToRegister(mode, lhs, g:vim9cutlass_registers.delete)
            endif
        endfor

        # Normal mode <Del> ignores the register prefix, use equivalent x
        for lhs in ['<Del>', '<kDel>']
            if CanMap(mode, lhs)
                CreateMapping(mode, lhs, '"' .. g:vim9cutlass_registers.delete .. 'x')
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

    var code = 33 # ASCII printable characters codes: 33-126
    while code <= 126
        var lhs = escape(nr2char(code), '|')
        if CanMap(mode, lhs)
            CreateMapping(mode, lhs, '<C-O>"' .. g:vim9cutlass_registers.select .. 'c' .. lhs)
        endif
        code += 1
    endwhile

    for lhs in ['<CR>', '<NL>', '<kEnter>', '<Space>']
        if CanMap(mode, lhs)
            CreateMapping(mode, lhs, '<C-O>"' .. g:vim9cutlass_registers.select .. 'c' .. lhs)
        endif
    endfor

    for lhs in ['<BS>', '<Del>', '<kDel>', '<C-H>']
        if CanMap(mode, lhs)
            CreateMapping(mode, lhs, '<C-O>"' .. g:vim9cutlass_registers.select .. 'c')
        endif
    endfor
enddef

def SavePutRegisters(lhs: string, reg: string): string
    var names = copy(put_register_names)
    if has_clipboard
        var clipboard = split(&clipboard, ',')
        if index(clipboard, 'unnamed') >= 0
            add(names, '*')
        endif
        if index(clipboard, 'unnamedplus') >= 0
            add(names, '+')
        endif
    endif
    put_registers = {}
    for name in names
        put_registers[name] = getreginfo(name)
    endfor
    put_changedtick = b:changedtick
    put_pending = (reg != '_')
    put_replaced = {}
    return lhs .. "\<ScriptCmd>RestorePutRegisters(" .. string(reg) .. ")\<CR>"
enddef

def CapturePutReplaced()
    # Visual put yanks the replaced text before the put, other TextYankPost
    # handlers may change the registers, but v:event keeps the yanked text
    if put_pending
        put_pending = false
        put_replaced = {regcontents: v:event.regcontents, regtype: v:event.regtype}
    endif
enddef

def RestorePutRegisters(reg: string)
    put_pending = false
    # Registers are unchanged if the put fails, e.g. in a nomodifiable buffer
    if b:changedtick == put_changedtick
        return
    endif
    for [name, info] in items(put_registers)
        if getreginfo(name) != info
            setreg(name, info)
        endif
    endfor
    setreg('"', {points_to: put_registers['"'].points_to})
    if !empty(put_replaced)
        setreg(reg, put_replaced)
    endif
enddef

def RedirectPutToRegister(mode: string, lhs: string, reg: string)
    CreateMapping(mode, '<expr> ' .. lhs, 'SavePutRegisters(' .. string(lhs) .. ', ' .. string(reg) .. ')')
enddef

def OverridePutMappings()
    for mode in ['x']
        for lhs in ['p', 'gp', 'gP', ']p', '[p', ']P', '[P']
            if CanMap(mode, lhs)
                RedirectPutToRegister(mode, lhs, g:vim9cutlass_registers.put)
            endif
        endfor
    endfor

    if g:vim9cutlass_registers.put != '_'
        augroup vim9cutlass_put
        autocmd!
        autocmd TextYankPost * CapturePutReplaced()
        augroup END
    endif
enddef

export def OverrideDefaultMappings()
    OverrideChangeMappings()
    OverrideDeleteMappings()
    OverrideSelectMappings()
    OverridePutMappings()
enddef


export def CreateCutMappings()
    CreateMapping('n', g:vim9cutlass_cut, 'd')
    CreateMapping('x', g:vim9cutlass_cut, 'd')
    CreateMapping('n', g:vim9cutlass_cut .. g:vim9cutlass_cut, 'dd')
    CreateMapping('n', toupper(g:vim9cutlass_cut), 'D')
enddef
