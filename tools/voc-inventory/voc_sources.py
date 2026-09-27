"""Reading voc's module sources (Phase 12 step 3, 2026-09-27): each .Mod file's
module name, imports, size, voc inline C and header comments, and whether voc's
makefile builds it and its install has its symbol file. Shared by
extract_modules.py and write_tables.py."""

import os
import re

# Files that declare a module another file declares too: voc builds one of
# each per host (Platform$(PLATFORM), oocC$(DATAMODEL)), and ooc2's
# oocwrapperlibc is not built at all. The inventory's closures and checks use
# the variant a Unix LP64 host builds.
OTHER_VARIANTS = ('runtime/Platformwindows.Mod', 'library/ooc/oocCILP32.Mod',
                  'library/ooc/oocCLLP64.Mod', 'library/ooc2/oocwrapperlibc.Mod')

# The files a make variable names, as the Unix LP64 host's make expands it
HOST_VARIANTS = {'runtime/Platformunix': 'runtime/Platform$(PLATFORM)',
                 'library/ooc/oocCLP64': 'library/ooc/oocC$(DATAMODEL)'}


def strip_comments(text):
    """text without its (* ... *) comments, which nest"""
    result = []
    i = 0
    depth = 0
    while i < len(text):
        if text.startswith('(*', i):
            depth += 1
            i += 2
        elif depth and text.startswith('*)', i):
            depth -= 1
            i += 2
        else:
            if not depth:
                result.append(text[i])
            i += 1
    return ''.join(result)


def read_module(path, relative):
    raw = open(path, encoding='latin-1').read()
    code = strip_comments(raw)
    match = re.search(r'\bMODULE\s+(\w+)', code)
    name = match.group(1) if match else '?'
    imports = []
    match = re.search(r'\bIMPORT\b(.*?);', code, re.S)
    if match:
        for part in match.group(1).split(','):
            part = part.strip()
            if ':=' in part:
                part = part.split(':=')[1].strip()
            if part:
                imports.append(part)
    comments = re.findall(r'\(\*(.*?)\*\)', raw[:4000], re.S)
    head = ' '.join(' '.join(c.split()) for c in comments[:3])[:400]
    return {
        'file': relative,
        'module': name,
        'imports': imports,
        'head': head,
        'lines': raw.count('\n'),
        # voc's PROCEDURE - (a body of C text pasted into the generated C)
        'inlineC': len(re.findall(r'PROCEDURE\s*-', code)),
        'x11': bool(re.search(r'X11|Xlib|XOpenDisplay', raw)),
    }


def read_all(voc_source, voc_install):
    """Every module file under voc's src/runtime, src/library and src/tools"""
    src = os.path.join(voc_source, 'src')
    makefile = open(os.path.join(src, 'tools/make/oberon.mk')).read()
    built = set(m.group(1) for m in re.finditer(r'src/((?:library|runtime)/[A-Za-z0-9/$()]+)\.Mod', makefile))
    symbols = {}
    for model in ('2', 'C'):
        directory = os.path.join(voc_install, model, 'sym')
        symbols[model] = {f[:-4] for f in os.listdir(directory) if f.endswith('.sym')}
    modules = []
    for top in ('runtime', 'library', 'tools'):
        for directory, _, files in sorted(os.walk(os.path.join(src, top))):
            for f in sorted(files):
                if f.endswith('.Mod'):
                    path = os.path.join(directory, f)
                    relative = os.path.relpath(path, src)
                    m = read_module(path, relative)
                    stem = relative[:-4]
                    m['built'] = stem in built or HOST_VARIANTS.get(stem) in built
                    m['symO2'] = m['module'] in symbols['2']
                    m['symOC'] = m['module'] in symbols['C']
                    m['hostVariant'] = relative not in OTHER_VARIANTS
                    modules.append(m)
    return modules


def by_name(modules):
    """The modules by name, the host's variant of each"""
    return {m['module']: m for m in modules if m['hostVariant']}


def closure(modules, name, seen=None):
    """The names of every module name imports, directly or not (SYSTEM left out)"""
    seen = set() if seen is None else seen
    for i in modules.get(name, {}).get('imports', []):
        if i != 'SYSTEM' and i not in seen:
            seen.add(i)
            closure(modules, i, seen)
    return seen
