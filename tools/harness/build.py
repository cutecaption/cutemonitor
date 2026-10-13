"""Assembles one runnable Luau file for one plugin entry: the extracted rules,
the plugin's strings and manifest defaults, the fake Noctalia runtime, the ui
prelude, every plugin module (inlined in place of require), the real entry
script wrapped in LOAD(), optional recorded scenarios, and a driver.

    python3 -I build.py --plugin DIR --entry service|desktop|bar|panel \
        --rules DIR --driver FILE [--scenarios FILE] --out FILE

Nothing in the plugin is changed; the output is a throwaway file.
"""
import argparse, json, pathlib, re, tomllib

p = argparse.ArgumentParser()
p.add_argument('--plugin', required=True, type=pathlib.Path)
p.add_argument('--entry', required=True, choices=['service', 'desktop', 'bar', 'panel'])
p.add_argument('--rules', required=True, type=pathlib.Path)
p.add_argument('--driver', required=True, type=pathlib.Path)
p.add_argument('--scenarios', type=pathlib.Path)
p.add_argument('--out', required=True, type=pathlib.Path)
args = p.parse_args()
HERE = pathlib.Path(__file__).parent


def q(s):
    return json.dumps(s, ensure_ascii=False)  # Luau rejects \uXXXX escapes


def lua(v):
    if isinstance(v, bool):
        return 'true' if v else 'false'
    if isinstance(v, (int, float)):
        return repr(v)
    if isinstance(v, str):
        return q(v)
    raise TypeError(v)


manifest = tomllib.loads((args.plugin / 'plugin.toml').read_text())
table = {'service': 'service', 'desktop': 'desktop_widget', 'bar': 'widget', 'panel': 'panel'}[args.entry]
entry = manifest[table][0]
settings = manifest.get('setting', []) + entry.get('setting', [])

strings = {}


def flatten(node, prefix):
    if isinstance(node, dict):
        for k, v in node.items():
            flatten(v, f'{prefix}.{k}' if prefix else k)
    else:
        strings[prefix] = node


flatten(json.loads((args.plugin / 'translations/en.json').read_text()), '')

parts = [(args.rules / 'rules.luau').read_text()]
parts.append('TR = {' + ','.join(f'[{q(k)}]={q(v)}' for k, v in strings.items()) + '}')
parts.append('DEFAULTS = {' + ','.join(f'[{q(s["key"])}]={lua(s["default"])}' for s in settings) + '}')
parts.append('DECLARED = {' + ','.join(f'[{q(s["key"])}]=true' for s in settings) + '}')
parts.append('OPTIONS = {' + ','.join(
    f'[{q(s["key"])}]={{' + ','.join(q(o['value']) for o in s['options']) + '}'
    for s in settings if 'options' in s) + '}')
parts.append((HERE / 'fake.luau').read_text())
parts.append((args.rules / 'prelude.luau').read_text())

modules = {f.stem: f.read_text() for f in sorted(args.plugin.glob('*.luau'))}
modules.update({f.stem: f.read_text() for f in sorted((args.plugin / 'tests').glob('*fixtures*.luau'))})
parts.append('local MODULES = {}')
for name, text in modules.items():
    parts.append(f'MODULES[{q(name)}] = function()\n{text}\nend')
parts.append('local function __require(name) return MODULES[name]() end')

body, n = re.subn(r'require\("\./(\w+)\.luau"\)', r'__require("\1")', (args.plugin / entry['entry']).read_text())
parts.append(f'-- entry: {entry["entry"]} ({n} requires inlined)')
parts.append(f'local function LOAD()\n{body}\nend')
if args.scenarios:
    parts.append(args.scenarios.read_text())
parts.append(args.driver.read_text())
args.out.parent.mkdir(parents=True, exist_ok=True)
args.out.write_text('\n'.join(parts))
print(f'built {args.out.name}: {entry["entry"]}, {n} requires inlined, {len(settings)} declared settings')
