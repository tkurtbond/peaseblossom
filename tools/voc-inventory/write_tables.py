"""write_tables.py VOC_SOURCE MODULES_JSON CHECK_DIR: the tables of
doc/research/voc-module-inventory.md, one per source directory, in Markdown on standard
output. CHECK_DIR holds the inventory script's poc checks (status.txt, a line
"<module> <0|1|poc>" each, and <module>.out)."""

import json
import os
import sys

import voc_sources
from module_purposes import PURPOSES

voc_source, modules_json, check_dir = sys.argv[1:4]
all_modules = json.load(open(modules_json))
modules = voc_sources.by_name(all_modules)
src = os.path.join(voc_source, 'src')

FAMILY = {'runtime': 'voc runtime', 'v4': 'Ofront / Oberon V4', 'misc': 'various', 'ooc': 'OOC (oo2c 1.x)',
          'ooc2': 'OOC (oo2c 2.x)', 'oocX11': 'OOC X11 binding', 'pow': 'POW!', 's3': 'ETH Oberon System 3',
          'ulm': 'Ulm Oberon Library', 'tools': 'voc tools'}
OAKWOOD = {'In', 'Out', 'Files', 'Math', 'MathL', 'Strings', 'oocXYplane'}

# What a module's first error means, where the message alone does not say
# (read from the modules, 2026-09-27); any other failure shows its message
EXPLANATIONS = {
    'Heap': 'inline C', 'oocwrapperlibc': 'inline C', 'oocX11': 'inline C', 'oocXutil': 'inline C',
    'oocXYplane': 'inline C', 'ulmSysStat': 'inline C',
    'Reals': 'poc Platform lacks LittleEndian',
    'oocSysClock': 'poc Platform lacks GetTimeOfDay', 'oocFilesHost': 'poc Platform lacks FileHandle',
    'MultiArrays': 'poc Platform lacks Time', 'crt': 'poc Platform lacks Delay',
    'ethZlibDeflate': 'LONG(CHAR) (voc; poc: use ORD)',
    'ulmTypes': 'POINTER [1] TO (voc untraced pointer; poc: use SYSTEM.ADDRESS)',
    'ulmSYSTEM': 'function with an empty body (voc accepts; the report does not)'}

# What poc's rtl/llvm has of voc's runtime and v4 modules of the same name
# (compared by hand, 2026-09-27; Platform, VT100, Files, Modules, Reals, Texts and Oberon 2026-10-02; Args
# 2026-10-02); the rest, "no"
IN_POC = {'In': 'yes, whole interface', 'Out': 'yes, whole interface', 'Strings': 'yes, whole interface',
          'Math': 'yes, whole interface (own code over libm)', 'MathL': 'yes, whole interface (own code over libm)',
          'Files': 'yes, whole interface (own code over C stdio)',
          'Modules': 'yes, whole interface (own code; modules listed by the code generator)',
          'Platform': 'yes, whole interface (its C part in Platform.c)', 'Console': 'yes (v4 interface)',
          'VT100': 'yes, whole interface (own code)',
          'Reals': 'yes, whole interface (own code; TenL correctly rounded)',
          'Texts': 'yes, whole interface (own code; no display)',
          'Oberon': 'yes, whole interface (own code; no display)',
          'Args': 'yes, whole interface (over Modules and Platform)',
          'Heap': 'no: poc has its own collector (GarbageCollectedHeap)'}


def in_poc(m):
    if not m['hostVariant']:
        return 'no (Unix only)'
    return IN_POC.get(m['module'], 'no')


def read_status():
    status = {}
    for line in open(os.path.join(check_dir, 'status.txt')):
        name, value = line.split()
        status[name] = value
    return status


status = read_status()


def first_error(name):
    for line in open(os.path.join(check_dir, name + '.out')):
        if ' error: ' in line:
            return line.split(' error: ', 1)[1].strip()
    return 'no error message'


# A failing module whose imports all pass fails on its own; the others, through them
failing = {name for name, value in status.items() if value == '1'}
roots = {name: EXPLANATIONS.get(name) or first_error(name) for name in failing
         if name in EXPLANATIONS or not set(modules[name]['imports']) & failing}


def check(m):
    name = m['module']
    if m['file'].startswith('tools/') or not m['hostVariant']:
        return 'not checked'
    value = status.get(name)
    if value == 'poc':
        return 'poc has its own'
    if value == '0':
        return 'accepted'
    if name in roots:
        return 'no: ' + roots[name]
    return 'no, through ' + ' '.join(sorted(voc_sources.closure(modules, name) & set(roots)))


