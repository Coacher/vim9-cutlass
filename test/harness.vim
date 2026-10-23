vim9script

# Runs every generated case in vanilla Vim and then in Vim with the plugin
# loaded, compares the two and writes the reports.
#
# run.sh configures the process through environment variables:
#   CUTLASS_CONFIG    plugin configuration name from matrices.vim
#   CUTLASS_DISPLAY   display variant name, recorded in the reports
#   CUTLASS_RESULTS   directory that receives the report files
#   CUTLASS_CASES     optional pattern that selects case ids
#   CUTLASS_MATRICES  optional pattern that selects matrix names

import './fixtures.vim' as fx
import './matrices.vim' as mx

const test_dir = expand('<sfile>:p:h')
const repo_dir = fnamemodify(test_dir, ':h')
const results_dir = $CUTLASS_RESULTS
const config_name = $CUTLASS_CONFIG
const config = mx.configs[config_name]

# Facts about this build that matrices use to decide what to generate
const ctx: dict<any> = {
    config: config,
    config_name: config_name,
    gui: has('gui_running') ? true : false,
    clipboard: has('clipboard') ? true : false,
    clipboard_working: has('clipboard_working') ? true : false,
    display: $CUTLASS_DISPLAY,
    registers: fx.seeded_registers + (has('clipboard') ? ['*', '+'] : []),
}

var snapshot: dict<any> = {}
var saved_options: dict<any> = {}


def Baseline()
    set encoding=utf-8
    set belloff=all
    set nomore
    set noswapfile
    set hidden
    set shortmess+=I
    set noshowmode
    set noshowcmd
    set noruler
    set laststatus=0
    set lazyredraw
    set report=99999
    set nomodeline
    set clipboard=
    if has('gui_running')
        set guioptions-=a
        set guioptions-=A
    endif
    # The snapshot key records the state at the end of the fed keys from
    # inside the mode the keys left Vim in; pending operators are cancelled
    # instead, because a <Cmd> key there blocks waiting for a motion.
    noremap <F10> <Cmd>call g:CutlassSnapshot()<CR>
    noremap! <F10> <Cmd>call g:CutlassSnapshot()<CR>
    onoremap <F10> <Esc>
    cnoremap <F10> <C-C>
enddef

def NewBuffer(fixture: dict<any>, cursor: list<number>)
    silent! bwipeout!
    enew!
    setlocal buftype=nofile bufhidden=wipe noswapfile noundofile
    setlocal undolevels=-1
    setline(1, fixture.lines)
    setlocal undolevels<
    for [name, pos] in items(fixture.marks)
        setpos("'" .. name, [0, pos[0], pos[1], 0])
    endfor
    cursor(cursor[0], cursor[1])
    setlocal nomodified
    # The last Visual mode and area outlive the buffer they were used in
    visualmode(1)
    silent! delmarks < > [ ] . ^
enddef

def ApplySettings(settings: dict<any>)
    saved_options = {}
    for [name, value] in items(settings)
        saved_options[name] = eval('&' .. name)
        execute('&' .. name .. ' = ' .. string(value))
    endfor
enddef

def RestoreSettings()
    for [name, value] in items(saved_options)
        execute('&' .. name .. ' = ' .. string(value))
    endfor
    saved_options = {}
enddef

def SeedRegisters(seed: dict<any>)
    for name in ctx.registers
        if name != '"'
            var regtype = index(seed.linewise, name) >= 0 ? 'V'
                : index(seed.blockwise, name) >= 0 ? "\<C-V>" : 'v'
            setreg(name, [fx.SeedText(name)], regtype)
        endif
    endfor
    setreg('"', {points_to: seed.points_to})
enddef

def Snapshot(): dict<any>
    var marks: dict<any> = {}
    for name in ['[', ']', '<', '>', '.', '^', 'a', 'b']
        marks[name] = getpos("'" .. name)[1 : 2]
    endfor
    var registers: dict<any> = {}
    for name in ctx.registers
        registers[name] = getreginfo(name)
    endfor
    return {
        lines: getline(1, '$'),
        cursor: getcurpos()[1 : 4],
        mode: mode(1),
        visualmode: visualmode(),
        marks: marks,
        registers: registers,
        search: getreg('/'),
        modified: &modified ? true : false,
        errmsg: v:errmsg,
    }
