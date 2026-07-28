#!/usr/bin/env bash
# organize-repo.sh —— 扫描 haisa-des-repo 所有 Release 资产，按首字母重组到 Pages 静态根
#
# 部署位置: haisa-des-repo 仓库 scripts/organize-repo.sh
# 触发方式: workflow_dispatch（手动）
#
# 设计:
#   - 输入: GitHub Releases 上所有 tag 的所有资产（扁平，混在一起）
#   - 输出: dist/apt-repo/ + dist/pip-repo/（按首字母布局，部署到 gh-pages 分支）
#   - 不破坏现有 release（保留可下载，老 App 端继续兼容）
#   - 幂等: 每次运行重写 dist/，最终状态只反映当前所有 release 的资产集合
#
# 资产分类规则:
#   - *.deb → apt-repo/pool/main/<首字母>/<包名>/<deb>
#   - *.whl → pip-repo/simple/<首字母>/<规范化包名>/<whl>（同 make-pip-repo.sh 规则）
#   - bootstrap-*.zip / packages.json / wheels-index.json / bootstrap-version.json
#     → 保留在 Releases（不动），不进 Pages
#   - 其他: 跳过并告警（便于排查遗漏资产）
#
# 产物:
#   dist/apt-repo/         Debian 仓库（含 Releases 中所有 .deb）
#   dist/pip-repo/         PEP 503 simple 索引（含 Releases 中所有 .whl）
#   dist/organize-report.json   整理报告（统计 + 异常）
#
# 用法（CI 中）:
#   REPO=XION-HN/haisa-des-repo GH_TOKEN=$TOKEN ./scripts/organize-repo.sh
set -euo pipefail

REPO="${REPO:-XION-HN/haisa-des-repo}"
# GH_TOKEN 必须由调用方注入（contents:read + actions:read 权限）
: "${GH_TOKEN:?GH_TOKEN 未设置（需 haisa-des-repo 的 PAT）}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT/dist"

