"""Turns the SCENARIO lines a service run prints (name + the shared state as
JSON) into a Luau file the desktop, bar and panel runs load as SCENARIOS.

    python3 -I scenarios.py service.out scenarios.luau
"""
import pathlib, sys

lines = [l for l in pathlib.Path(sys.argv[1]).read_text().splitlines() if l.startswith('SCENARIO ')]
out = ['SCENARIOS, SCENARIO_ORDER = {}, {}']
for line in lines:
    _, name, state = line.split(' ', 2)
    assert ']==]' not in state, name
    out.append(f'SCENARIOS["{name}"] = H.decode([==[{state}]==]) or {{}}')
    out.append(f'table.insert(SCENARIO_ORDER, "{name}")')
pathlib.Path(sys.argv[2]).write_text('\n'.join(out) + '\n')
print(f'{len(lines)} scenarios: {", ".join(l.split(" ", 2)[1] for l in lines)}')
