"""Extracts the UI rules the harness validates against from a Noctalia source
tree: allowed props per ui.* type, enum values, color roles, glyph names, and
the ui.* prelude itself.

    python3 -I gen_rules.py <noctalia-source-dir> <output-dir>

The source tree is the release tarball (github.com/noctalia-dev/noctalia, tag
vX.Y.Z). The output dir gets rules.luau and prelude.luau; name it after the
version (noctalia-5.2.1/) and pass it to build.py.
"""
import json, pathlib, re, sys

SRC = pathlib.Path(sys.argv[1])
OUT = pathlib.Path(sys.argv[2])
VERSION = (SRC / 'VERSION').read_text().strip() if (SRC / 'VERSION').exists() else SRC.name

rec = (SRC / 'src/ui/ui_tree_reconciler.cpp').read_text()
sets = {}
for m in re.finditer(r'static const std::unordered_set<std::string> (k\w+)\s*=\s*\{(.*?)\};', rec, re.S):
    sets[m.group(1)] = re.findall(r'"([^"]+)"', m.group(2))
tmap = {'column': 'kFlex', 'row': 'kFlex', 'box': 'kBox', 'label': 'kLabel', 'glyph': 'kGlyph', 'image': 'kImage',
        'separator': 'kSeparator', 'progress': 'kProgress', 'button': 'kButton', 'graph': 'kGraph', 'input': 'kInput',
        'markdown': 'kMarkdown', 'select': 'kSelect', 'slider': 'kSlider', 'toggle': 'kToggle', 'scroll': 'kScroll',
        'drag_source': 'kDragSource', 'drop_zone': 'kDropZone', 'spacer': 'kCommon'}
# Confirm the type -> set mapping against knownProps()'s if-chain; spacer is the fallback.
for t, k in tmap.items():
    if t == 'spacer':
        continue
    assert re.search(r'type == "%s"(?: \|\| type == "\w+")?\) \{\s*return %s;' % (t, k), rec), \
        f'{t} -> {k} not found; update tmap'


def enum(marker):
    i = rec.index(marker)
    body = rec[i:i + 3000]
    return re.findall(r'\*token == "([^"]+)"', body[:body.find('\n    }\n')])


enums = {
    'align': enum('const std::string* token = strProp(node, "align")'),
    'justify': enum('const std::string* token = strProp(node, "justify")'),
    'textAlign': enum('const std::string* token = strProp(node, "textAlign")'),
    'variant': enum('const std::string* token = strProp(node, "variant")'),
    'controlSize': enum('const std::string* token = strProp(node, "controlSize")'),
    'fontWeight': enum('std::optional<FontWeight> parseFontWeight'),
}
i = rec.index('strProp(desired, "orientation")')
enums['orientation'] = re.findall(r'== "([^"]+)"', rec[i:i + 400])

roles = re.findall(r'\{ColorRole::\w+, "([^"]+)"\}', (SRC / 'src/ui/palette.h').read_text())
glyphs = list(json.loads((SRC / 'assets/fonts/tabler.json').read_text()).keys())
gr = (SRC / 'src/render/text/glyph_registry.cpp').read_text()
start = gr.index('kAliases')
aliases = re.findall(r'\{"([^"]+)", "[^"]+"\}', gr[start:gr.index('};', start)])
prelude = (SRC / 'src/scripting/ui_prelude.h').read_text()
prelude = prelude[prelude.index('R"luau(') + 7:prelude.index(')luau"')]


def q(s):
    return json.dumps(s, ensure_ascii=False)  # Luau rejects \uXXXX escapes


def lt(xs):
    return '{' + ','.join(f'[{q(x)}]=true' for x in xs) + '}'


out = [f'-- generated from Noctalia {VERSION} source by gen_rules.py', 'local RULES = {}']
out.append('RULES.props = {' + ','.join(f'[{q(t)}]={lt(sets[k])}' for t, k in tmap.items()) + '}')
out.append('RULES.enums = {' + ','.join(f'{k}={lt(v)}' for k, v in enums.items()) + '}')
out.append('RULES.roles = ' + lt(roles))
out.append('RULES.glyphs = ' + lt(glyphs + aliases))
OUT.mkdir(parents=True, exist_ok=True)
(OUT / 'rules.luau').write_text('\n'.join(out) + '\n')
(OUT / 'prelude.luau').write_text(prelude)
print(f'Noctalia {VERSION}: {len(roles)} roles, {len(glyphs)} glyphs + {len(aliases)} aliases')
for k, v in enums.items():
    print(f'  {k}: {", ".join(v)}')