enddef

def g:CutlassSnapshot()
    snapshot = Snapshot()
enddef

# Runs one key sequence from the case's initial state and returns the state
# right after the keys.
def Execute(case: dict<any>, keys: string): dict<any>
    var fixture = fx.fixtures[case.fixture]
    NewBuffer(fixture, get(case, 'cursor', fixture.cursor))
    ApplySettings(get(case, 'settings', {}))
    SeedRegisters(fx.seeds[get(case, 'seed', 'plain')])
    setreg('/', '')
    v:errmsg = ''
    snapshot = {}
    g:CutlassFeed(keys .. "\<F10>")
    var after = empty(snapshot) ? Snapshot() : snapshot
    # Modes that persist after the typeahead ran out, Visual and Select,
    # are only visible here: the snapshot key sees Select as Visual
    after.mode_after = mode(1)
    var tries = 0
    while mode(1) != 'n' && tries < 5
        g:CutlassFeed("\<Esc>")
        tries += 1
    endwhile
    RestoreSettings()
    return after
enddef

def Diff(expected: any, actual: any, path: string, out: list<string>)
    if type(expected) != type(actual)
        add(out, path .. ': expected ' .. string(expected) .. ', actual ' .. string(actual))
    elseif type(expected) == v:t_dict
        for key in sort(keys(expected) + keys(actual))->uniq()
            if !has_key(actual, key)
                add(out, path .. '.' .. key .. ': missing, expected ' .. string(expected[key]))
            elseif !has_key(expected, key)
                add(out, path .. '.' .. key .. ': unexpected ' .. string(actual[key]))
            else
                Diff(expected[key], actual[key], path .. '.' .. key, out)
            endif
        endfor
    elseif expected != actual
        add(out, path .. ': expected ' .. string(expected) .. ', actual ' .. string(actual))
    endif
enddef

def Unmet(case: dict<any>): string
    for need in get(case, 'needs', [])
        if !has(need)
            return 'build lacks ' .. need
        endif
    endfor
    return ''
enddef

def Selected(case: dict<any>): bool
    return (empty($CUTLASS_MATRICES) || case.matrix =~ $CUTLASS_MATRICES)
        && (empty($CUTLASS_CASES) || case.id =~ $CUTLASS_CASES)
enddef

def LoadPlugin()
    g:vim9cutlass_registers = deepcopy(config.registers)
    g:vim9cutlass_exclude = deepcopy(get(config, 'exclude', []))
    g:vim9cutlass_cut = get(config, 'cut', v:null)
    for [mode, maps] in items(get(config, 'usermaps', {}))
        for [lhs, rhs] in items(maps)
            execute(mode .. 'noremap ' .. lhs .. ' ' .. rhs)
        endfor
    endfor
    execute('source ' .. fnameescape(repo_dir .. '/plugin/cutlass.vim'))
    if !exists('g:vim9cutlass_loaded')
        throw 'plugin did not load'
    endif
enddef

def XmlEscape(text: string): string
    return text->substitute('&', '\&amp;', 'g')->substitute('<', '\&lt;', 'g')
        ->substitute('>', '\&gt;', 'g')->substitute('"', '\&quot;', 'g')
        ->substitute('[^[:print:]\t\n]', '', 'g')
enddef

