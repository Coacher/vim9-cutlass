vim9script

# Case generation.  Every matrix is a product of axes narrowed by a filter;
# a case records the keys a user types and the vanilla keys that define the
# expected outcome.
#
# Case fields:
#   id            unique name, selectable with CUTLASS_CASES
#   matrix        matrix name, selectable with CUTLASS_MATRICES
#   fixture       buffer the case starts from, see fixtures.vim
#   cursor        optional cursor override
#   seed          register seed, see fixtures.vim
#   settings      options set for the case
#   keys          keys fed with the plugin loaded
#   vanilla       keys fed without the plugin that define the expected state
#   vanilla_regs  keys fed without the plugin that define the expected
#                 registers, when they differ from vanilla
#   register      the register the plugin redirects the text to, '' when
#                 it leaves the key alone
#   known         the accepted plugin limitation that makes the case fail
#   needs         has() features the case requires

import './fixtures.vim' as fx

export const configs: dict<dict<any>> = {
    black: {registers: {change: '_', delete: '_', select: '_'}},
    named: {registers: {change: 'a', delete: 'a', select: 'a'}},
    distinct: {registers: {change: 'a', delete: 'b', select: 'c'}},
    plus: {registers: {change: '+', delete: '+', select: '+'}},
    star: {registers: {change: '*', delete: '*', select: '*'}},
    exclude: {
        registers: {change: '_', delete: '_', select: '_'},
        exclude: ['nd', 'xx', 'nC', 'sa', 's<BS>'],
    },
    usermap: {
        registers: {change: '_', delete: '_', select: '_'},
        usermaps: {n: {d: '"zd', D: '"zD'}, x: {d: '"zd', c: '"zc'}},
    },
    cut: {
        registers: {change: '_', delete: '_', select: '_'},
        cut: 'm',
    },
}

const fixture_names = keys(fx.fixtures)->sort()

# Crosses the axes in the given order so that ids are stable
export def Product(axes: list<list<any>>): list<dict<any>>
    var result: list<dict<any>> = [{}]
    for [name, values] in axes
        var next: list<dict<any>> = []
        for combo in result
            for value in values
                var extended = copy(combo)
                extended[name] = value
                add(next, extended)
            endfor
        endfor
        result = next
    endfor
    return result
enddef

# Register the plugin uses for a key in a mode, '' when it leaves the key
# alone because of the exclude list or a mapping the user defined first
export def Register(ctx: dict<any>, mode: string, lhs: string, family: string): string
    var config = ctx.config
    if index(get(config, 'exclude', []), mode .. lhs) >= 0
        return ''
    endif
    var usermaps = get(config, 'usermaps', {})
    if has_key(usermaps, mode) && has_key(usermaps[mode], lhs)
        return matchstr(usermaps[mode][lhs], '^"\zs.')
    endif
    return config.registers[family]
enddef

def Prefix(register: string): string
    return empty(register) ? '' : '"' .. register
enddef

# Typed text in Select mode takes its register from CTRL-R
def SelectPrefix(register: string): string
    return empty(register) ? '' : "\<C-R>" .. register
enddef

def Needs(case: dict<any>): list<string>
    var needs: list<string> = []
    if case.register =~ '[*+]'
        add(needs, 'clipboard_working')
    elseif has_key(get(case, 'settings', {}), 'clipboard') || case.keys =~ '"[*+]'
        add(needs, 'clipboard')
    endif
    if has_key(get(case, 'settings', {}), 'guioptions')
        add(needs, 'gui_running')
    endif
    return needs
enddef

def Id(matrix: string, parts: list<any>): string
    return matrix .. '/' .. join(mapnew(parts, (_, p) => keytrans(p)), '/')
enddef

def Case(matrix: string, parts: list<any>, spec: dict<any>): dict<any>
    var case = extend({
        matrix: matrix,
        id: Id(matrix, parts),
        fixture: 'ascii',
        seed: 'plain',
        settings: {},
        register: '_',
        known: '',
    }, spec)
    if !has_key(case, 'vanilla_regs')
        case.vanilla_regs = case.vanilla
    endif
    case.needs = Needs(case)
    return case
enddef


# Operators the plugin redirects, across the modes that can start them.
const operators: list<dict<any>> = [
    {lhs: 'c', family: 'change', modes: ['n', 'x', 'i', 'R'], motion: true},
    {lhs: 'C', family: 'change', modes: ['n', 'x', 'i', 'R']},
    {lhs: 's', family: 'change', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'S', family: 'change', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'cc', family: 'change', modes: ['n', 'i', 'R']},
    {lhs: 'R', family: 'change', modes: ['x']},
    {lhs: 'd', family: 'delete', modes: ['n', 'x', 'i', 'R'], motion: true},
    {lhs: 'D', family: 'delete', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'x', family: 'delete', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'X', family: 'delete', modes: ['n', 'x', 'i', 'R']},
    {lhs: 'dd', family: 'delete', modes: ['n', 'i', 'R']},
    {lhs: "\<Del>", family: 'delete', modes: ['n', 'x', 'i', 'R'], vanilla: 'x', nocount: true},
    {lhs: "\<kDel>", family: 'delete', modes: ['n', 'x', 'i', 'R'], vanilla: 'x', nocount: true},
]

