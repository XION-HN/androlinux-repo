#!/usr/bin/env bash
# organize-repo.sh —— 扫描 haisa-des-repo Release 资产，生成索引部署到 gh-pages
#
# 设计（index + pool 模式 + 并行扫描）:
#   - gh-pages 存索引（HTML / Packages / Release）+ apt 的 .deb pool
#   - PEP 503 simple/<首字母>/<包名>/index.html 的 href 用 Releases 绝对 URL（pip 支持）
#   - apt Packages 的 Filename 字段用相对 apt-repo 根的路径（apt 不支持绝对 URL）
#     .deb 下载到 apt-repo/pool/main/<首字母>/<包名>/ 下
#   - 并行扫描 26 个 release（xargs -P 8），减少总扫描时间
#
# Release 布局（固定 26 个 tag）:
#   pip-a / pip-b / ... / pip-z
#   每个文件按首字母归到对应 release（同名 clobber 覆盖）
#
# 触发方式:
#   - 手动: workflow_dispatch
#   - 自动: repository_dispatch（bootstrap CI 发版后调用）
#
# 用法:
#   REPO=XION-HN/haisa-des-repo GH_TOKEN=$TOKEN ./scripts/organize-repo.sh
set -euo pipefail

REPO="${REPO:-XION-HN/haisa-des-repo}"
: "${GH_TOKEN:?GH_TOKEN 未设置（需 haisa-des-repo 的 PAT）}"

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST_DIR="$ROOT/dist"

