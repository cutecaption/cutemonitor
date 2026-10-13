# CuteMonitor design language

How the CuteMonitor tools look, behave and are built, written down from the first one
(`cutemonitor-ups`) so later tools (a GPU monitor is next) start from the same platform.
Every value here is what the UPS plugin does today; its files are the reference.

## Principles

- **Look built-in.** A CuteMonitor widget sits beside Noctalia's Clock, Weather and System
  Monitor and matches them: their type sizes, their graph style, the host's Background block,
  move, resize and inspector. In the bar, the normal state uses the bar's own colors.
- **Settings over fixed choices.** If something can reasonably be configured, it's a setting
  with a sensible default.
- **One poller, thin displays.** One background service reads the hardware; the desktop
  widget, bar item and panel only render what it publishes.
- **Quiet until it matters.** Normal states use the base colors; color changes mean something
  (Warning, Alert); stale data dims instead of disappearing.
- **Verified offline before anything goes live.**

## Architecture

| Piece | Role |
| --- | --- |
| `[[service]]` | Polls the data source, tracks history and events, runs actions, publishes everything through `noctalia.state`. The only place that runs commands. |
| `[[desktop_widget]]` | One of several layouts, chosen by `display`; renders shared state. |
| `[[widget]]` (bar) | Icon and/or short label, tooltip summary; left click opens the panel. |
| `[[panel]]` | Details: big numbers, live graph, full readout, events, actions; each section switchable. |
| `source_*.luau` | One pure parser per data source → one normalized snapshot shape. |
| `tracker.luau` | Pure history, graph series and event detection. |
| `shared.luau` | State keys, stat catalog, formatting, levels and colors (pure); then "Words" (translations, dates). |

**Pure modules** make no `noctalia.*` calls and have no `require`, so the standalone `luau`
runner can test them with captured fixtures (Noctalia needs `require("./x.luau")`, the runner
resolves only extensionless paths). Entry scripts stay thin.

**Shared state** (`noctalia.state`, per plugin): the latest snapshot, then a link record
`{ state = starting|ok|lost|unavailable, kind, message, source, lastOkAt }`. The service always
sets the snapshot first and the link second; displays store the snapshot and re-render when
the link arrives. Graph series get one key per time span; the event log, last self-test and
policy have their own keys. Panel actions go through a `request { id, action }` →
`reply { id, ok, message }` pair; the panel stops waiting after 15 s.

**Saved data** goes to `noctalia.pluginDataDir()` as JSON, written to a temporary file and
renamed. Graph history stays in memory (one hour).

## Layout and type

Desktop content is **252 px wide**: with Noctalia's default 10 px background padding the tile
is 272 px, the width of a Clock (112) + Weather (160) row.

