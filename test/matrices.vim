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
#   source      register prefix of a put, such as '"a'
#   op          'c' or 'd', the change or delete a Select key stands for
#   vanilla     key the plugin maps lhs to when it differs from lhs
#   redirected  false for a key the plugin leaves alone
# A repeat in the suffix of a redirected put stands for the plugin's repeat,
# which puts the register over the same amount of text again, so vanilla
# gets [count]v and the put in its place.  The plugin keeps the unnamed
# register pointing at register 0 of the seeds, while vanilla's own put
# leaves the replaced text there, so a put without a register reads 0; a
# put from the configured register puts the replaced text the plugin
# stored there, which vanilla keeps in the unnamed register.
def RepeatPut(keys: string, source: string, register: string, put: string): string
    var again = (source == '"' .. register ? '' : (empty(source) ? '"0' : source)) .. put
    return substitute(keys, '\(\d*\)\.', (m) => (empty(m[1]) ? '1' : m[1]) .. 'v' .. again, 'g')
enddef

export def Build(ctx: dict<any>, spec: dict<any>): dict<any>
    var mode = spec.mode
    var lhs = spec.lhs
    var mapmode = mode =~ "^[vV\<C-V>]$" ? 'x' : (mode == 's' ? 's' : 'n')
    var register = get(spec, 'redirected', true) ? Register(ctx, mapmode, keytrans(lhs), spec.family) : ''
    var prefix = Prefix(register)
    var count = get(spec, 'count', '')
    var tail = get(spec, 'tail', '')
    var prelude = get(spec, 'prelude', '')
    var suffix = get(spec, 'suffix', '')
    var vlhs = get(spec, 'vanilla', lhs)
    var result: dict<any> = {register: register, oracle: 'same'}
    if mode == 's'
        var op = get(spec, 'op', 'c')
        result.keys = prelude .. lhs .. suffix
        result.vanilla = result.keys
        result.vanilla_regs = prelude .. "\<C-O>" .. prefix .. op .. (op == 'c' ? lhs : '') .. suffix
    elseif spec.family == 'put'
        var source = get(spec, 'source', '')
        result.keys = prelude .. source .. count .. lhs .. suffix
        result.vanilla = prelude .. source .. count .. lhs
            .. (empty(register) ? suffix : RepeatPut(suffix, source, register, count .. lhs))
        result.oracle = empty(register) ? 'same' : 'put'
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
    elseif lhs =~ '^\([gP[\]]\?[pP]\)$'
        return 'put'
    endif
    throw 'no register family for ' .. lhs
enddef

# Expands a key template whose {mode:key} tokens stand for keys the plugin
# maps, giving the typed keys and the vanilla keys with register prefixes;
# a {n:.} token is the repeat of the redirected put before it
export def Expand(ctx: dict<any>, template: string): dict<any>
    var result: dict<any> = {keys: '', vanilla: '', vanilla_regs: '', vanilla_prefix: '', register: '', oracle: 'same'}
    var rest = template
    var put: dict<string> = {}
    while true
        var m = matchlist(rest, '^\(.\{-}\){\([nxs]\):\([^}]\+\)}\(.*\)$')
        if empty(m)
            break
        endif
        var [_, before, mode, lhs, after; __] = m
        if lhs =~ '^\d*\.$'
            var repeat = empty(put) ? lhs : RepeatPut(lhs, put.source, put.register, put.key)
            result.keys ..= before .. lhs
            result.vanilla ..= before .. repeat
            result.vanilla_regs ..= before .. repeat
            rest = after
            continue
        endif
        var key = eval('"' .. lhs .. '"')
        var family = mode == 's' ? 'select' : FamilyOf(lhs)
        var register = Register(ctx, mode, lhs, family)
        result.keys ..= before .. key
        if mode == 's'
            result.vanilla ..= before .. key
            result.vanilla_regs ..= before .. "\<C-O>" .. Prefix(register) .. 'c' .. key
        elseif family == 'put'
            # The vanilla keys up to the put give the registers it starts from
            result.vanilla_prefix = result.vanilla .. before
            result.vanilla ..= before .. key
            result.vanilla_regs ..= before .. key
            result.oracle = empty(register) ? 'same' : 'put'
            put = empty(register) ? {} : {source: matchstr(before, '"\S$'), register: register, key: key}
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