log()  { printf '\033[1;34m[organize]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[warn]\033[0m %s\n' "$*" >&2; }
die()  { printf '\033[1;31m[error]\033[0m %s\n' "$*" >&2; exit 1; }

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# 1. 列出所有 release tag（26 个 pip-* 固定 tag + 其他动态 tag）
log "扫描 $REPO 所有 release tag..."
mapfile -t ALL_TAGS < <(gh release list --repo "$REPO" --json tagName --jq '.[].tagName' | sort -V)
[ ${#ALL_TAGS[@]} -gt 0 ] || die "$REPO 无任何 release"
log "共 ${#ALL_TAGS[@]} 个 release: ${ALL_TAGS[*]}"

# 2. 并行扫描所有 release 资产元数据（不下载文件本体）
ASSETS_RAW="$WORK/assets-raw.jsonl"
: > "$ASSETS_RAW"

scan_one_release() {
    local tag="$1"
    gh release view "$tag" --repo "$REPO" --json assets \
        --jq ".assets[] | {tag: \"$tag\", name: .name, url: .url, size: .size, content_type: .contentType}"
}
export -f scan_one_release
export REPO WORK ASSETS_RAW

log "并行扫描 ${#ALL_TAGS[@]} 个 release（8 并发）..."
printf '%s\n' "${ALL_TAGS[@]}" | xargs -P 8 -I {} bash -c 'scan_one_release "{}"' >> "$ASSETS_RAW" 2>/dev/null || true

ASSET_COUNT=$(wc -l < "$ASSETS_RAW")
log "资产总数: $ASSET_COUNT 个"

# 3. 清理 dist/ 重建
rm -rf "$DIST_DIR"
mkdir -p "$DIST_DIR/apt-repo/dists/stable/main/binary-aarch64" \
         "$DIST_DIR/apt-repo/pool/main" \
         "$DIST_DIR/pip-repo/simple"

# 4. 用 Python 生成索引（不下载文件本体）
TAGS_JSON=$(printf '%s' "${ALL_TAGS[*]}" | python3 -c "import sys, json; print(json.dumps(sys.stdin.read().split()))")
python3 - "$ASSETS_RAW" "$DIST_DIR" "$REPO" "$WORK" "$TAGS_JSON" <<'PYEOF'
import os, sys, json, re, html, datetime

raw_file = sys.argv[1]
dist_dir = sys.argv[2]
repo = sys.argv[3]
work_dir = sys.argv[4]
tags_list = json.loads(sys.argv[5])

def release_url(tag, name):
    return f"https://github.com/{repo}/releases/download/{tag}/{name}"

# 读取所有资产
assets = []
with open(raw_file) as f:
    for line in f:
        line = line.strip()
        if not line:
            continue
        try:
            assets.append(json.loads(line))
        except json.JSONDecodeError:
            pass

print(f"  解析资产: {len(assets)} 个")

# 规范化函数
def normalize_pip(name):
    """PEP 503 规范化：大写转小写，连续 - _ . 替换为单个 -"""
    return re.sub(r"[-_.]+", "-", name).lower()

def apt_prefix(pkg_name):
    """Debian pool 首字母：lib* 取前 4 字符，其他取首字母"""
    if pkg_name.lower().startswith("lib"):
        return pkg_name[:4].lower()
    return pkg_name[:1].lower()

# 分类
deb_entries = []
whl_by_pkg = {}
skip_files = []

for a in assets:
    name = a["name"]
    lower = name.lower()
    tag = a.get("tag", "?")
    url = a.get("url") or release_url(tag, name)
    size = a.get("size", 0)

    if lower.endswith(".deb"):
        # Debian 包名格式: <name>_<version>_<arch>.deb
        pkg_name = name.split("_", 1)[0]
        prefix = apt_prefix(pkg_name)
        deb_entries.append({
            "name": name, "tag": tag, "url": url, "size": size,
            "pkg_name": pkg_name, "prefix": prefix,
        })
    elif lower.endswith(".whl"):
        # wheel 格式: <name>-<ver>-<py>-<abi>-<plat>[-<build>].whl
        base = name[:-len(".whl")]
        parts = base.split("-")
        if len(parts) < 5:
            skip_files.append((name, "wheel 文件名格式不规范"))
            continue
        raw_name = parts[0]
        norm_name = normalize_pip(raw_name)
        whl_by_pkg.setdefault(norm_name, []).append({
            "name": name, "tag": tag, "url": url, "size": size,
        })
    else:
        skip_files.append((name, "非 .deb/.whl（保留在 Releases，不索引）"))

# 5. 生成 PEP 503 simple 索引
simple_root = os.path.join(dist_dir, "pip-repo", "simple")
os.makedirs(simple_root, exist_ok=True)

pkg_names_sorted = sorted(whl_by_pkg.keys())
for norm_name in pkg_names_sorted:
    first_letter = norm_name[0].lower()
    pkg_dir = os.path.join(simple_root, first_letter, norm_name)
    os.makedirs(pkg_dir, exist_ok=True)

    wheels = sorted(whl_by_pkg[norm_name], key=lambda w: w["name"], reverse=True)
    lines = [
        "<!DOCTYPE html>",
        '<html lang="en">',
        "<head>",
        '  <meta charset="utf-8">',
        f"  <title>Links for {html.escape(norm_name)}</title>",
        "</head>",
        "<body>",
        f"  <h1>Links for {html.escape(norm_name)}</h1>",
        f"  <p>Package: {html.escape(norm_name)} ({len(wheels)} file(s))</p>",
        "  <ul>",
    ]
    for w in wheels:
        href = w["url"]
        size_mb = w["size"] / 1024 / 1024
        lines.append(f'    <li><a href="{html.escape(href)}">{html.escape(w["name"])}</a> ({size_mb:.1f} MB)</li>')
    lines += ["  </ul>", "</body>", "</html>", ""]
    with open(os.path.join(pkg_dir, "index.html"), "w") as f:
        f.write("\n".join(lines))

# 顶层 simple/index.html
top_lines = [
    "<!DOCTYPE html>",
    '<html lang="en">',
    "<head>",
    '  <meta charset="utf-8">',
    "  <title>haisa-des PEP 503 Simple Index</title>",
    "</head>",
    "<body>",
    "  <h1>haisa-des Python Package Index</h1>",
    f"  <p>{len(pkg_names_sorted)} packages</p>",
    "  <ul>",
]
for n in pkg_names_sorted:
    letter = n[0].lower()
    top_lines.append(f'    <li><a href="{letter}/{n}/">{n}</a></li>')
top_lines += ["  </ul>", "</body>", "</html>", ""]
with open(os.path.join(simple_root, "index.html"), "w") as f:
    f.write("\n".join(top_lines))

# 6. 生成 apt Packages
# 关键修复: apt 的 Filename 字段不支持绝对 URL，必须用相对仓库根的路径。
# 之前的注释 "apt 2.8.1 支持绝对 URL" 是错误的——apt 会把绝对 URL 当相对路径，
# 拼成 <基址>/https://github.com/... 的错误 URL，导致下载失败。
# 修复: 下载 .deb 到 apt-repo/pool/main/<首字母>/<包名>/ 下，Filename 写相对路径。
packages_path = os.path.join(dist_dir, "apt-repo", "dists", "stable", "main", "binary-aarch64", "Packages")
os.makedirs(os.path.dirname(packages_path), exist_ok=True)

repo_root = os.path.join(dist_dir, "apt-repo")

# 从 .deb 文件名提取 Package/Version/Architecture
import urllib.request

def download_deb(url, dst):
    """下载 .deb 到 pool 下（带重试）"""
    for attempt in range(3):
        try:
            urllib.request.urlretrieve(url, dst)
            return True
        except Exception as e:
            if attempt == 2:
                print(f"    ⚠ 下载失败: {url} -> {e}")
            else:
                import time; time.sleep(2)
    return False

def md5sum_file(path):
    import hashlib
    h = hashlib.md5()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

def sha256sum_file(path):
    import hashlib
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(65536), b""):
            h.update(chunk)
    return h.hexdigest()

entries = []
downloaded = 0
download_failed = 0
for d in deb_entries:
    parts = d["name"].rsplit("_", 2)
    if len(parts) != 3:
        continue
    pkg_name, version, arch_file = parts
    arch = arch_file[:-len(".deb")]
    # pool 布局: pool/main/<首字母>/<包名>/<deb>
    pool_dir = os.path.join(repo_root, "pool", "main", d["prefix"], pkg_name)
    os.makedirs(pool_dir, exist_ok=True)
    deb_path = os.path.join(pool_dir, d["name"])
    # 下载 .deb（若已存在且大小匹配则跳过）
    if not (os.path.isfile(deb_path) and os.path.getsize(deb_path) == d["size"]):
        if download_deb(d["url"], deb_path):
            downloaded += 1
        else:
            download_failed += 1
            continue
    # Filename: 相对 apt-repo 根的路径（apt 规范）
    filename_rel = os.path.relpath(deb_path, repo_root)
    # 计算 MD5sum 和 SHA256（apt 下载校验必需，否则报
    # "Insufficient information available to perform this download securely"）
    md5 = md5sum_file(deb_path)
    sha256 = sha256sum_file(deb_path)
    entry = [
        f"Package: {pkg_name}",
        f"Version: {version}",
        f"Architecture: {arch}",
        "Maintainer: haisa-des <noreply@haisa-des.local>",
        "Priority: optional",
        f"Description: {pkg_name} package (from release {d['tag']})",
        f"Filename: {filename_rel}",
        f"Size: {d['size']}",
        f"MD5sum: {md5}",
        f"SHA256: {sha256}",
    ]
    entries.append("\n".join(entry))
print(f"  .deb 下载: {downloaded} 成功, {download_failed} 失败")

content = "\n\n".join(entries) + ("\n" if entries else "")
with open(packages_path, "w") as f:
    f.write(content)
import gzip
with gzip.open(packages_path + ".gz", "wb") as f:
    f.write(content.encode("utf-8"))

# 7. 生成 apt Release
release_path = os.path.join(dist_dir, "apt-repo", "dists", "stable", "Release")
dists_dir = os.path.dirname(release_path)

def md5sum(p):
    import hashlib
    h = hashlib.md5()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

def sha256sum(p):
    import hashlib
    h = hashlib.sha256()
    with open(p, "rb") as f:
        for c in iter(lambda: f.read(65536), b""):
            h.update(c)
    return h.hexdigest()

now = datetime.datetime.utcnow().strftime("%a, %d %b %Y %H:%M:%S UTC")
lines = [
    "Origin: haisa-des repository",
    "Label: haisa-des",
    "Suite: stable",
    "Codename: stable",
    f"Date: {now}",
    "Architectures: aarch64",
    "Components: main",
    "Description: haisa-des package repository (index-only, files in GitHub Releases)",
    "MD5Sum:",
]
for dp, _, fns in os.walk(dists_dir):
    for fn in fns:
        full = os.path.join(dp, fn)
        rel = os.path.relpath(full, dists_dir)
        size = os.path.getsize(full)
        lines.append(f" {md5sum(full)} {size:>16} {rel}")
lines.append("SHA256:")
for dp, _, fns in os.walk(dists_dir):
    for fn in fns:
        full = os.path.join(dp, fn)
        rel = os.path.relpath(full, dists_dir)
        size = os.path.getsize(full)
        lines.append(f" {sha256sum(full)} {size:>16} {rel}")
with open(release_path, "w") as f:
    f.write("\n".join(lines) + "\n")

# 8. 写整理报告
report = {
    "generated_at": now,
    "tag_scanned": tags_list,
    "deb_count": len(deb_entries),
    "whl_count": sum(len(v) for v in whl_by_pkg.values()),
    "whl_pkg_count": len(whl_by_pkg),
    "skip_count": len(skip_files),
    "skip_files": [n for n, _ in skip_files[:30]],
    "deb_by_letter": {},
    "whl_by_letter": {},
}
for d in deb_entries:
    report["deb_by_letter"].setdefault(d["prefix"], 0)
    report["deb_by_letter"][d["prefix"]] += 1
for norm_name, ws in whl_by_pkg.items():
    letter = norm_name[0].lower()
    report["whl_by_letter"].setdefault(letter, 0)
    report["whl_by_letter"][letter] += len(ws)

with open(os.path.join(dist_dir, "organize-report.json"), "w") as f:
    json.dump(report, f, indent=2, ensure_ascii=False)

print(f"  .deb 索引: {report['deb_count']} 个")
print(f"  .whl 索引: {report['whl_count']} 个 ({report['whl_pkg_count']} 个包)")
print(f"  跳过: {report['skip_count']} 个")
PYEOF

log ""
log "===== 整理报告 ====="
python3 -c "
import json
with open('$DIST_DIR/organize-report.json') as f:
    r = json.load(f)
print(f'  .deb 索引: {r[\"deb_count\"]} 个')
print(f'  .whl 索引: {r[\"whl_count\"]} 个 ({r[\"whl_pkg_count\"]} 个包)')
print(f'  跳过: {r[\"skip_count\"]} 个（*.tar.gz / *.zip / *.json 等）')
print('  apt 首字母分布:')
for letter, n in sorted(r.get('deb_by_letter', {}).items()):
    print(f'    {letter}/  {n} 个')
print('  pip 首字母分布:')
for letter, n in sorted(r.get('whl_by_letter', {}).items()):
    print(f'    {letter}/  {n} 个')
" || true

log ""
log "产物: $DIST_DIR/"
log "  apt-repo/  $(find "$DIST_DIR/apt-repo" -name 'Packages' 2>/dev/null | wc -l) 个 Packages"
log "  pip-repo/  $(find "$DIST_DIR/pip-repo" -name 'index.html' 2>/dev/null | wc -l) 个 index.html"
log ""
log "下一步: 部署 dist/apt-repo/ + dist/pip-repo/ 到 gh-pages 分支"