def raw(m):
    return open(os.path.join(src, m['file']), encoding='latin-1').read()


def licence(m):
    text = raw(m)[:6000]
    parts = m['file'].split('/')
    if 'Lesser General Public' in text:
        return 'LGPL 2.1+ (header)'
    if 'Library General Public' in text:
        return 'LGPL 2+ (header)'
    if 'ETH Oberon System Source License' in text:
        return 'ETH Oberon licence (header)'
    if 'POW!' in text:
        return 'copyright POW! team, no licence given'
    if parts[0] == 'tools':
        return 'none in file; README: tools GPLv3'
    if parts[0] == 'runtime':
        return 'none in file; README: runtime GPLv3 + runtime exception, Ofront parts FreeBSD'
    if parts[1] in ('ooc', 'ooc2'):
        return 'none in file; OOC library (LGPL) or voc wrapper'
    if parts[1] == 'ulm':
        return 'none in file; Ulm library (LGPL 2+) adapted by voc'
    if parts[1] == 'v4':
        return 'none in file; Ofront (FreeBSD, README)'
    return 'none in file'


# voc's runtime modules poc's own runtime replaces: their inline C does not count against an importer
REPLACED = {'Platform', 'Heap', 'Modules', 'Out', 'Files'}
PROGRAM_ONLY = {'OPM', 'OPS', 'OPT', 'OPV', 'Configuration'}  # the compiler's, imported by showdef


def depends_on(m):
    reach = voc_sources.closure(modules, m['module'])
    out = []
    if m['inlineC']:
        out.append('inline C (%d)' % m['inlineC'])
    elif any(modules[i]['inlineC'] for i in reach if i in modules and i not in REPLACED):
        out.append('inline C in an import')
    if m['x11']:
        out.append('X11')
    if 'Platform' in reach or m['module'] == 'Platform':
        out.append('Platform')
    if reach & {'Texts', 'Oberon'}:
        out.append('Texts')
    if 'SYSTEM' in m['imports']:
        out.append('SYSTEM')
    missing = [i for i in m['imports'] if i != 'SYSTEM' and i not in modules and i not in PROGRAM_ONLY]
    if missing:
        out.append('missing: ' + ' '.join(missing))
    return ', '.join(out) or '-'


def voc_builds(m):
    if m['file'].startswith('tools/'):
        return 'showdef' if m['module'] == 'BrowserCmd' else 'no'
    if m['file'] == 'runtime/Platformwindows.Mod':
        return 'Windows only'
    if m['file'] == 'library/ooc2/oocwrapperlibc.Mod':
        return 'no (ooc\'s is)'
    if m['file'] in ('library/ooc/oocCLP64.Mod', 'library/ooc/oocCILP32.Mod', 'library/ooc/oocCLLP64.Mod'):
        return 'O2 (as oocC, on %s hosts)' % ('LP64' if m['hostVariant'] else 'ILP32/LLP64')
    if not m['built']:
        return 'no'
    if m['file'].startswith('library/oocX11'):
        return 'no (target not in the library)'
    as_platform = ' (as Platform)' if m['file'] == 'runtime/Platformunix.Mod' else ''
    return ('O2, OC' if m['symOC'] else 'O2') + as_platform


rows = {}
for m in all_modules:
    parts = m['file'].split('/')
    key = parts[1] if parts[0] == 'library' else parts[0]
    reach = voc_sources.closure(modules, m['module'])
    rows.setdefault(key, []).append('| %s | `%s` | %s | %s | %d | %d | %s | %s | %s | %s | %s | %s |' % (
        m['module'], m['file'], PURPOSES[m['module']], ' '.join(m['imports']) or '-', m['lines'], len(reach),
        depends_on(m), FAMILY[key] + (', Oakwood' if m['module'] in OAKWOOD else ''), voc_builds(m), check(m),
        in_poc(m) if key in ('runtime', 'v4') else 'no', licence(m)))

HEADER = ('| Module | File | Purpose | Imports | Lines | Pulls in | Depends on | Family | voc builds | poc -check'
          ' | In poc | Licence |\n|---|---|---|---|---|---|---|---|---|---|---|---|')
for key in ['runtime', 'v4', 'ooc', 'ooc2', 'oocX11', 's3', 'ulm', 'misc', 'pow', 'tools']:
    print('\n### `%s` (%d files)\n' % (key if key in ('runtime', 'tools') else 'library/' + key, len(rows[key])))
    print(HEADER)
    print('\n'.join(rows[key]))