| Token | Value | Use |
| --- | --- | --- |
| Hero | 31.5 bold | Main number (Weather's temperature size) |
| Secondary | 20 | Second number |
| Body | 14 | Titles, units after a number |
| Caption | 13 | Labels, details, legends, readout rows |
| Small | 12 | Panel captions and replies |
| Dim | 0.45 opacity | Stale (lost) values |
| Track | `on_surface/0.12` | Gauge tracks, separators |

- **Icons:** power/status icon 42 beside a hero number; 22 in side-by-side cells; 16–18 in
  legends, gauges and status lines; 34 (`outline`) in message tiles.
- **Graph:** System Monitor's style — line 0.75, fill 0.2, 120 points; percentages scale
  0–100, watts 0–rating, everything else between the lowest and highest value in view. Desktop
  graph 112 high; panel graph 84.
- **Gauges:** bars 6 high, radius 3; pills 8 × 40, radius 4; value column 76 wide (fits
  "23 h 59 min").
- **Two numbers of different sizes** (Status → Main + Secondary): both on one baseline, a
  caption under each on the next, details as a full-width footer. Labels beside numbers
  ("Load 18%") don't fit every stat pair; captions underneath always do.
- **Baselines:** rows align label boxes, not baselines, and a label's baseline sits higher
  in a bigger box, so a smaller label bottom-aligned with a bigger one lands low. Lift it with
  a spacer under it — measured for Inter: 31.5 vs 14 → 4 px, 31.5 vs 20 → 3, 26 vs 14 → 3,
  20 vs 14 → 1 (`lift()` in the UPS `desktop.luau`).
- **Text that must fit:** measure the longest realistic value in the shell font (Inter) —
  `pango-view` does it. A label with a fixed width wraps unless it has `maxLines`; a label in
  a row with neither a width nor `flexGrow` keeps its natural width and can spill past the
  tile. Text that can grow (states, lost messages, reasons) gets `flexGrow` and `maxLines`.
- **Panel:** 380 × 600 (content 352 × 572); big numbers 26 bold; cards `surface_variant/0.45`,
  radius 12, padding 12, gap 8; nothing inside the scroll area gets a fixed width (rows and columns stretch, and
  a scrollbar takes 14 px when content overflows).
- **Text:** values modern (`180 W · 18%`), status words in sentence case, runtimes adaptive
  (`40 s`, `37 min`, `1 h 15 min`), parts joined with ` · `.

## Color

| Setting | Default | Meaning |
| --- | --- | --- |
| Color | `primary` | First stat; the power icon in a normal state |
| Color 2 | `secondary` | Second stat; normal state words |
| Color 3 | `on_surface_variant` | Third stat (Gauges) |
| Warning Color | `tertiary` | Running on battery (or bypass, calibrating) |
| Alert Color | `error` | Low battery, overload, fault, load above the High Load threshold |

A color setting is hidden for layouts that don't use it (`visible_when`). In the bar, normal
states set no color at all so text and icons follow the bar; only Warning/Alert tint.
Anything drawn from boxes (the drawn battery) needs its own color setting, because only
text and glyphs inherit the bar's foreground.

## States

| Level | When | Shown as |
| --- | --- | --- |
| none | no data source | Message tile: icon, "Looking for a UPS…" or "No UPS connected", and the reason |
| lost | link lost, or the source says so | Last values dimmed to 0.45 with "Lost communication · last data N ago" |
| alert | critical conditions | Alert color on the state and affected stats |
| warning | degraded but working | Warning color |
| normal | everything fine | Base colors |

Lost is declared at once when the source reports it, otherwise after three failed readings.

## Timing

- Service: polls at the user's interval (1/2/5/10/30/60 s).
- Desktop and bar: re-render when the service publishes; their own tick is 60 s (relative
  dates), 1 s while lost (the age counts up). Set the interval before any early return — the
  bar's default tick is 250 ms.
- Panel: second ticks only while open.

## Settings names

Reuse these keys and meanings so every tool's inspector reads the same.

| Scope | Keys |
| --- | --- |
| Plugin-wide | `data_source`, `poll_interval`, `high_<stat>` thresholds, `date_style` (`short` / native / `relative`), `log_<category>` switches |
| Desktop widget | `display`; Status: `big1`, `big2` (+ `none`), `number_style`, `detail1`–`detail3`; Graph: `line1`, `line2`, `time_span`, `show_label`; Gauges: `gauge_layout`, `bar1`–`bar3`, `status_line`; Readout: `row_<group>`, `extra_<group>`; colors: `color`, `color2`, `color3`, `warning_color`, `alert_color` |
| Bar | `display_mode`, `show_label`, `label_content`, `only_on_<state>`, `warning_color`, `alert_color` |
| Panel | `panel_<section>` switches |

Translations (`translations/en.json`): `settings.<key>.label|description|options.<value>`,
`stats.<stat>` (dropdown names), `caption.<stat>` (under big numbers), `status.<state>`,
`event.<key>`, `rows.<field>` (the source's own wording), `reason.<why>`, `time.*` plurals as
`.one`/`.other`.

## Platform facts worth knowing

Verified in Noctalia 5.2.1's source while building the UPS plugin.

- Noctalia calls `update()` right after a script loads; don't call it yourself.
- Watchers fire after the current callback, not on registration; `state.set` doesn't skip
  unchanged values. Values pass through JSON: a table with an array part loses its other keys.
- `noctalia.tr` logs a warning for every missing key, so don't probe for keys that may not
  exist (the UPS plugin skips lookups for unrecognized "other" values).
- Luau's `os.time(table)` reads the table as **UTC**; convert local wall-clock times yourself.
- `runAsync` with an argv table runs without a shell; ≤ 8 at once, 1 MiB output, timeout
  50–60000 ms. Each callback gets 25 ms of CPU; repeated overruns disable the script.
- A `[widget.actions]` left binding takes left clicks away from the script's `onClick`.
- Desktop widgets can't hide themselves (bar widgets can); there's no overlay or text shadow;
  selects render as dropdowns.
- `plugin.toml` is re-read only when the plugin configuration changes or Noctalia restarts.
- The desktop editor's inspector doesn't scroll and has no height cap: a layout's settings
  plus Noctalia's Background block must fit the screen. At ~38 px a row, keep each layout to
  about 15 settings (Readout groups its rows for this reason). Descriptions aren't shown there.
- A setting's `visible_when` takes one condition and doesn't cascade (a setting stays visible
  when the setting it depends on is hidden), so it can't build "show more" sub-sections.
- Saved widget settings with keys the manifest no longer declares are logged as "unknown
  setting"; renaming a setting leaves those behind in the user's config.

## A new tool in the suite

- Folder `cutemonitor-<thing>/` beside `cutemonitor-ups/`, id `cutecaption/cutemonitor-<thing>`
  (the folder name must equal the id's second half). The existing `cutecaption` source finds it.
- Shared code is **copied** into each plugin, never required across folders: the community
  repo installs each plugin folder on its own. Candidates: formatting, levels and colors,
  graph scaling, history and series, the tile builders.
- Pick a state-key prefix of its own, a data-source module per source, fixtures captured from
  real output, unit tests, and drivers for `tools/harness/`.
- Same process: decisions made with the user, offline verification (tests, `luau-analyze` from
  the repo root, `noctalia plugins lint`, the harness), go-live last.