# Visual selections used wherever a case needs a Visual area
export const selections: dict<list<string>> = {
    v: ['ve', 'vjl', 'v$', 'vb'],
    V: ['V', 'Vj', 'Vk'],
    "\<C-V>": ["\<C-V>jl", "\<C-V>j$", "\<C-V>kh"],
}

const counts: dict<list<string>> = {
    none: ['', ''],
    op: ['2', ''],
    motion: ['', '3'],
    both: ['2', '3'],
}

def Operators(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', operators],
            ['mode', ['n', 'v', 'V', "\<C-V>", 'i', 'R']],
            ['count', keys(counts)->sort()],
            ['motion', ['w', 'j', 'iw']],
            ['fixture', fixture_names],
    ])
        var op = combo.op
        var visual = combo.mode =~ "^[vV\<C-V>]$"
        # An operator typed after CTRL-O runs through the Normal mode mapping
        var mapmode = visual ? 'x' : 'n'
        if index(op.modes, visual ? 'x' : combo.mode) < 0
            continue
        endif
        var has_motion = get(op, 'motion', false) && !visual
        if !has_motion && combo.motion != 'w'
            continue
        endif
        var [opcount, mcount] = counts[combo.count]
        if (!has_motion && !empty(mcount)) || (get(op, 'nocount', false) && !empty(opcount))
            continue
        endif
        if visual && !empty(opcount)
            continue
        endif
        var register = Register(ctx, mapmode, keytrans(op.lhs), op.family)
        var redirected = Prefix(register) .. get(op, 'vanilla', op.lhs)
        var tail = has_motion ? mcount .. combo.motion : ''
        var selections_for = visual ? selections[combo.mode] : ['']
        for selection in selections_for
            var prelude = visual ? selection : (combo.mode == 'n' ? '' : combo.mode .. "\<C-O>")
            var parts = [op.lhs, combo.mode, selection, combo.count, has_motion ? combo.motion : '', combo.fixture]
            add(cases, Case('operators', filter(copy(parts), (_, p) => !empty(p)), {
                fixture: combo.fixture,
                keys: prelude .. opcount .. op.lhs .. tail,
                vanilla: prelude .. opcount .. redirected .. tail,
                register: register,
            }))
        endfor
    endfor
    return cases
enddef




# Every motion and text object as the target of the change and delete
# operators in Normal mode, from each cursor position of each fixture.
const motions: list<dict<any>> = [
    {keys: 'w'}, {keys: 'W'}, {keys: 'e'}, {keys: 'E'}, {keys: 'b'}, {keys: 'B'},
    {keys: 'ge'}, {keys: 'gE'}, {keys: '0'}, {keys: '^'}, {keys: '$'},
    {keys: 'h'}, {keys: 'l'}, {keys: 'j'}, {keys: 'k'}, {keys: 'gj'}, {keys: 'gk'},
    {keys: '+'}, {keys: '-'}, {keys: '_'}, {keys: '|'}, {keys: 'G'}, {keys: 'gg'},
    {keys: 'H'}, {keys: 'L'}, {keys: 'M'},
    {keys: 'fe'}, {keys: 'te'}, {keys: 'Fo'}, {keys: 'To'},
    {keys: ';', prelude: 'fe'}, {keys: ',', prelude: 'fe'},
    {keys: '(' }, {keys: ')'}, {keys: '{'}, {keys: '}'}, {keys: '%'},
    {keys: "/line\<CR>"}, {keys: "?one\<CR>"},
    {keys: 'n', prelude: "/line\<CR>"}, {keys: 'N', prelude: "/line\<CR>"},
    {keys: '`a'}, {keys: "'a"}, {keys: '`b'}, {keys: "'b"},
    {keys: '`[', prelude: 'yiw'}, {keys: '`]', prelude: 'yiw'},
    {keys: '`<', prelude: "viw\<Esc>"}, {keys: '`>', prelude: "viw\<Esc>"},
    {keys: '`.', prelude: "ix\<Esc>"}, {keys: '`^', prelude: "ix\<Esc>"},
    {keys: 'iw'}, {keys: 'aw'}, {keys: 'iW'}, {keys: 'aW'},
    {keys: 'is'}, {keys: 'as'}, {keys: 'ip'}, {keys: 'ap'},
    {keys: 'i('}, {keys: 'a('}, {keys: 'ib'}, {keys: 'ab'},
    {keys: 'i{'}, {keys: 'a{'}, {keys: 'i['}, {keys: 'a['}, {keys: 'i<'}, {keys: 'a<'},
    {keys: 'i"'}, {keys: 'a"'}, {keys: "i'"}, {keys: "a'"}, {keys: 'i`'},
    {keys: 'it'}, {keys: 'at'},
    {keys: 'gn', prelude: "/line\<CR>gg"}, {keys: 'gN', prelude: "/line\<CR>G"},
    {keys: 'vj'}, {keys: 'Vw'}, {keys: "\<C-V>j"}, {keys: 'v$'}, {keys: 'viw'},
]