log()  { printf '\033[1;34m[organize]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

log "扫描 $REPO 所有 Release 资产..."

# 1. 列出所有 release（含草稿/ prerelease）
#    gh release list --json tagName,isDraft,isPrerelease
mapfile -t TAGS < <(gh release list --repo "$REPO" --json tagName --jq '.[].tagName' | sort -V)
[ ${#TAGS[@]} -gt 0 ] || die "$REPO 无任何 release"

log "发现 ${#TAGS[@]} 个 release: ${TAGS[*]}"

# 2. 收集每个 release 的所有资产 URL（保留 tag 来源信息，便于报告）
ASSETS_JSON="$WORK/assets.json"
echo "[]" > "$ASSETS_JSON"

for tag in "${TAGS[@]}"; do
    log "  扫描 release $tag..."
    # gh release view 输出 assets 列表（name + url + size）
    gh release view "$tag" --repo "$REPO" --json assets --jq '.assets[] | {tag: "'"$tag"'", name: .name, url: .url, size: .size}' \
        >> "$WORK/assets-raw.jsonl" || true
done

# 用 python 把 assets-raw.jsonl（每行一个 JSON 对象）合并成数组并分类
python3 - "$WORK/assets-raw.jsonl" "$WORK/assets.json" <<'PYEOF'
import json, sys, re, os

raw_file, out_file = sys.argv[1], sys.argv[2]
assets = []
if os.path.exists(raw_file):
    with open(raw_file) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            # raw.jsonl 每行是 gh --jq 输出的单对象 JSON
            try:
                assets.append(json.loads(line))
            except json.JSONDecodeError:
                # gh 输出可能多行拼成对象，尝试累积解析（罕见，留作 fallback）
                pass

# 去重：同 (name, url) 多个 release 可能复用同一资产（罕见）
seen = set()
unique = []
for a in assets:
    key = (a["name"], a["url"])
    if key not in seen:
        seen.add(key)
        unique.append(a)

with open(out_file, "w") as f:
    json.dump(unique, f, indent=2)
print(f"  唯一资产数: {len(unique)}")
PYEOF

# 3. 清理 dist/ 并重建
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/apt-repo/pool/main" \
         "$DIST_DIR/pip-repo/simple"

# 4. 下载并分类所有资产
#    用 python 实现（避免 bash 循环里多次 curl 慢）
python3 - "$WORK/assets.json" "$DIST_DIR" "$REPO" "$GH_TOKEN" "$WORK" <<'PYEOF'
import os, sys, json, re, shutil, subprocess, hashlib, urllib.request
from concurrent.futures import ThreadPoolExecutor, as_completed

assets_file = sys.argv[1]
dist_dir = sys.argv[2]
repo = sys.argv[3]
token = sys.argv[4]
work_dir = sys.argv[5]

with open(assets_file) as f:
    assets = json.load(f)

apt_pool = os.path.join(dist_dir, "apt-repo", "pool", "main")
pip_simple = os.path.join(dist_dir, "pip-repo", "simple")
os.makedirs(apt_pool, exist_ok=True)
os.makedirs(pip_simple, exist_ok=True)

# 统计报告
report = {
    "deb_count": 0,
    "whl_count": 0,
    "skip_count": 0,
    "skip_files": [],
    "errors": [],
    "deb_by_letter": {},   # {"a": 1, "libg": 2, ...}
    "whl_by_letter": {},  # {"n": 1, "p": 2, ...}
}

def normalize_pip(name):
    """PEP 503: 大写转小写，连续 - _ . 替换为单个 -"""
    return re.sub(r"[-_.]+", "-", name).lower()

def apt_prefix(pkg_name):
    """Debian pool 首字母: lib* 取前 4 字符，其他取首字母"""
    if pkg_name.lower().startswith("lib"):
        return pkg_name[:4].lower()
    return pkg_name[:1].lower()

def download(url, dest):
    """下载到 dest，返回 sha256（None 表示失败）"""
    req = urllib.request.Request(url, headers={"Authorization": f"token {token}"})
    try:
        with urllib.request.urlopen(req, timeout=120) as r, open(dest, "wb") as f:
            data = r.read()
            f.write(data)
            return hashlib.sha256(data).hexdigest()
    except Exception as e:
        return None

# 并发下载（GitHub 限速：认证用户 5000/h，足够）
def process_asset(a):
    name = a["name"]
    url = a["url"]
    tag = a.get("tag", "?")
    lower = name.lower()

    if lower.endswith(".deb"):
        # apt 包
        pkg_name = name.split("_", 1)[0]
        prefix = apt_prefix(pkg_name)
        dest_dir = os.path.join(apt_pool, prefix, pkg_name)
        os.makedirs(dest_dir, exist_ok=True)
        dest = os.path.join(dest_dir, name)
        sha = download(url, dest)
        if sha is None:
            return ("error", f"{name} (from {tag}): 下载失败", a)
        return ("deb", (pkg_name, prefix, sha), a)

    if lower.endswith(".whl"):
        # pip wheel
        # 文件名: {name}-{ver}-{py}-{abi}-{plat}[-{build}].whl
        base = name[:-len(".whl")]
        parts = base.split("-")
        if len(parts) < 5:
            return ("error", f"{name}: wheel 文件名格式不规范", a)
        raw_name = parts[0]
        norm_name = normalize_pip(raw_name)
        first_letter = norm_name[0].lower()
        dest_dir = os.path.join(pip_simple, first_letter, norm_name)
        os.makedirs(dest_dir, exist_ok=True)
        dest = os.path.join(dest_dir, name)
        sha = download(url, dest)
        if sha is None:
            return ("error", f"{name} (from {tag}): 下载失败", a)
        return ("whl", (norm_name, first_letter, sha), a)

    # 跳过的资产（bootstrap.zip / packages.json / wheels-index.json 等）
    return ("skip", name, a)

with ThreadPoolExecutor(max_workers=8) as ex:
    futures = {ex.submit(process_asset, a): a for a in assets}
    for fut in as_completed(futures):
        kind, info, asset = fut.result()
        if kind == "deb":
            pkg_name, prefix, sha = info
            report["deb_count"] += 1
            report["deb_by_letter"].setdefault(prefix, 0)
            report["deb_by_letter"][prefix] += 1
        elif kind == "whl":
            norm_name, letter, sha = info
            report["whl_count"] += 1
            report["whl_by_letter"].setdefault(letter, 0)
            report["whl_by_letter"][letter] += 1
        elif kind == "skip":
            report["skip_count"] += 1
            report["skip_files"].append(info)
        elif kind == "error":
            report["errors"].append(info)

# 写报告
with open(os.path.join(dist_dir, "organize-report.json"), "w") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)

print(f"  .deb 归档: {report['deb_count']} 个")
print(f"  .whl 归档: {report['whl_count']} 个")
print(f"  跳过: {report['skip_count']} 个（bootstrap.zip / *.json 等）")
if report["errors"]:
    print(f"  错误: {len(report['errors'])} 个", file=sys.stderr)
    for e in report["errors"][:5]:
        print(f"    {e}", file=sys.stderr)
PYEOF

log "下载完成，开始重新生成仓库元数据..."

# 5. 重新生成 Debian Packages + Release（基于 apt-repo/pool/main/ 全量扫描）
#    复用 haisa-des-bootstrap 的 make-apt-repo.sh 思路，但这里 dist/apt-repo 已经填好
#    需要重新扫 pool 生成 Packages/Release
#    若 haisa-des-bootstrap 仓库可用，可调它的 make-apt-repo.sh；否则内联简化版
python3 - "$DIST_DIR/apt-repo" <<'PYEOF'
import os, sys, hashlib, gzip, subprocess, io, tarfile, datetime

repo_root = sys.argv[1]
pool_root = os.path.join(repo_root, "pool", "main")
packages_path = os.path.join(repo_root, "dists", "stable", "main", "binary-aarch64", "Packages")
os.makedirs(os.path.dirname(packages_path), exist_ok=True)

def md5sum(p):
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

def sha256sum(p):
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

def parse_control(deb_path):
    try:
        r = subprocess.run(["ar", "p", deb_path, "control.tar.gz"],
                           capture_output=True, check=True)
        with tarfile.open(fileobj=io.BytesIO(r.stdout), mode="r:gz") as tar:
            cf = tar.extractfile("control")
            if cf is None:
                return {}
            text = cf.read().decode("utf-8")
    except Exception:
        return {}
    fields = {}
    cur = None
    for line in text.splitlines():
        if line.startswith((" ", "\t")):
            if cur:
                fields[cur] += "\n" + line
        elif ":" in line:
            k, _, v = line.partition(":")
            fields[k.strip()] = v.strip()
            cur = k.strip()
    return fields

deb_paths = []
for dp, _, fns in os.walk(pool_root):
    for fn in fns:
        if fn.endswith(".deb"):
            deb_paths.append(os.path.join(dp, fn))
deb_paths.sort()

entries = []
for deb_path in deb_paths:
    filename = os.path.relpath(deb_path, repo_root)
    fields = parse_control(deb_path)
    size = os.path.getsize(deb_path)
    entry = [
        f"Package: {fields.get('Package', '')}",
        f"Version: {fields.get('Version', '')}",
        f"Architecture: {fields.get('Architecture', 'aarch64')}",
        f"Maintainer: {fields.get('Maintainer', '')}",
    ]
    if "Installed-Size" in fields:
        entry.append(f"Installed-Size: {fields['Installed-Size']}")
    if "Depends" in fields:
        entry.append(f"Depends: {fields['Depends']}")
    entry.append(f"Priority: {fields.get('Priority', 'optional')}")
    entry.append(f"Description: {fields.get('Description', '')}")
    entry.append(f"Filename: {filename}")
    entry.append(f"Size: {size}")
    entry.append(f"MD5sum: {md5sum(deb_path)}")
    entry.append(f"SHA256: {sha256sum(deb_path)}")
    entries.append("\n".join(entry))

content = "\n\n".join(entries) + "\n"
with open(packages_path, "w") as f:
    f.write(content)
with gzip.open(packages_path + ".gz", "wb") as f:
    f.write(content.encode("utf-8"))

# Release 文件
release_path = os.path.join(repo_root, "dists", "stable", "Release")
now = datetime.datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S UTC")
dists_dir = os.path.join(repo_root, "dists", "stable")
lines = [
    "Origin: haisa-des repository",
    "Label: haisa-des",
    "Suite: stable",
    "Codename: stable",
    f"Date: {now}",
    "Architectures: aarch64",
    "Components: main",
    "Description: haisa-des package repository (organized from Releases)",
    "MD5Sum:",
]
for dp, _, fns in os.walk(dists_dir):
    for fn in fns:
        full = os.path.join(dp, fn)
        rel = os.path.relpath(full, dists_dir)
        size = os.path.getsize(full)
        md5 = md5sum(full)
        lines.append(f" {md5} {size:>16} {rel}")
lines.append("SHA256:")
for dp, _, fns in os.walk(dists_dir):
    for fn in fns:
        full = os.path.join(dp, fn)
        rel = os.path.relpath(full, dists_dir)
        size = os.path.getsize(full)
        sha = sha256sum(full)
        lines.append(f" {sha} {size:>16} {rel}")
with open(release_path, "w") as f:
    f.write("\n".join(lines) + "\n")

print(f"Packages: {packages_path} ({len(entries)} 包)")
print(f"Release:  {release_path}")
PYEOF

# 6. 重新生成 PEP 503 simple index（基于 pip-repo/simple/ 已下载的 wheel）
python3 - "$DIST_DIR/pip-repo" <<'PYEOF'
import os, sys, re, html

pip_root = sys.argv[1]
simple_root = os.path.join(pip_root, "simple")

def normalize(name):
    return re.sub(r"[-_.]+", "-", name).lower()

# 扫描已下载的 wheel，按 <首字母>/<规范化包名>/ 重组 index.html
packages = {}  # norm_name → [(filename, pkg_dir)]
for letter in os.listdir(simple_root):
    if letter in ("index.html", "README.md"):
        continue
    letter_dir = os.path.join(simple_root, letter)
    if not os.path.isdir(letter_dir):
        continue
    for pkg_name in os.listdir(letter_dir):
        pkg_dir = os.path.join(letter_dir, pkg_name)
        if not os.path.isdir(pkg_dir):
            continue
        for fn in os.listdir(pkg_dir):
            if fn.endswith(".whl"):
                norm = normalize(fn.split("-")[0])
                if norm != pkg_name:
                    # 防御: 跳过非本目录对应的 wheel（理论不应发生）
                    continue
                packages.setdefault(norm, []).append((fn, pkg_dir))

# 为每个包生成 index.html
for norm_name, wheels in packages.items():
    pkg_dir = wheels[0][1]
    wheels.sort(key=lambda x: x[0], reverse=True)
    lines = [
        "<!DOCTYPE html>", '<html lang="en">', "<head>",
        '  <meta charset="utf-8">',
        f"  <title>Links for {html.escape(norm_name)}</title>", "</head>", "<body>",
        f"  <h1>Links for {html.escape(norm_name)}</h1>",
        f"  <p>Package: {html.escape(norm_name)} ({len(wheels)} file(s))</p>",
        "  <ul>",
    ]
    for fn, _ in wheels:
        lines.append(f'    <li><a href="{html.escape(fn)}">{html.escape(fn)}</a></li>')
    lines += ["  </ul>", "</body>", "</html>", ""]
    with open(os.path.join(pkg_dir, "index.html"), "w") as f:
        f.write("\n".join(lines))

# 顶层 simple/index.html
sorted_names = sorted(packages.keys())
top_lines = [
    "<!DOCTYPE html>", '<html lang="en">', "<head>",
    '  <meta charset="utf-8">',
    "  <title>haisa-des PEP 503 Simple Index</title>", "</head>", "<body>",
    "  <h1>haisa-des Python Package Index</h1>",
    f"  <p>{len(sorted_names)} packages</p>",
    "  <ul>",
]
for n in sorted_names:
    letter = n[0].lower()
    top_lines.append(f'    <li><a href="{letter}/{n}/">{n}</a></li>')
top_lines += ["  </ul>", "</body>", "</html>", ""]
with open(os.path.join(simple_root, "index.html"), "w") as f:
    f.write("\n".join(top_lines))

print(f"PEP 503 索引重建完成: {len(sorted_names)} 个包")
PYEOF

log ""
log "===== 整理报告 ====="
cat "$DIST_DIR/organize-report.json" | python3 -m json.tool 2>/dev/null | head -30
log ""
log "===== 仓库结构 ====="
find "$DIST_DIR" -type d | sort | head -30
log ""
log "产物: $DIST_DIR/"
log "  apt-repo/  $(find "$DIST_DIR/apt-repo" -name '*.deb' | wc -l) 个 .deb"
log "  pip-repo/  $(find "$DIST_DIR/pip-repo" -name '*.whl' | wc -l) 个 .whl"
log ""
log "下一步: 部署 dist/apt-repo/ + dist/pip-repo/ 到 gh-pages 分支"
