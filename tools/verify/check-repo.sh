#!/usr/bin/env bash
# 仓库卫生检查：脚本语法 + Python 编译 + 结构/链接/补丁/skills 检查。
# 无需 Chromium 源码、无需设备、无需网络（CI 与本机同一套）。
#
#   bash tools/verify/check-repo.sh
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT"
fail=0

echo "== shell 语法（bash -n）=="
while IFS= read -r f; do
  bash -n "$f" || { echo "FAIL $f"; fail=1; }
done < <(git ls-files '*.sh')
echo "ok   $(git ls-files '*.sh' | wc -l) 个脚本语法正确"

echo "== python 编译（py_compile）=="
pycache="$(mktemp -d)"
trap 'rm -rf "$pycache"' EXIT
while IFS= read -r f; do
  PYTHONPYCACHEPREFIX="$pycache" python3 -m py_compile "$f" || { echo "FAIL $f"; fail=1; }
done < <(git ls-files '*.py')
echo "ok   $(git ls-files '*.py' | wc -l) 个 Python 文件可编译"

echo "== 结构检查（补丁 / 链接 / 索引 / skills / 卫生）=="
python3 tools/verify/check_repo.py || fail=1

if (( fail )); then
  echo "静态检查失败" >&2
  exit 1
fi
echo "静态检查全部通过"