def Motions(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', ['d', 'c']],
            ['motion', motions],
            ['count', ['', '2']],
            ['fixture', fixture_names],
    ])
        var family = combo.op == 'd' ? 'delete' : 'change'
        var register = Register(ctx, 'n', combo.op, family)
        var prelude = get(combo.motion, 'prelude', '')
        for cursor in fx.fixtures[combo.fixture].cursors
            var parts = [combo.op, combo.motion.keys, combo.count, combo.fixture, join(cursor, ',')]
            add(cases, Case('motions', filter(copy(parts), (_, p) => !empty(p)), {
                fixture: combo.fixture,
                cursor: cursor,
                keys: prelude .. combo.op .. combo.count .. combo.motion.keys,
                vanilla: prelude .. Prefix(register) .. combo.op .. combo.count .. combo.motion.keys,
                register: register,
            }))
        endfor
    endfor
    return cases
enddef


# Typing over a Select mode selection, entered every way Vim offers from
# Normal mode and from a suspended Insert or Replace edit, with the keys
# the plugin maps and the ones it leaves alone.
const select_entries: list<dict<any>> = [
    {name: 'gh', prelude: 'gh'},
    {name: 'gH', prelude: 'gH'},
    {name: 'g<C-H>', prelude: "g\<C-H>"},
    {name: 'v<C-G>', prelude: "ve\<C-G>"},
    {name: 'V<C-G>', prelude: "Vj\<C-G>"},
    {name: '<C-V><C-G>', prelude: "\<C-V>jl\<C-G>"},
    {name: 'gh<S-Right>', prelude: "gh\<S-Right>\<S-Right>", settings: {keymodel: 'startsel'}},
    {name: 'gH<S-Down>', prelude: "gH\<S-Down>", settings: {keymodel: 'startsel'}},
    {name: 'selectmode=cmd', prelude: "v\<S-Right>", settings: {selectmode: 'cmd', keymodel: 'startsel'}},
    {name: 'selectmode=cmd-V', prelude: 'V', settings: {selectmode: 'cmd'}},
    {name: 'selectmode=key', prelude: "\<S-Right>\<S-Right>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'selectmode=key<S-Down>', prelude: "\<S-Down>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'i<S-Right>', prelude: "i\<S-Right>\<S-Right>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'i<S-Down>', prelude: "i\<S-Down>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'R<S-Right>', prelude: "R\<S-Right>\<S-Right>", settings: {selectmode: 'key', keymodel: 'startsel'}},
    {name: 'i<C-O>gh', prelude: "i\<C-O>gh"},
    {name: 'i<C-O>v<C-G>', prelude: "i\<C-O>ve\<C-G>"},
    {name: 'R<C-O>v<C-G>', prelude: "R\<C-O>ve\<C-G>"},
]

# Typed keys: the ones the plugin maps, a Tab that is not a typed key in
# Select mode at all, and characters outside printable ASCII, which the
# plugin does not map, so that Vim's own replacement runs.  CTRL-H keeps
# its modifier apart, as the GUI and key protocol terminals deliver a
# keypress.
const multibyte_select_known = 'multibyte Select typing is not redirected'
const select_keys: list<dict<any>> = [
    {key: 'X'}, {key: 'a'}, {key: 'd'}, {key: '1'},
    {key: '|'}, {key: '"'}, {key: '\'}, {key: '<'},
    {key: ' '}, {key: "\<CR>"}, {key: "\<NL>"}, {key: "\<kEnter>"},
    {key: "\<BS>"}, {key: "\<Del>"}, {key: "\<kDel>"}, {key: "\<*C-H>"},
    {key: "\<Tab>", redirected: false},
    {key: 'ю', known: multibyte_select_known},
    {key: '日', known: multibyte_select_known},
]

def Select(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['entry', select_entries],
            ['key', select_keys],
            ['selection', ['inclusive', 'exclusive']],
            ['fixture', fixture_names],
    ])
        var register = get(combo.key, 'redirected', true)
            ? Register(ctx, 's', keytrans(combo.key.key), 'select') : ''
        var prelude = combo.entry.prelude
        var parts = [combo.entry.name, combo.key.key, combo.selection, combo.fixture]
        add(cases, Case('select', parts, {
            fixture: combo.fixture,
            settings: extend({selection: combo.selection}, get(combo.entry, 'settings', {})),
            keys: prelude .. combo.key.key,
            vanilla: prelude .. combo.key.key,
            vanilla_regs: prelude .. SelectPrefix(register) .. combo.key.key,
            register: register,
            known: get(combo.key, 'known', ''),
        }))
    endfor
    return cases
enddef


