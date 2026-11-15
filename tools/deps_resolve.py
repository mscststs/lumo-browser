#!/usr/bin/env python3
"""Resolve a path to its pinned git dependency in Chromium's DEPS.

Usage: deps_resolve.py <src-root> <path-relative-to-src>

Prints "<url> <revision>" or exits 1. Handles DEPS' Var()/Str() wrappers and
the dict form (`{'url': ..., 'condition': ...}`). Only plain git deps are
resolved; CIPD/GCS deps are handled by scripts/chromium/cipd-deps.sh.
"""
import os
import sys


class _Var(str):
    pass


class _Str(str):
    pass


def load_deps(src_root):
    path = os.path.join(src_root, 'DEPS')
    env = {'Var': _Var, 'Str': _Str, 'vars': {}}
    deps = {}
    # Two passes: vars first (DEPS uses `vars['x']` and Var('x')).
    ns = {}
    exec(compile(open(path).read(), path, 'exec'), ns)
    for key in ('deps', 'deps_os'):
        block = ns.get(key) or {}
        if isinstance(block, dict):
            for k, v in block.items():
                deps.setdefault(k, v)
        if key == 'deps_os':
            for osname, sub in (block or {}).items():
                if isinstance(sub, dict):
                    for k, v in sub.items():
                        deps.setdefault(k, v)
    return ns.get('vars', {}), deps


def main():
    if len(sys.argv) != 3:
        print(__doc__, file=sys.stderr)
        return 2
    src_root, rel = sys.argv[1], sys.argv[2].lstrip('/')
    if not rel.startswith('src/'):
        rel = 'src/' + rel
    _, deps = load_deps(src_root)
    entry = deps.get(rel)
    if entry is None:
        print(f'no DEPS entry for {rel}', file=sys.stderr)
        return 1
    if isinstance(entry, dict):
        url = entry.get('url')
        if not url:
            print(f'{rel} is not a git dep (dep_type={entry.get("dep_type")})', file=sys.stderr)
            return 1
    else:
        url = entry
    if '@' not in url:
        print(f'{rel}: unpinned url {url}', file=sys.stderr)
        return 1
    base, rev = url.rsplit('@', 1)
    print(base, rev)
    return 0


if __name__ == '__main__':
    sys.exit(main())