# Visual put from every source register over every kind of selection, with
# the counts, clipboard settings and unnamed pointer states that matter.
const put_ops: list<dict<any>> = [
    {lhs: 'p'}, {lhs: 'P', redirected: false}, {lhs: 'gp'}, {lhs: 'gP'},
    {lhs: ']p'}, {lhs: '[p'}, {lhs: ']P'}, {lhs: '[P'},
]
const put_sources = ['', '"0', '"a', '"-', '"1', '"z', '"e', '"*', '"+']
const put_selections = ['ve', 'vjl', 'V', 'Vj', "\<C-V>jl"]
const put_variants: list<dict<any>> = [
    {fixture: 'ascii', seed: 'plain', settings: {}},
    {fixture: 'ascii', seed: 'named', settings: {}},
    {fixture: 'multibyte', seed: 'plain', settings: {}},
    {fixture: 'sparse', seed: 'small', settings: {}},
    {fixture: 'ascii', seed: 'plain', settings: {clipboard: 'unnamed'}},
    {fixture: 'ascii', seed: 'plain', settings: {clipboard: 'unnamedplus'}},
    {fixture: 'ascii', seed: 'plain', settings: {clipboard: 'unnamed,unnamedplus'}},
]

def Put(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', put_ops],
            ['selection', put_selections],
            ['source', put_sources],
            ['count', ['', '2']],
            ['variant', put_variants],
    ])
        var built = Build(ctx, {
            mode: 'v', lhs: combo.op.lhs, family: 'put', prelude: combo.selection,
            source: combo.source, count: combo.count, redirected: get(combo.op, 'redirected', true),
        })
        var parts = [combo.op.lhs, combo.selection, combo.source, combo.count,
            combo.variant.fixture, combo.variant.seed, SettingsId(combo.variant.settings)]
        add(cases, Case('put', filter(copy(parts), (_, p) => !empty(p)),
            extend(copy(combo.variant), built)))
    endfor
    return cases
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
    {mode: 's', lhs: "\<BS>", op: 'd', prelude: "Vj\<C-G>", family: 'select'},
    {mode: 'v', lhs: 'p', prelude: 've', family: 'put'},
    {mode: 'V', lhs: 'p', prelude: 'Vj', source: '"a', family: 'put'},
    {mode: 'v', lhs: 'p', prelude: 've', source: '"1', family: 'put'},
]

