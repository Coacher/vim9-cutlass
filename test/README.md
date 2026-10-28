Test suite
==========

The suite checks that vim9-cutlass redirects the text removed by change,
delete and Select typing to the configured register and leaves every other
register alone, in terminal Vim and in gVim, with and without a display
server.

Design
------

Every case is a key sequence a user could type. The harness feeds it twice
in one Vim process: first before the plugin is loaded, then after. The two
runs start from the same buffer, cursor, marks, settings and register
seeds, and the harness compares the buffer, cursor, mode, marks, search
pattern and every register afterwards.

The expected outcome is defined by vanilla Vim, never by hand: the plugin
run of `{keys}` must equal the vanilla run of `"R{keys}`, where R is the
configured register, or of `CTRL-R R {keys}` for text typed over a Select
mode selection. This includes the unnamed register pointing to R afterwards
and the numbered registers shifting as vanilla Vim shifts them.

Keys that vanilla Vim would read differently, such as a Select mode key or
the delete key that ignores register prefixes, carry a separate vanilla
sequence that defines the expected registers.

A reference built this way stays valid across Vim versions and makes
a hand-written expectation unnecessary. Cases that fail show the field by
field difference between what vanilla Vim produced and what the plugin
produced.

A case can carry a known mark naming an accepted plugin limitation. Such
a case is reported as known rather than failed, counted apart in the
summary and exported as skipped in the JUnit report, so it does not fail
the run. A marked case that passes fails the run instead, which keeps the
marks honest. The mark sits on the axis value that produces the cases, next
to what it concerns. One limitation is marked: typing a character outside
printable ASCII over a Select mode selection, which the plugin does not
map.

Matrices
--------

`matrices.vim` generates the cases as products of axes. Nothing is listed
case by case: a new motion, setting or fixture becomes a new axis value.
Where the products of two matrices meet, such as an operation of the
registers matrix under the default seed, the case is generated once.

* `operators`: every change and delete key in Normal, Visual, Insert CTRL-O
  and Replace CTRL-O modes, with counts before the operator and the motion,
  and between the two keys of a doubled operator.
* `motions`: every motion and text object as the target of `c` and `d`,
  from every cursor position of every fixture.
* `select`: typing over a Select mode selection entered through every
  entry Vim offers, from Normal mode and from a suspended Insert or
  Replace edit, with the keys the plugin maps and the ones it leaves to
  Vim.
* `registers`: representative operations of every family against every
  register seed, run under every plugin configuration, including a
  register the user names before the key, with `"` or in Select mode
  with CTRL-R.
* `settings`: each option that influences the operations, crossed with
  the operation groups it can affect.
* `history`: operations followed by repeat, undo and redo, including a
  repeat after an undo, and the same operations driven through `:normal`
  and the Ex commands.
* `modes`: mode changes around the mapped keys, such as Visual kind
  switches, Select hand-overs and Insert excursions.
* `cut`: the cut mappings `g:vim9cutlass_cut` creates.

Plugin configurations live in the same file: the black hole default, named
registers, distinct registers per family, the clipboard registers, an
exclude list, pre-existing user mappings and a cut key. The user mappings
come in every form Vim offers: for one mode, for Visual and Select together
or for every mode, redirecting to a register, running another command or
doing nothing. One configuration makes a key the plugin redirects the cut
key. The register oracle follows the configuration, so an excluded key is
expected to behave like vanilla Vim, a user mapping is expected to win,
with its right-hand side standing in for the key in the vanilla sequence,
and a cut mapping is expected to replace the redirection of its key.

Fixtures and register seeds live in `fixtures.vim`. Every register holds
a distinct value before a case runs, so any unexpected write shows up in
the diff with the register name in it.

Isolation
---------

`run.sh` starts every Vim with an empty environment and a private home,
runtime directory and display. Nothing from the calling session reaches
Vim: no display, no Wayland socket, no D-Bus, no session clipboard. The
display variants are

* `none`: no display server, for terminal Vim only;
* `x11`: a private Xvfb server;
* `wayland`: a private headless sway compositor;
* `xwayland`: that compositor reached only through its Xwayland display.

The compositor is sway rather than weston because a headless weston offers
no data control protocol and no input seat, which leaves terminal Vim
without a clipboard and crashes gVim inside GTK on the first clipboard
write. A display variant whose server binary is missing is reported as
skipped with the binary named, and so is a gVim that cannot run on
a display: a GTK build without the Wayland backend cannot open the
`wayland` display, and the `xwayland` variant covers it under a Wayland
compositor instead. Clipboard cases are skipped on builds without the
clipboard feature, and such builds run on one variant only, as they never
reach a display server and every other variant would repeat that run: on
`none` when it is selected, otherwise on the first selected variant that
starts, and the other variants report them as skipped. A build that reaches
display servers runs every case on the first server it reaches, and
terminal Vim also on `none`, but only the clipboard cases on the other
servers: the other cases never touch a clipboard and reach the same state
under every server. The clipboard cases use a clipboard register or set the
`clipboard` option or a `guioptions` flag that copies the Visual area to
a clipboard register, and the summary of a run limited to them says so.
Each run records whether the clipboard was reachable: a Vim built with the
Wayland feature reaches the clipboard under `wayland`, while a build
without it sees the clipboard registers without reaching a clipboard, and
the suite covers that state as such.

Running locally
---------------

    test/run.sh

Environment variables select what runs:

| Variable   | Meaning                                               |
|------------|-------------------------------------------------------|
| `VIM_BIN`  | terminal Vim binaries, space separated, default `vim` |
| `GVIM_BIN` | gVim binaries, space separated, default `gvim`        |
| `DISPLAYS` | display variants, default `none x11 wayland xwayland` |
| `CONFIGS`  | plugin configurations from `matrices.vim`             |
| `MATRICES` | Vim pattern selecting matrix names                    |
| `CASES`    | Vim pattern selecting case ids                        |
| `RESULTS`  | report directory, default `test/results`              |
| `TIMEOUT`  | seconds per Vim process, default 900                  |
| `VERBOSE`  | `1` prints every report line                          |

An empty `GVIM_BIN` skips the GUI.

For example, a local GTK 2 build is covered with
`GVIM_BIN=/opt/vim-gtk2/bin/gvim test/run.sh`, and one matrix on one
configuration with `MATRICES='^select$' CONFIGS=named test/run.sh`.

Each run writes `report.txt`, `junit.xml` and `results.jsonl` under the
results directory. `results.jsonl` lists the cases that failed, were
skipped or are known failures; JUnit alone lists the passing ones. The JSON
lines of failing cases carry the full expected and actual state.

Distribution coverage
---------------------

    test/docker.sh debian:stable

builds `Dockerfile` on the given base image with the packaged Vim variants
that differ in the features the suite sees and the display servers, then
runs `run.sh` inside with no network as the calling user. Debian's
`vim-nox` is left out, as it only adds language interfaces to `vim.basic`
and yields the same results. Xwayland admits local clients only when it can
resolve their user name, so the script mounts a minimal passwd file with
that user. The GitHub workflow runs the same script for Debian stable, the
Ubuntu LTS and current releases, and Fedora, and uploads the reports.
Failures appear as annotations in the workflow log.

Builds without Vim9 script, such as `vim.tiny`, get a separate check that
sourcing the plugin leaves no mappings behind. Such builds also lack the
eval feature, so the guard in the plugin cannot run and Vim reports every
later line as an error; the check records those messages and passes as long
as no mapping exists afterwards.
