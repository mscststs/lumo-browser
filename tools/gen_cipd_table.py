#!/usr/bin/env python3
"""Generate the CIPD dependency table for the current checkout.

The official source tarball omits `dep_type: cipd` entries, and `gclient sync`
is unusable here, so we install them ourselves. This script derives both the
install root (the DEPS key) and the exact package/version from DEPS, which keeps
the table correct across Chromium bumps.

Output: lines "root|package|version" (see scripts/chromium/cipd-deps.sh).

Usage: tools/gen_cipd_table.py <chromium-src> [--include-all]
"""
import os
import re
import sys

PLATFORM = 'linux-amd64'
OS = 'linux'


def load(src):
    path = os.path.join(src, 'DEPS')
    ns = {'Var': lambda name: f'@@{name}@@', 'Str': lambda s: s}
    exec(compile(open(path).read(), path, 'exec'), ns)
    return ns


def resolve(value, variables):
    """Resolve @@var@@ placeholders (two passes covers nested vars)."""
    for _ in range(3):
        def repl(m):
            name = m.group(1)
            return str(variables.get(name, m.group(0)))
        new = re.sub(r'@@([A-Za-z0-9_\-]+)@@', repl, value)
        if new == value:
            break
        value = new
    return value


def main():
    if len(sys.argv) < 2:
        print(__doc__, file=sys.stderr)
        return 2
    src = sys.argv[1]
    include_all = '--include-all' in sys.argv
    ns = load(src)
    variables = ns.get('vars', {})
    rows = []
    for section in ('deps', 'deps_os'):
        block = ns.get(section) or {}
        entries = []
        if isinstance(block, dict):
            entries = list(block.items())
        for key, entry in entries:
            if not isinstance(entry, dict) or entry.get('dep_type') != 'cipd':
                continue
            cond = entry.get('condition', '')
            if 'checkout_android' not in cond and not include_all:
                continue
            root = key[4:] if key.startswith('src/') else key
            for pkg in entry.get('packages', []):
                name = pkg.get('package', '')
                name = name.replace('${{platform}}', PLATFORM).replace('${{os}}', OS)
                ver = resolve(str(pkg.get('version', '')), variables)
                rows.append((root, name, ver))
    seen = set()
    for root, name, ver in rows:
        line = f'{root}|{name}|{ver}'
        if line in seen:
            continue
        seen.add(line)
        print(line)
    return 0


if __name__ == '__main__':
    sys.exit(main())
