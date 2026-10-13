# Offline harness

Runs a CuteMonitor plugin's real entry scripts (service, desktop widget, bar item, panel)
outside Noctalia, against a fake runtime that follows Noctalia 5.2.1's own rules, and checks
everything they produce. Nothing is registered, enabled or started; it never touches the
plugin's files.

```sh
bash tools/harness/run-ups.sh
```

Needs `python3` and `luau`. Prints one summary line per run and exits non-zero if any run
fails or reports an issue. Build output and logs go to `tools/harness/out/`, which can be
deleted at any time. To check a copy of the plugin instead, set `PLUGIN_DIR` to its folder.

## What it checks

Every tree an entry renders, against rules extracted from Noctalia's source
(`noctalia-5.2.1/`, made by `gen_rules.py`):

- each `ui.*` node's props are ones that type accepts (an unknown prop is ignored by Noctalia)
- enum values (`align`, `justify`, `textAlign`, `fontWeight`, `variant`, `controlSize`,
  `orientation`), color roles with optional `/alpha`, and glyph names
- string callbacks name a function the script defines
- sizes are finite and non-negative; `opacity`, `fillOpacity`, `progress` and graph values
  stay within 0–1
- at most 256 children per node and 32 levels; no `ui.input`/`ui.select`/`ui.scroll` in the bar
- labels hold text, and never a raw translation key

And around the rendering:

- every `noctalia.state.set` value survives Noctalia's Lua-to-JSON conversion (a table with an
  array part loses its other keys; non-string object keys and non-finite numbers are dropped)
- `getConfig` only reads keys the manifest declares for that entry
- every translation lookup finds a string (Noctalia logs each missing key)
- watchers and command results arrive after the current callback, as in Noctalia

The UPS drivers (`ups/`) add behavior checks: the service's whole life (start, outage,
self-test, blip, lost and recovered link, simulations, actions, NUT, a settings change during
a search, no UPS, restart from saved files); every desktop layout option, bar option and
panel section combination against the 16 states the service run records; a click-through
of the panel; and exact date text in each date style.

## What it can't check

Pixel layout and sizes, Noctalia's real timing and CPU budget, and anything only a real UPS
shows (what `pwrstat` answers to actions, how a self-test looks while it runs). Those stay on
the go-live checklist.

## Files

| Path | What it is |
| --- | --- |
| `fake.luau` | The fake Noctalia runtime and the tree validator. |
| `build.py` | Assembles one runnable file per entry (modules inlined, entry wrapped in `LOAD()`). |
| `scenarios.py` | Turns the states a service run records into input for the other runs. |
| `gen_rules.py` | Extracts the rules from a Noctalia source tree. |
| `noctalia-5.2.1/` | Rules and `ui.*` prelude extracted from Noctalia 5.2.1. |
| `ups/` | Drivers for `cutemonitor-ups`. |
| `run-ups.sh` | Runs all of the above for the UPS plugin. |

## Another Noctalia version

Download that release's source tarball, extract it, and generate its rules beside the
5.2.1 ones; then point `rules=` in the run script at the new folder:

```sh
python3 -I tools/harness/gen_rules.py <extracted-source-dir> tools/harness/noctalia-X.Y.Z
```

## Another CuteMonitor plugin

`fake.luau`, `build.py`, `scenarios.py` and `gen_rules.py` are shared. A new plugin gets its
own driver folder (for example `gpu/`) and run script modeled on `ups/` and `run-ups.sh`.
