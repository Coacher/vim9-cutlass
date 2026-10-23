vim9script

# Case generation.  Every matrix is a product of axes narrowed by a filter;
# a case records the keys a user types, the vanilla keys that define the
# expected outcome and the oracle that compares the two.
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
#   oracle        'same' compares everything with the vanilla runs, 'put'
#                 expects untouched registers except the configured one
#   register      the plugin register the oracle refers to
#   needs         has() features the case requires

import './fixtures.vim' as fx

export const configs: dict<dict<any>> = {
    black: {registers: {change: '_', delete: '_', select: '_', put: '_'}},
    named: {registers: {change: 'a', delete: 'a', select: 'a', put: 'a'}},
    distinct: {registers: {change: 'a', delete: 'b', select: 'c', put: 'd'}},
    plus: {registers: {change: '+', delete: '+', select: '+', put: '+'}},
    star: {registers: {change: '*', delete: '*', select: '*', put: '*'}},
    exclude: {
        registers: {change: '_', delete: '_', select: '_', put: '_'},
        exclude: ['nd', 'xx', 'nC', 'sa', 's<BS>', 'xp'],
    },
    usermap: {
        registers: {change: '_', delete: '_', select: '_', put: '_'},
        usermaps: {n: {d: '"zd', D: '"zD'}, x: {d: '"zd', c: '"zc'}},
    },
    cut: {
        registers: {change: '_', delete: '_', select: '_', put: '_'},
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
        oracle: 'same',
        register: '_',
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

# Typed keys: the plugin's change keys replace the selection and start
# Insert mode, its delete keys only remove it, and a Tab is not a typed
# key in Select mode at all.  CTRL-H keeps its modifier apart, as the GUI
# and key protocol terminals deliver a keypress.
const select_keys: list<dict<any>> = [
    {key: 'X', op: 'c'}, {key: 'a', op: 'c'}, {key: 'd', op: 'c'}, {key: '1', op: 'c'},
    {key: '|', op: 'c'}, {key: '"', op: 'c'}, {key: '\', op: 'c'}, {key: '<', op: 'c'},
    {key: ' ', op: 'c'}, {key: "\<CR>", op: 'c'}, {key: "\<NL>", op: 'c'}, {key: "\<kEnter>", op: 'c'},
    {key: "\<BS>", op: 'd'}, {key: "\<Del>", op: 'd'}, {key: "\<kDel>", op: 'd'}, {key: "\<*C-H>", op: 'd'},
    {key: "\<Tab>", redirected: false}, {key: 'ю', op: 'c'}, {key: '日', op: 'c'},
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
        # A key the plugin leaves alone keeps the vanilla outcome
        var redirect = empty(register) ? combo.key.key
            : "\<C-O>" .. Prefix(register) .. combo.key.op .. (combo.key.op == 'c' ? combo.key.key : '')
        var parts = [combo.entry.name, combo.key.key, combo.selection, combo.fixture]
        add(cases, Case('select', parts, {
            fixture: combo.fixture,
            settings: extend({selection: combo.selection}, get(combo.entry, 'settings', {})),
            keys: prelude .. combo.key.key,
            vanilla: prelude .. combo.key.key,
            vanilla_regs: prelude .. redirect,
            register: register,
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
    return cases
enddef
