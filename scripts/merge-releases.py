#!/usr/bin/env python3
"""
merge-releases.py —— 将多个 release 的资产按首字母合并到 26 个新 release，删除旧 release

流程:
  1. 列出所有原 release 的资产
  2. 去重（同文件名取最新 tag 的版本）
  3. 按首字母分组（a-z）
  4. 下载所有资产到本地临时目录
  5. 创建 26 个新 release（a / b / c / ... / z）
  6. 上传资产到对应 release
  7. 删除原 5 个 release

用法:
  GH_TOKEN=ghp_xxx REPO=XION-HN/haisa-des-repo python3 merge-releases.py

环境变量:
  GH_TOKEN  - GitHub PAT（需 admin 权限）
  REPO      - 仓库（默认 XION-HN/haisa-des-repo）
  OLD_TAGS  - 要删除的旧 tag（逗号分隔，默认 v0.0.1,v0.1.4,v0.2.0,v0.3.0,v0.4.0）
  DRY_RUN   - true=只预览不执行（默认 false）
  SKIP_DOWNLOAD - true=跳过下载（已下载过，默认 false）
"""
import os, sys, json, re, subprocess, tempfile, shutil
from collections import defaultdict
from pathlib import Path

REPO = os.environ.get("REPO", "XION-HN/haisa-des-repo")
GH_TOKEN = os.environ.get("GH_TOKEN", "")
OLD_TAGS = os.environ.get("OLD_TAGS", "v0.0.1,v0.1.4,v0.2.0,v0.3.0,v0.4.0").split(",")
DRY_RUN = os.environ.get("DRY_RUN", "false").lower() == "true"
SKIP_DOWNLOAD = os.environ.get("SKIP_DOWNLOAD", "false").lower() == "true"

if not GH_TOKEN:
    print("错误: GH_TOKEN 未设置", file=sys.stderr)
    sys.exit(1)

WORK_DIR = Path(tempfile.mkdtemp(prefix="merge-releases-"))
DOWNLOAD_DIR = WORK_DIR / "downloads"
DOWNLOAD_DIR.mkdir(parents=True, exist_ok=True)

def gh(*args, input=None, check=True):
    """调用 gh CLI"""
    cmd = ["gh"] + list(args) + ["-R", REPO]
    env = {**os.environ, "GH_TOKEN": GH_TOKEN}
    r = subprocess.run(cmd, capture_output=True, text=True, input=input, env=env)
    if check and r.returncode != 0:
        print(f"gh 命令失败: {' '.join(cmd)}", file=sys.stderr)
        print(f"stderr: {r.stderr}", file=sys.stderr)
        raise subprocess.CalledProcessError(r.returncode, cmd, r.stdout, r.stderr)
    return r

def gh_raw(*args):
    """调用 gh CLI 不检查返回码"""
    return gh(*args, check=False)

def get_release_assets(tag):
    """获取某 release 的所有资产"""
    r = gh("release", "view", tag, "--json", "assets")
    data = json.loads(r.stdout)
    return data.get("assets", [])

def download_asset(url, dest):
    """下载资产到本地"""
    if dest.exists() and dest.stat().st_size > 0:
        print(f"  跳过（已存在）: {dest.name}")
        return True
    cmd = ["curl", "-fL", "-o", str(dest), url]
    r = subprocess.run(cmd, capture_output=True, text=True)
    if r.returncode != 0:
        print(f"  下载失败: {dest.name}: {r.stderr}", file=sys.stderr)
        return False
    return True

def create_release(tag, title, notes):
    """创建 release（如已存在先删除）"""
    r = gh_raw("release", "view", tag)
    if r.returncode == 0:
        print(f"  release {tag} 已存在，先删除")
        gh("release", "delete", tag, "--yes")
    gh("release", "create", tag, "--title", title, "--notes", notes)

def upload_assets(tag, files):
    """上传资产到 release"""
    for f in files:
        print(f"  上传: {f.name} ({f.stat().st_size/1024/1024:.1f} MB)")
        gh("release", "upload", tag, str(f), "--clobber")

def delete_release(tag):
    """删除 release"""
    print(f"  删除 release: {tag}")
    gh("release", "delete", tag, "--yes")

def get_letter(name):
    """获取首字母"""
    base = name.rsplit(".", 1)[0]
    if base.endswith(".tar"):
        base = base[:-4]
    first_seg = base.split("-")[0].split("_")[0].lower()
    norm = re.sub(r"[-_.]+", "-", first_seg).lower()
    return norm[0] if norm else "_"

