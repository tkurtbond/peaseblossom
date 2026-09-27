"""import_order.py MODULES_JSON: the library and runtime modules (the host's
variant of each; voc's tools left out), one name a line, each after the modules it imports - the
order in which poc can check them, each against its imports' .sym files."""

import json
import sys

import voc_sources

modules = {name: m for name, m in voc_sources.by_name(json.load(open(sys.argv[1]))).items()
           if not m['file'].startswith('tools/')}
ordered = []
visited = set()


def visit(name):
    if name in visited or name not in modules:
        return
    visited.add(name)
    for i in modules[name]['imports']:
        visit(i)
    ordered.append(name)


for name in sorted(modules):
    visit(name)
print('\n'.join(ordered))