def WriteReports(results: list<dict<any>>, run: string)
    var counts = {PASS: 0, FAIL: 0, SKIP: 0, KNOWN: 0}
    var report: list<string> = []
    var xml: list<string> = ['<?xml version="1.0" encoding="UTF-8"?>']
    var cases: list<string> = []
    for result in results
        counts[result.status] += 1
        var name = XmlEscape(result.id)
        if result.status == 'PASS'
            add(cases, printf('  <testcase classname="%s" name="%s"/>', XmlEscape(run), name))
        elseif result.status == 'SKIP'
            add(cases, printf('  <testcase classname="%s" name="%s"><skipped message="%s"/></testcase>',
                XmlEscape(run), name, XmlEscape(result.reason)))
        elseif result.status == 'KNOWN'
            add(cases, printf('  <testcase classname="%s" name="%s"><skipped type="known" message="%s"/></testcase>',
                XmlEscape(run), name, XmlEscape(result.known)))
        else
            var detail = join(result.diffs, "\n")
            add(report, 'FAIL ' .. result.id)
            extend(report, mapnew(result.diffs, (_, line) => '    ' .. line))
            add(cases, printf('  <testcase classname="%s" name="%s"><failure message="%s">%s</failure></testcase>',
                XmlEscape(run), name, XmlEscape(result.diffs[0]), XmlEscape(detail)))
        endif
    endfor
    var skips: dict<number> = {}
    for result in results
        if result.status == 'SKIP'
            skips[result.reason] = get(skips, result.reason, 0) + 1
        endif
    endfor
    for [reason, count] in items(skips)
        add(report, printf('SKIP %d cases: %s', count, reason))
    endfor
    var knowns: dict<number> = {}
    for result in results
        if result.status == 'KNOWN'
            knowns[result.known] = get(knowns, result.known, 0) + 1
        endif
    endfor
    for [reason, count] in items(knowns)
        add(report, printf('KNOWN %d cases: %s', count, reason))
    endfor
    add(report, printf('SUMMARY %s: %d passed, %d failed, %d skipped, %d known, clipboard %s',
        run, counts.PASS, counts.FAIL, counts.SKIP, counts.KNOWN,
        ctx.clipboard_working ? 'working' : (ctx.clipboard ? 'present' : 'absent')))
    add(xml, printf('<testsuite name="%s" tests="%d" failures="%d" skipped="%d">',
        XmlEscape(run), len(results), counts.FAIL, counts.SKIP + counts.KNOWN))
    extend(xml, cases)
    add(xml, '</testsuite>')
    writefile(report, results_dir .. '/report.txt')
    writefile(xml, results_dir .. '/junit.xml')
    writefile(mapnew(results, (_, r) => json_encode(r)), results_dir .. '/results.jsonl')
enddef

def Main()
    Baseline()
    var run = printf('%s/%s/%s', ctx.display, config_name, ctx.gui ? 'gui' : 'term')
    var cases = filter(mx.Cases(ctx), (_, c) => Selected(c))
    var ids: dict<bool> = {}
    for case in cases
        if has_key(ids, case.id)
            throw 'duplicate case id ' .. case.id
        endif
        ids[case.id] = true
    endfor
    var vanilla: dict<any> = {}
    var registers: dict<any> = {}
    for case in cases
        if !empty(Unmet(case))
            continue
        endif
        vanilla[case.id] = Execute(case, case.vanilla)
        registers[case.id] = case.vanilla_regs == case.vanilla
            ? vanilla[case.id] : Execute(case, case.vanilla_regs)
    endfor
    LoadPlugin()
    var results: list<dict<any>> = []
    for case in cases
        var unmet = Unmet(case)
        if !empty(unmet)
            add(results, {id: case.id, matrix: case.matrix, status: 'SKIP', reason: unmet})
            continue
        endif
        var plugin = Execute(case, case.keys)
        # The vanilla run of the keys defines the expected state, with the
        # registers of the vanilla run that carries the register prefixes
        var expected = extend(copy(vanilla[case.id]), {registers: registers[case.id].registers})
        var diffs: list<string> = []
        Diff(expected, plugin, '', diffs)
        var status = empty(diffs) ? 'PASS' : 'FAIL'
        if !empty(case.known)
            # A marked case has to keep failing, or its mark is stale
            status = empty(diffs) ? 'FAIL' : 'KNOWN'
            if empty(diffs)
                add(diffs, 'known failure passes: ' .. case.known)
            endif
        endif
        var result = {
            id: case.id, matrix: case.matrix,
            status: status,
            diffs: diffs,
            known: case.known,
            keys: strtrans(case.keys), vanilla: strtrans(case.vanilla),
        }
        if !empty(diffs)
            extend(result, {expected: expected, actual: plugin})
        endif
        add(results, result)
    endfor
    WriteReports(results, run)
    execute(indexof(results, (_, r) => r.status == 'FAIL') >= 0 ? 'cquit!' : 'qall!')
enddef

try
    Main()
catch
    writefile(['HARNESS ERROR ' .. v:exception .. ' @ ' .. v:throwpoint], results_dir .. '/report.txt')
    cquit!
endtry