def main():
    tag_priority = {"v0.4.0": 4, "v0.3.0": 3, "v0.2.0": 2, "v0.1.4": 1, "v0.0.1": 0}

    print("=" * 60)
    print("步骤 1: 收集所有 release 资产")
    print("=" * 60)
    all_assets = []
    for tag in OLD_TAGS:
        print(f"  扫描 {tag}...")
        assets = get_release_assets(tag)
        for a in assets:
            a["source_tag"] = tag
            all_assets.append(a)
        print(f"    {len(assets)} 个资产")

    print(f"\n总资产: {len(all_assets)} 个")

    print("\n" + "=" * 60)
    print("步骤 2: 去重（同文件名取最新 tag）")
    print("=" * 60)
    by_name = defaultdict(list)
    for a in all_assets:
        by_name[a["name"]].append(a)

    deduped = []
    dup_count = 0
    for name, items in by_name.items():
        items.sort(key=lambda x: tag_priority.get(x["source_tag"], -1), reverse=True)
        deduped.append(items[0])
        if len(items) > 1:
            dup_count += 1

    print(f"  去重后: {len(deduped)} 个文件（去除 {dup_count} 个重复）")
    print(f"  总体积: {sum(a['size'] for a in deduped)/1024/1024/1024:.2f} GB")

    print("\n" + "=" * 60)
    print("步骤 3: 按首字母分组")
    print("=" * 60)
    by_letter = defaultdict(list)
    for a in deduped:
        letter = get_letter(a["name"])
        by_letter[letter].append(a)

    for letter in sorted(by_letter.keys()):
        items = by_letter[letter]
        size = sum(a["size"] for a in items)
        flag = " ⚠ 超2GB!" if size > 2*1024*1024*1024 else ""
        print(f"  {letter}: {len(items)} 个文件, {size/1024/1024:.1f} MB{flag}")

    if any(sum(a["size"] for a in items) > 2*1024*1024*1024 for items in by_letter.values()):
        print("\n错误: 有字母超过 2 GB 限制！", file=sys.stderr)
        sys.exit(1)

    if DRY_RUN:
        print("\n[DRY_RUN] 预览模式，不执行实际操作")
        print(f"  将创建 {len(by_letter)} 个新 release（a-z）")
        print(f"  将删除 {len(OLD_TAGS)} 个旧 release: {OLD_TAGS}")
        return

    if not SKIP_DOWNLOAD:
        print("\n" + "=" * 60)
        print("步骤 4: 下载所有资产（按原 release 批量下载）")
        print("=" * 60)
        # 按原 tag 分组批量下载（gh release download 一次拉整个 release）
        for tag in OLD_TAGS:
            print(f"\n  批量下载 {tag}...")
            r = subprocess.run(
                ["gh", "release", "download", tag, "-R", REPO, "--dir", str(DOWNLOAD_DIR), "--clobber"],
                capture_output=True, text=True, env={**os.environ, "GH_TOKEN": GH_TOKEN}
            )
            if r.returncode != 0:
                print(f"  批量下载 {tag} 失败: {r.stderr}", file=sys.stderr)
                # 回退到逐个下载
                print(f"  回退到逐个下载...")
                for a in deduped:
                    if a["source_tag"] != tag:
                        continue
                    dest = DOWNLOAD_DIR / a["name"]
                    if dest.exists() and dest.stat().st_size > 0:
                        continue
                    url = a.get("url", "") or f"https://github.com/{REPO}/releases/download/{tag}/{a['name']}"
                    download_asset(url, dest)
            else:
                print(f"  {tag} 下载完成")
        dl_count = len(list(DOWNLOAD_DIR.iterdir()))
        dl_size = sum(f.stat().st_size for f in DOWNLOAD_DIR.iterdir() if f.is_file())
        print(f"\n下载完成: {dl_count} 个文件, {dl_size/1024/1024/1024:.2f} GB")

    print("\n" + "=" * 60)
    print("步骤 5: 创建 26 个新 release 并上传资产")
    print("=" * 60)
    for letter in sorted(by_letter.keys()):
        items = by_letter[letter]
        tag = f"pip-{letter}"
        title = f"Python packages - {letter}"
        notes = f"""# Python packages starting with '{letter}'

Contains {len(items)} files ({sum(a['size'] for a in items)/1024/1024:.1f} MB).

## Contents
"""
        for a in items[:10]:
            notes += f"- {a['name']} ({a['size']/1024/1024:.1f} MB)\n"
        if len(items) > 10:
            notes += f"- ... and {len(items)-10} more\n"

        notes += f"\nMigrated from releases: {', '.join(OLD_TAGS)}\n"
        notes += "Deduplicated: same filename kept from latest tag.\n"

        print(f"\n  创建 release {tag} ({len(items)} 个文件)...")
        create_release(tag, title, notes)

        files = [DOWNLOAD_DIR / a["name"] for a in items if (DOWNLOAD_DIR / a["name"]).exists()]
        print(f"  上传 {len(files)} 个文件...")
        upload_assets(tag, files)

    print("\n" + "=" * 60)
    print("步骤 6: 删除原 release")
    print("=" * 60)
    for tag in OLD_TAGS:
        delete_release(tag)

    print("\n" + "=" * 60)
    print("完成！")
    print("=" * 60)
    print(f"  创建了 {len(by_letter)} 个新 release（pip-a ~ pip-z）")
    print(f"  删除了 {len(OLD_TAGS)} 个旧 release")
    print(f"  总资产: {len(deduped)} 个文件 ({sum(a['size'] for a in deduped)/1024/1024/1024:.2f} GB)")
    print(f"  临时目录: {WORK_DIR}")
    print(f"\n下一步: 触发 organize workflow 重新生成 gh-pages 索引")

if __name__ == "__main__":
    main()
