vim9script

# Buffer fixtures and register seeds shared by every matrix.
#
# A fixture is the buffer a case starts from: its lines, the cursor position
# the case uses unless it names another one, further cursor positions that
# put text objects in reach, and the marks that are set before any key is
# fed.  Register seeds give every register a distinct,
# recognizable value so that an unexpected write is visible in the diff.

export const fixtures: dict<dict<any>> = {
    ascii: {
        lines: [
            'one two three four five',
            '  indented (paren) "quoted" <tag>text</tag> end',
            '',
            'alpha beta gamma delta epsilon.  Second sentence here.',
            'last line of the first paragraph',
            '',
            'second paragraph line one',
            'second paragraph line two',
        ],
        cursor: [1, 5],
        cursors: [[1, 5], [2, 14], [2, 23], [2, 36], [4, 20], [8, 1]],
        marks: {a: [4, 7], b: [7, 1]},
    },
    multibyte: {
        lines: [
            'раз два три четыре пять',
            '日本語 テキスト の 行',
            'café naïve (скобки) "кавычки"',
            'mixed ascii and кириллица words',
            '',
            'tail line',
        ],
        cursor: [1, 5],
        cursors: [[1, 5], [2, 7], [3, 20], [4, 25]],
        marks: {a: [3, 7], b: [6, 1]},
    },
    indented: {
        lines: [
            "\tfirst tab line",
            "\t\tsecond tab line",
            '    four spaces',
            "\tif (cond) {",
            "\t\tbody;",
            "\t}",
            'trailing spaces   ',
            'end',
        ],
        cursor: [4, 10],
        cursors: [[4, 10], [1, 3], [5, 4], [7, 16]],
        marks: {a: [2, 3], b: [8, 1]},
    },
    sparse: {
        lines: ['a', '', '', 'bb', '', 'ccc', ''],
        cursor: [4, 1],
        cursors: [[4, 1], [2, 1], [7, 1]],
        marks: {a: [1, 1], b: [6, 2]},
    },
    single: {
        lines: ['only one line here'],
        cursor: [1, 6],
        cursors: [[1, 6], [1, 1], [1, 18]],
        marks: {a: [1, 1], b: [1, 10]},
    },
}

# Registers seeded before every execution.  The clipboard registers are
# added by the harness when the build can reach a display server.
export const seeded_registers: list<string> =
    ['"', '-', '0', '1', '2', '3', '4', '5', '6', '7', '8', '9']
    + ['a', 'b', 'c', 'd', 'e', 'z']

# Seeds differ in where the unnamed register points and in which registers
# hold linewise or blockwise text, so that a wrong pointer or type is
# observable.
export const seeds: dict<dict<any>> = {
    plain: {points_to: '0', linewise: ['1', 'z'], blockwise: ['e']},
    named: {points_to: 'a', linewise: ['a', '4'], blockwise: ['b']},
    numbered: {points_to: '1', linewise: ['1', '2', '3'], blockwise: []},
    small: {points_to: '-', linewise: [], blockwise: ['z']},
}

export def SeedText(name: string): string
    return 'seed register ' .. name
enddef