def Registers(ctx: dict<any>): list<dict<any>>
    var cases: list<dict<any>> = []
    for combo in Product([
            ['op', register_ops],
            ['seed', keys(fx.seeds)->sort()],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var built = Build(ctx, combo.op)
        var parts = [get(combo.op, 'prelude', '') .. get(combo.op, 'source', '') .. get(combo.op, 'count', '')
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
        {mode: 's', lhs: "\<BS>", op: 'd', prelude: "ve\<C-G>", family: 'select'},
        {mode: 's', lhs: "\<CR>", prelude: "Vj\<C-G>", family: 'select'},
    ],
    put: [
        {mode: 'v', lhs: 'p', prelude: 've', family: 'put'},
        {mode: 'V', lhs: 'p', prelude: 'Vj', family: 'put'},
        {mode: 'v', lhs: 'p', prelude: 've', source: '"a', family: 'put'},
        {mode: "\<C-V>", lhs: 'p', prelude: "\<C-V>jl", family: 'put'},
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
        {mode: 's', lhs: "\<BS>", op: 'd', prelude: "\<C-V>\<S-Right>", family: 'select'},
        {mode: 's', lhs: "\<CR>", prelude: "v\<S-Down>", family: 'select'},
    ],
    keyselect: [
        {mode: 's', lhs: 'X', prelude: "\<S-Right>\<S-Right>", family: 'select'},
        {mode: 's', lhs: "\<BS>", op: 'd', prelude: "\<S-Down>", family: 'select'},
        {mode: 's', lhs: 'X', prelude: "\<S-End>", family: 'select'},
        {mode: 's', lhs: "\<CR>", prelude: "\<S-Right>", family: 'select'},
    ],
    folded: [
        {mode: 'n', lhs: 'dd', prelude: 'zfj', family: 'delete'},
        {mode: 'n', lhs: 'd', tail: 'j', prelude: 'zfj', family: 'delete'},
        {mode: 'n', lhs: 'cc', prelude: 'zfj', family: 'change'},
        {mode: 'n', lhs: 'x', prelude: 'zfj', family: 'delete'},
        {mode: 'V', lhs: 'd', prelude: 'zfjV', family: 'delete'},
        {mode: 'V', lhs: 'p', prelude: 'zfjV', family: 'put'},
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

# Settings that influence change, delete, Select typing or Visual put,
# each crossed with the operation groups it can affect
const settings_table: list<dict<any>> = [
    {settings: {clipboard: 'unnamed'}, groups: ['delete', 'change', 'select', 'put', 'insert']},
    {settings: {clipboard: 'unnamedplus'}, groups: ['delete', 'change', 'select', 'put', 'insert']},
    {settings: {clipboard: 'unnamed,unnamedplus'}, groups: ['delete', 'change', 'select', 'put', 'insert']},
    {settings: {clipboard: 'autoselect'}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {clipboard: 'autoselect,unnamed'}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {clipboard: 'autoselect,unnamedplus'}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {clipboard: 'autoselectplus'}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {clipboard: 'autoselectplus,unnamedplus'}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {clipboard: 'autoselectplus,unnamed'}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {clipboard: 'autoselect,autoselectplus,unnamed,unnamedplus'}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {clipboard: 'exclude:.*'}, groups: ['delete', 'put']},
    {settings: {clipboard: 'unnamed,exclude:.*'}, groups: ['delete', 'put']},
    {settings: {selection: 'exclusive'}, groups: ['delete', 'change', 'select', 'put', 'lineend']},
    {settings: {selection: 'old'}, groups: ['delete', 'change', 'select', 'put', 'lineend']},
    {settings: {selectmode: 'mouse'}, groups: ['delete', 'select']},
    {settings: {selectmode: 'key', keymodel: 'startsel'}, groups: ['keyselect', 'select']},
    {settings: {selectmode: 'cmd', keymodel: 'startsel'}, groups: ['cmdselect', 'insert']},
    {settings: {keymodel: 'startsel'}, groups: ['shifted']},
    {settings: {keymodel: 'stopsel'}, groups: ['delete', 'select']},
    {settings: {keymodel: 'startsel,stopsel'}, groups: ['shifted', 'select']},
    {settings: {virtualedit: 'all'}, groups: ['delete', 'change', 'lineend', 'put']},
    {settings: {virtualedit: 'onemore'}, groups: ['delete', 'change', 'lineend', 'put']},
    {settings: {virtualedit: 'block'}, groups: ['delete', 'change', 'lineend', 'put']},
    {settings: {virtualedit: 'insert'}, groups: ['insert', 'change']},
    {settings: {cpoptions: 'aABceFszy'}, groups: ['repeat', 'delete']},
    {settings: {cpoptions: 'aABceFszE'}, groups: ['empty', 'delete']},
    {settings: {cpoptions: 'aABceFsz$'}, groups: ['change']},
    {settings: {startofline: false}, groups: ['delete', 'change']},
    {settings: {whichwrap: 'b,s,h,l,<,>,[,]'}, groups: ['lineend']},
    {settings: {whichwrap: ''}, groups: ['lineend']},
    {settings: {autoindent: true}, groups: ['change', 'select']},
    {settings: {modifiable: false}, groups: ['delete', 'change', 'select', 'put', 'insert']},
    {settings: {readonly: true}, groups: ['delete', 'change', 'select', 'put', 'insert']},
    {settings: {timeout: false}, groups: ['delete', 'change', 'select']},
    {settings: {timeoutlen: 1}, groups: ['delete', 'change', 'select']},
    {settings: {ttimeout: true, ttimeoutlen: 10}, groups: ['delete', 'change', 'select']},
    {settings: {foldmethod: 'manual'}, groups: ['folded']},
    {settings: {guioptions: default_guioptions}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {guioptions: 'a' .. default_guioptions}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {guioptions: 'A' .. default_guioptions}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {guioptions: 'P' .. default_guioptions}, groups: ['delete', 'change', 'select', 'put']},
    {settings: {guioptions: 'a' .. default_guioptions, clipboard: 'unnamed'}, groups: ['delete', 'put']},
    {settings: {guioptions: 'P' .. default_guioptions, clipboard: 'unnamedplus'}, groups: ['delete', 'put']},
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
    {mode: 's', lhs: "\<BS>", op: 'd', prelude: "ve\<C-G>", family: 'select'},
    {mode: 'v', lhs: 'p', prelude: 've', family: 'put'},
    {mode: 'v', lhs: 'p', prelude: 've', count: '2', family: 'put'},
    {mode: 'V', lhs: 'p', prelude: 'Vj', source: '"a', family: 'put'},
    {mode: 'i', lhs: 'd', tail: 'w', suffix: "\<Esc>", family: 'delete'},
]
const histories = ['.', 'j.', '3.', 'u', "u\<C-R>", '.u', 'uu', 'u.', "u\<C-R>."]

const ex_commands: list<string> = [
    ":delete\<CR>", ":2delete\<CR>", ":1,3delete\<CR>", ":delete a\<CR>", ":delete _\<CR>",
    ":%delete\<CR>", "Vj:delete\<CR>", ":change\<CR>new text\<CR>.\<CR>", ":2,3change\<CR>new\<CR>.\<CR>",
    ":normal {n:d}w\<CR>", ":normal! dw\<CR>", ":normal 2{n:dd}\<CR>", ":normal {n:x}\<CR>",
    ":normal ve{x:d}\<CR>", ":normal {n:cc}NEW\<CR>", ":normal ve{x:p}\<CR>", ":normal Vj\"a{x:p}\<CR>",
    ":normal ve\<C-G>{s:X}\<CR>", ":execute 'normal {n:d}w'\<CR>", "3:normal {n:d}w\<CR>",
    ":normal i\<C-O>{n:d}w\<CR>",
]

# A Visual put followed by a visit to another buffer, with or without a
# change there, and a repeat back in the first buffer.  The put oracle
# takes every register change after the put for a leak, so the changes
# made elsewhere leave the registers alone.
const buffer_commands: list<string> = [
    "ve{x:p}:new\<CR>:bwipeout!\<CR>{n:.}",
    "ve{x:p}:new\<CR>:bwipeout!\<CR>{n:3.}",
    "ve{x:p}:new\<CR>ihello\<Esc>:bwipeout!\<CR>.",
    "ve{x:p}:new\<CR>ihello\<Esc>0rX:bwipeout!\<CR>.",
    "ve{x:p}:new\<CR>ihello\<Esc>:bwipeout!\<CR>3.",
    "Vj\"a{x:p}:new\<CR>ihello\<Esc>0rX:bwipeout!\<CR>.",
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
            ['command', ex_commands + buffer_commands],
            ['fixture', ['ascii', 'multibyte']],
    ])
        var built = Expand(ctx, combo.command)
        var parts = [strtrans(built.keys), combo.fixture]
        add(cases, Case('history', parts, extend({fixture: combo.fixture}, built)))
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
    extend(cases, Put(ctx))
    extend(cases, Registers(ctx))
    extend(cases, Settings(ctx))
    extend(cases, History(ctx))
    return cases
enddef