def SettingsId(settings: dict<any>): string
    return join(mapnew(sort(keys(settings)), (_, k) => k .. '=' .. string(settings[k])->trim("'")), ',')
enddef

# Builds the keys of one operation from a spec:
#   mode        'n', 'v', 'V', "\<C-V>", 'i', 'R' or 's' for Select typing
#   lhs         operator or typed key
#   tail        motion after a Normal mode operator
#   count       count before the operator
#   prelude     keys fed first, such as a selection or a cursor move
#   suffix      keys fed after the operation
#   family      plugin register family
#   vanilla     key the plugin maps lhs to when it differs from lhs
export def Build(ctx: dict<any>, spec: dict<any>): dict<any>
    var mode = spec.mode
    var lhs = spec.lhs
    var mapmode = mode =~ "^[vV\<C-V>]$" ? 'x' : (mode == 's' ? 's' : 'n')
    var register = Register(ctx, mapmode, keytrans(lhs), spec.family)
    var prefix = Prefix(register)
    var count = get(spec, 'count', '')
    var tail = get(spec, 'tail', '')
    var prelude = get(spec, 'prelude', '')
    var suffix = get(spec, 'suffix', '')
    var vlhs = get(spec, 'vanilla', lhs)
    var result: dict<any> = {register: register}
    if mode == 's'
        result.keys = prelude .. lhs .. suffix
        result.vanilla = result.keys
        result.vanilla_regs = prelude .. SelectPrefix(register) .. lhs .. suffix
    elseif mode == 'i' || mode == 'R'
        result.keys = prelude .. mode .. "\<C-O>" .. count .. lhs .. tail .. suffix
        result.vanilla = prelude .. mode .. "\<C-O>" .. count .. prefix .. vlhs .. tail .. suffix
    else
        result.keys = prelude .. count .. lhs .. tail .. suffix
        result.vanilla = prelude .. count .. prefix .. vlhs .. tail .. suffix
    endif
    return result
enddef

def FamilyOf(lhs: string): string
    if lhs =~ '^\([cCsSR]\|cc\)$'
        return 'change'
    elseif lhs =~ '^\([dDxX]\|dd\|<k\?Del>\)$'
        return 'delete'
    endif
    throw 'no register family for ' .. lhs
enddef

# Expands a key template whose {mode:key} tokens stand for keys the plugin
# maps, giving the typed keys and the vanilla keys with register prefixes
export def Expand(ctx: dict<any>, template: string): dict<any>
    var result: dict<any> = {keys: '', vanilla: '', vanilla_regs: '', register: ''}
    var rest = template
    while true
        var m = matchlist(rest, '^\(.\{-}\){\([nxs]\):\([^}]\+\)}\(.*\)$')
        if empty(m)
            break
        endif
        var [_, before, mode, lhs, after; __] = m
        var key = eval('"' .. lhs .. '"')
        var family = mode == 's' ? 'select' : FamilyOf(lhs)
        var register = Register(ctx, mode, lhs, family)
        result.keys ..= before .. key
        if mode == 's'
            result.vanilla ..= before .. key
            result.vanilla_regs ..= before .. SelectPrefix(register) .. key
        else
            result.vanilla ..= before .. Prefix(register) .. key
            result.vanilla_regs ..= before .. Prefix(register) .. key
        endif
        if !empty(register)
            result.register = register
        endif
        rest = after
    endwhile
    result.keys ..= rest
    result.vanilla ..= rest
    result.vanilla_regs ..= rest
    return result
enddef


# Representative operations of every family against every register seed,
# so that numbered shifting, the small delete register and the unnamed
# pointer are checked under every plugin configuration.
const register_ops: list<dict<any>> = [
    {mode: 'n', lhs: 'd', tail: 'w', family: 'delete'},
    {mode: 'n', lhs: 'dd', family: 'delete'},
    {mode: 'n', lhs: 'dd', count: '3', family: 'delete'},
    {mode: 'n', lhs: 'd', tail: '2j', family: 'delete'},
    {mode: 'n', lhs: 'x', family: 'delete'},
    {mode: 'n', lhs: 'D', family: 'delete'},
    {mode: 'n', lhs: 'd', tail: 'w', prelude: '"a', family: 'delete'},
    {mode: 'n', lhs: 'd', tail: 'w', prelude: '"A', family: 'delete'},
    {mode: 'n', lhs: 'dd', prelude: '"+', family: 'delete'},
    {mode: 'n', lhs: 'x', prelude: '"_', family: 'delete'},
    {mode: 'n', lhs: 'c', tail: 'w', family: 'change'},
    {mode: 'n', lhs: 'cc', family: 'change'},
    {mode: 'n', lhs: 's', family: 'change'},
    {mode: 'v', lhs: 'd', prelude: 've', family: 'delete'},
    {mode: 'V', lhs: 'd', prelude: 'Vj', family: 'delete'},
    {mode: "\<C-V>", lhs: 'd', prelude: "\<C-V>jl", family: 'delete'},
    {mode: 'v', lhs: 'c', prelude: 'vjl', family: 'change'},
    {mode: 's', lhs: 'X', prelude: "ve\<C-G>", family: 'select'},
    {mode: 's', lhs: "\<BS>", prelude: "Vj\<C-G>", family: 'select'},
]

def Registers(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', register_ops],
            ['seed', keys(fx.seeds)->sort()],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var built = Build(ctx, combo.op)
        var parts = [get(combo.op, 'prelude', '') .. get(combo.op, 'count', '')
            .. combo.op.lhs .. get(combo.op, 'tail', ''), combo.seed, combo.fixture]
        add(cases, Case('registers', parts, extend({fixture: combo.fixture, seed: combo.seed}, built)))
    endfor
    return cases
enddef


# Operations grouped by what a setting can influence
const setting_ops: dict<list<dict<any>>> = {
    delete: [
        {mode: 'n', lhs: 'd', tail: 'w', family: 'delete'},
        {mode: 'n', lhs: 'dd', family: 'delete'},
        {mode: 'n', lhs: 'x', family: 'delete'},
        {mode: 'n', lhs: 'D', family: 'delete'},
        {mode: 'v', lhs: 'd', prelude: 've', family: 'delete'},
        {mode: 'V', lhs: 'd', prelude: 'Vj', family: 'delete'},
        {mode: "\<C-V>", lhs: 'd', prelude: "\<C-V>jl", family: 'delete'},
    ],
    change: [
        {mode: 'n', lhs: 'c', tail: 'w', family: 'change'},
        {mode: 'n', lhs: 'cc', family: 'change'},
        {mode: 'n', lhs: 'S', family: 'change'},
        {mode: 'n', lhs: 'C', family: 'change'},
        {mode: 'v', lhs: 'c', prelude: 'vjl', family: 'change'},
        {mode: 'V', lhs: 'c', prelude: 'Vj', family: 'change'},
    ],
    select: [
        {mode: 's', lhs: 'X', prelude: "ve\<C-G>", family: 'select'},
        {mode: 's', lhs: "\<BS>", prelude: "ve\<C-G>", family: 'select'},
        {mode: 's', lhs: "\<CR>", prelude: "Vj\<C-G>", family: 'select'},
    ],
    insert: [
        {mode: 'i', lhs: 'd', tail: 'w', family: 'delete'},
        {mode: 'i', lhs: 'c', tail: 'w', family: 'change'},
        {mode: 'R', lhs: 'x', family: 'delete'},
    ],
    lineend: [
        {mode: 'n', lhs: 'x', prelude: '$', family: 'delete'},
        {mode: 'n', lhs: 'x', prelude: '$', count: '3', family: 'delete'},
        {mode: 'n', lhs: 'X', prelude: '0', family: 'delete'},
        {mode: 'n', lhs: 'd', tail: 'l', prelude: '$', family: 'delete'},
        {mode: 'n', lhs: 'd', tail: 'h', prelude: '0', family: 'delete'},
        {mode: 'n', lhs: 'd', tail: ' ', prelude: '$', family: 'delete'},
        {mode: 'n', lhs: 'd', tail: "\<BS>", prelude: '0', family: 'delete'},
        {mode: 'n', lhs: 'd', tail: '$', prelude: '$', family: 'delete'},
        {mode: 'v', lhs: 'd', prelude: '$v', family: 'delete'},
        {mode: 'v', lhs: 'd', prelude: 'v$', family: 'delete'},
    ],
    shifted: [
        {mode: 'v', lhs: 'd', prelude: "\<S-Right>\<S-Right>", family: 'delete'},
        {mode: 'v', lhs: 'd', prelude: "\<S-Down>", family: 'delete'},
        {mode: 'v', lhs: 'x', prelude: "v\<S-Right>", family: 'delete'},
        {mode: 'v', lhs: 'c', prelude: "\<S-End>", family: 'change'},
        {mode: 's', lhs: 'X', prelude: "gh\<S-Right>", family: 'select'},
    ],
    cmdselect: [
        {mode: 's', lhs: 'X', prelude: "v\<S-Right>", family: 'select'},
        {mode: 's', lhs: 'X', prelude: 'V', family: 'select'},
        {mode: 's', lhs: "\<BS>", prelude: "\<C-V>\<S-Right>", family: 'select'},
        {mode: 's', lhs: "\<CR>", prelude: "v\<S-Down>", family: 'select'},
    ],
    keyselect: [
        {mode: 's', lhs: 'X', prelude: "\<S-Right>\<S-Right>", family: 'select'},
        {mode: 's', lhs: "\<BS>", prelude: "\<S-Down>", family: 'select'},
        {mode: 's', lhs: 'X', prelude: "\<S-End>", family: 'select'},
        {mode: 's', lhs: "\<CR>", prelude: "\<S-Right>", family: 'select'},
    ],
    folded: [
        {mode: 'n', lhs: 'dd', prelude: 'zfj', family: 'delete'},
        {mode: 'n', lhs: 'd', tail: 'j', prelude: 'zfj', family: 'delete'},
        {mode: 'n', lhs: 'cc', prelude: 'zfj', family: 'change'},
        {mode: 'n', lhs: 'x', prelude: 'zfj', family: 'delete'},
        {mode: 'V', lhs: 'd', prelude: 'zfjV', family: 'delete'},
    ],
    repeat: [
        {mode: 'n', lhs: 'd', tail: 'w', suffix: '.', family: 'delete'},
        {mode: 'n', lhs: 'x', suffix: 'yiw.', family: 'delete'},
        {mode: 'n', lhs: 'c', tail: 'w', suffix: "NEW\<Esc>j.", family: 'change'},
    ],
    empty: [
        {mode: 'n', lhs: 'd', tail: '0', prelude: '0', family: 'delete'},
        {mode: 'v', lhs: 'd', prelude: 'v', fixture: 'sparse', family: 'delete'},
        {mode: 'n', lhs: 'c', tail: 'w', fixture: 'sparse', family: 'change'},
        {mode: 'n', lhs: 'd', tail: 'iw', fixture: 'sparse', family: 'delete'},
        {mode: 'n', lhs: 'x', fixture: 'sparse', family: 'delete'},
    ],
}

const default_guioptions = 'egimrLtT'

# Settings that influence change, delete or Select typing,
# each crossed with the operation groups it can affect
const settings_table: list<dict<any>> = [
    {settings: {clipboard: 'unnamed'}, groups: ['delete', 'change', 'select', 'insert']},
    {settings: {clipboard: 'unnamedplus'}, groups: ['delete', 'change', 'select', 'insert']},
    {settings: {clipboard: 'unnamed,unnamedplus'}, groups: ['delete', 'change', 'select', 'insert']},
    {settings: {clipboard: 'autoselect'}, groups: ['delete', 'change', 'select']},
    {settings: {clipboard: 'autoselect,unnamed'}, groups: ['delete', 'change', 'select']},
    {settings: {clipboard: 'autoselect,unnamedplus'}, groups: ['delete', 'change', 'select']},
    {settings: {clipboard: 'autoselectplus'}, groups: ['delete', 'change', 'select']},
    {settings: {clipboard: 'autoselectplus,unnamedplus'}, groups: ['delete', 'change', 'select']},
    {settings: {clipboard: 'autoselectplus,unnamed'}, groups: ['delete', 'change', 'select']},
    {settings: {clipboard: 'autoselect,autoselectplus,unnamed,unnamedplus'}, groups: ['delete', 'change', 'select']},
    {settings: {clipboard: 'exclude:.*'}, groups: ['delete']},
    {settings: {clipboard: 'unnamed,exclude:.*'}, groups: ['delete']},
    {settings: {selection: 'exclusive'}, groups: ['delete', 'change', 'select', 'lineend']},
    {settings: {selection: 'old'}, groups: ['delete', 'change', 'select', 'lineend']},
    {settings: {selectmode: 'mouse'}, groups: ['delete', 'select']},
    {settings: {selectmode: 'key', keymodel: 'startsel'}, groups: ['keyselect', 'select']},
    {settings: {selectmode: 'cmd', keymodel: 'startsel'}, groups: ['cmdselect', 'insert']},
    {settings: {keymodel: 'startsel'}, groups: ['shifted']},
    {settings: {keymodel: 'stopsel'}, groups: ['delete', 'select']},
    {settings: {keymodel: 'startsel,stopsel'}, groups: ['shifted', 'select']},
    {settings: {virtualedit: 'all'}, groups: ['delete', 'change', 'lineend']},
    {settings: {virtualedit: 'onemore'}, groups: ['delete', 'change', 'lineend']},
    {settings: {virtualedit: 'block'}, groups: ['delete', 'change', 'lineend']},
    {settings: {virtualedit: 'insert'}, groups: ['insert', 'change']},
    {settings: {cpoptions: 'aABceFszy'}, groups: ['repeat', 'delete']},
    {settings: {cpoptions: 'aABceFszE'}, groups: ['empty', 'delete']},
    {settings: {cpoptions: 'aABceFsz$'}, groups: ['change']},
    {settings: {startofline: false}, groups: ['delete', 'change']},
    {settings: {whichwrap: 'b,s,h,l,<,>,[,]'}, groups: ['lineend']},
    {settings: {whichwrap: ''}, groups: ['lineend']},
    {settings: {autoindent: true}, groups: ['change', 'select']},
    {settings: {modifiable: false}, groups: ['delete', 'change', 'select', 'insert']},
    {settings: {readonly: true}, groups: ['delete', 'change', 'select', 'insert']},
    {settings: {timeout: false}, groups: ['delete', 'change', 'select']},
    {settings: {timeoutlen: 1}, groups: ['delete', 'change', 'select']},
    {settings: {ttimeout: true, ttimeoutlen: 10}, groups: ['delete', 'change', 'select']},
    {settings: {foldmethod: 'manual'}, groups: ['folded']},
    {settings: {guioptions: default_guioptions}, groups: ['delete', 'change', 'select']},
    {settings: {guioptions: 'a' .. default_guioptions}, groups: ['delete', 'change', 'select']},
    {settings: {guioptions: 'A' .. default_guioptions}, groups: ['delete', 'change', 'select']},
    {settings: {guioptions: 'P' .. default_guioptions}, groups: ['delete', 'change', 'select']},
    {settings: {guioptions: 'a' .. default_guioptions, clipboard: 'unnamed'}, groups: ['delete']},
    {settings: {guioptions: 'P' .. default_guioptions, clipboard: 'unnamedplus'}, groups: ['delete']},
]

def Settings(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for entry in settings_table
        for group in entry.groups
            for spec in setting_ops[group]
                for fixture in has_key(spec, 'fixture') ? [spec.fixture] : ['ascii', 'indented']
                    var built = Build(ctx, spec)
                    var parts = [SettingsId(entry.settings), group, strtrans(built.keys), fixture]
                    add(cases, Case('settings', parts, extend({
                        fixture: fixture,
                        settings: entry.settings,
                    }, built)))
                endfor
            endfor
        endfor
    endfor
    return cases
enddef


# Operations followed by repeat, undo and redo, and the same operations
# driven through :normal and the Ex commands that remove text
const history_ops: list<dict<any>> = [
    {mode: 'n', lhs: 'd', tail: 'w', family: 'delete'},
    {mode: 'n', lhs: 'dd', family: 'delete'},
    {mode: 'n', lhs: 'dd', count: '2', family: 'delete'},
    {mode: 'n', lhs: 'x', family: 'delete'},
    {mode: 'n', lhs: 'X', family: 'delete'},
    {mode: 'n', lhs: 'D', family: 'delete'},
    {mode: 'n', lhs: "\<Del>", vanilla: 'x', family: 'delete'},
    {mode: 'n', lhs: 'c', tail: 'w', suffix: "NEW\<Esc>", family: 'change'},
    {mode: 'n', lhs: 'cc', suffix: "NEW\<Esc>", family: 'change'},
    {mode: 'n', lhs: 's', suffix: "NEW\<Esc>", family: 'change'},
    {mode: 'v', lhs: 'd', prelude: 've', family: 'delete'},
    {mode: 'V', lhs: 'd', prelude: 'Vj', family: 'delete'},
    {mode: "\<C-V>", lhs: 'd', prelude: "\<C-V>jl", family: 'delete'},
    {mode: 'v', lhs: 'c', prelude: 'vjl', suffix: "NEW\<Esc>", family: 'change'},
    {mode: 's', lhs: 'X', prelude: "ve\<C-G>", suffix: "\<Esc>", family: 'select'},
    {mode: 's', lhs: "\<BS>", prelude: "ve\<C-G>", family: 'select'},
    {mode: 'i', lhs: 'd', tail: 'w', suffix: "\<Esc>", family: 'delete'},
]
const histories = ['.', 'j.', '3.', 'u', "u\<C-R>", '.u', 'uu', 'u.', "u\<C-R>."]

const ex_commands: list<string> = [
    ":delete\<CR>", ":2delete\<CR>", ":1,3delete\<CR>", ":delete a\<CR>", ":delete _\<CR>",
    ":%delete\<CR>", "Vj:delete\<CR>", ":change\<CR>new text\<CR>.\<CR>", ":2,3change\<CR>new\<CR>.\<CR>",
    ":normal {n:d}w\<CR>", ":normal! dw\<CR>", ":normal 2{n:dd}\<CR>", ":normal {n:x}\<CR>",
    ":normal ve{x:d}\<CR>", ":normal {n:cc}NEW\<CR>",
    ":normal ve\<C-G>{s:X}\<CR>", ":execute 'normal {n:d}w'\<CR>", "3:normal {n:d}w\<CR>",
    ":normal i\<C-O>{n:d}w\<CR>",
]

def History(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', history_ops],
            ['history', histories],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var spec = extend(copy(combo.op), {suffix: get(combo.op, 'suffix', '') .. combo.history})
        var built = Build(ctx, spec)
        var parts = [strtrans(built.keys), combo.fixture]
        add(cases, Case('history', parts, extend({fixture: combo.fixture}, built)))
    endfor
    for combo in Product([
            ['command', ex_commands],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var built = Expand(ctx, combo.command)
        var parts = [strtrans(built.keys), combo.fixture]
        add(cases, Case('history', parts, extend({fixture: combo.fixture}, built)))
    endfor
    return cases
enddef


# Operations that cross mode boundaries before or after the key the plugin
# maps: Visual kind switches, Select and Visual hand-overs, Insert and
# Replace excursions.  Templates mark the mapped keys with {mode:key}.
const mode_templates: list<string> = [
    "vjV{x:d}", "Vjv{x:D}", "vj\<C-V>{x:d}", "\<C-V>jlv{x:d}", "\<C-V>jlV{x:c}",
    "vjo{x:d}", "vjO{x:c}", "\<C-V>jlO{x:d}", "\<C-V>jlo{x:x}",
    "ve\<Esc>gv{x:d}", "vj\<Esc>0gv{x:c}", "ve\<Esc>jgv{x:x}",
    "ve\<C-G>\<C-O>{x:d}", "ve\<C-G>\<C-G>{x:d}", "ve\<C-G>\<C-O>\<C-G>{s:X}",
    "gh\<C-O>{x:d}", "gH\<C-O>{x:c}", "ve\<C-G>\<Esc>{n:d}w", "ve\<C-G>\<Esc>{n:x}",
    "vjv{n:d}w", "Vj\<Esc>{n:dd}", "\<C-V>jl\<Esc>{n:x}",
    "ihello\<Esc>{n:d}w", "ihello\<C-O>{n:d}w", "i\<C-\>\<C-O>{n:d}w", "i\<C-O>vj{x:d}",
    "i\<C-O>V{x:d}", "i\<C-O>ve{x:c}", "i\<C-O>{n:dd}", "i\<C-O>{n:x}", "i\<C-O>{n:X}",
    "A\<C-O>{n:D}", "I\<C-O>{n:C}", "a\<C-O>{n:s}", "o\<C-O>{n:S}",
    "R\<C-O>{n:x}", "Rab\<C-O>{n:d}w", "gR\<C-O>{n:d}w", "gRab\<C-O>{n:x}",
    "i\<C-O>ve\<C-G>{s:X}", "i\<C-O>gh{s:X}", "R\<C-O>ve\<C-G>{s:X}",
    "vj:'<,'>delete\<CR>", "Vj:delete\<CR>", "Vj:normal {x:d}\<CR>",
    "{n:d}vj", "{n:d}Vw", "{n:d}\<C-V>j", "{n:c}vj", "{n:d}v$", "{n:c}viw",
    "ve{x:d}{n:d}w", "ve{x:c}NEW\<Esc>{n:x}", "ve\<C-G>{s:X}\<Esc>{n:dd}",
    "ve{x:d}vep", "{n:dd}Vjp",
    "ve\<C-G>{s:X}\<C-O>{n:d}w", "ve\<C-G>{s:X}\<Esc>ve\<C-G>{s:X}",
]

def Modes(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['template', mode_templates],
            ['fixture', ['ascii', 'multibyte', 'single']],
    ])
        var built = Expand(ctx, combo.template)
        add(cases, Case('modes', [strtrans(built.keys), combo.fixture], extend({fixture: combo.fixture}, built)))
    endfor
    return cases
enddef


# The cut mappings: they behave like the delete keys of vanilla Vim and
# only exist when g:vim9cutlass_cut is set.  The cut key shadows the mark
# command and its upper case form is a motion after an operator.
def Cut(ctx: dict<any>): list<dict<any>>
    var cut = get(ctx.config, 'cut', v:null)
    if cut == v:null
        return []
    endif
    var upper = toupper(cut)
    var templates: list<list<string>> = [
        [cut .. 'w', 'dw'], [cut .. 'iw', 'diw'], [cut .. '2j', 'd2j'], ['2' .. cut .. 'w', '2dw'],
        [cut .. cut, 'dd'], ['3' .. cut .. cut, '3dd'], [upper, 'D'], ['2' .. upper, '2D'],
        ['ve' .. cut, 'ved'], ['Vj' .. cut, 'Vjd'], ["\<C-V>jl" .. cut, "\<C-V>jld"],
        ['"a' .. cut .. 'w', '"adw'], ['"A' .. cut .. cut, '"Add'], ['"+' .. upper, '"+D'], ['"_' .. cut .. 'w', '"_dw'],
        [cut .. 'w.', 'dw.'], [cut .. cut .. 'j.', 'ddj.'], [cut .. 'wu', 'dwu'],
        ["i\<C-O>" .. cut .. 'w', "i\<C-O>dw"], ["ve\<C-G>\<C-O>" .. cut, "ve\<C-G>\<C-O>d"],
        [cut .. 'w' .. 'p', 'dwp'], ['ve' .. cut .. 'P', 'vedP'],
        [cut .. upper, 'd' .. upper], ['ma' .. cut .. 'w', 'da' .. cut .. 'w'],
    ]
    var cases: list<dict<any>> = []
    for combo in Product([
            ['template', templates],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var [keys, vanilla] = combo.template
        add(cases, Case('cut', [strtrans(keys), combo.fixture], {
            fixture: combo.fixture,
            keys: keys,
            vanilla: vanilla,
            register: '',
        }))
    endfor
    return cases
enddef


export def Cases(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    extend(cases, Operators(ctx))
    if ctx.config_name =~ '^\(black\|named\)$'
        extend(cases, Motions(ctx))
    endif
    extend(cases, Select(ctx))
    extend(cases, Registers(ctx))
    extend(cases, Settings(ctx))
    extend(cases, History(ctx))
    extend(cases, Modes(ctx))
    extend(cases, Cut(ctx))
    return cases
enddef
