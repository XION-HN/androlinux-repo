# haisa-des-repo

HaisaDes 项目的**公开发布仓库**，托管 GitHub Releases 资产与 apt / pip 仓库索引（通过 gh-pages 分支提供）。

> 本仓库不存放源码。所有构建配方和 CI 在 [`XION-HN/haisa-des-bootstrap`](https://github.com/XION-HN/haisa-des-bootstrap) 仓库；Android App 源码在 [`XION-HN/haisa-des`](https://github.com/XION-HN/haisa-des) 仓库。

---

## 目录

- [仓库职责](#仓库职责)
- [目录结构](#目录结构)
- [仓库规范](#仓库规范)
- [Release 布局](#release-布局)
- [首字母规则](#首字母规则)
- [CI 自动化整理系统](#ci-自动化整理系统)
- [提交规范](#提交规范)
- [提交方式](#提交方式)
- [资产清单](#资产清单)
- [下载与使用](#下载与使用)
- [相关仓库](#相关仓库)
- [合规](#合规)

---

## 仓库职责

| 职责 | 实现位置 |
|---|---|
| 托管 GitHub Releases 资产（wheel/.deb/zip/json 等） | `Releases`（bootstrap CI 自动按首字母上传） |
| 托管 Debian apt 仓库元数据 | `gh-pages` 分支 `apt-repo/` |
| 托管 PEP 503 pip 索引 | `gh-pages` 分支 `pip-repo/` |
| 自动整理索引 | `.github/workflows/organize.yml` |
| 一次性迁移/合并工具 | `scripts/merge-releases.py` |

**分工原则**：
- **本仓库**只存放索引元数据和 release 资产，不存放任何构建脚本或源码。
- **bootstrap 仓库**负责编译和上传资产，上传完成后自动触发本仓库整理。
- **gh-pages 分支**由 CI 自动维护，禁止手动修改。

---

## 目录结构

### `main` 分支

```
haisa-des-repo/
├── .github/
│   └── workflows/
│       ├── organize.yml         # 自动整理 workflow（repository_dispatch + workflow_dispatch）
│       └── merge-releases.yml   # 一次性 release 合并工具（手动触发）
├── scripts/
│   ├── organize-repo.sh        # 整理脚本（扫描 release、生成 apt + pip 索引、部署 gh-pages）
│   └── merge-releases.py       # 一次性迁移脚本（合并多个 release 到 26 个字母 release）
├── LICENSES/
│   ├── NOTICE.md
│   └── termux-app-LICENSE.md
└── README.md
```

### `gh-pages` 分支（CI 自动生成，禁止手动修改）

```
gh-pages/
├── apt-repo/                                 # Debian 仓库
│   └── dists/stable/
│       ├── Release                           # 仓库元数据
│       ├── InRelease                         # GPG 签名（可选，需配置 Secret）
│       ├── Release.gpg                       # GPG 签名（可选）
│       └── main/binary-aarch64/
│           ├── Packages                      # apt 包索引
│           └── Packages.gz                   # 压缩版
└── pip-repo/                                 # PEP 503 Python 索引
    └── simple/
        ├── index.html                        # 顶层索引（列出所有包）
        └── <首字母>/
            └── <规范化包名>/
                └── index.html                # 该包所有 wheel 下载链接
```

---

## 仓库规范

### 允许的操作

- 在 `main` 分支修改：`scripts/`、`.github/workflows/`、`LICENSES/`、`README.md`
- 在 Actions 页面手动触发 `organize-repo` workflow
- 在 Actions 页面手动触发 `merge-releases` workflow（一次性合并工具）

### 禁止的操作

- **禁止**手动修改 `gh-pages` 分支任何内容（会被 CI 覆盖）
- **禁止**手动上传/删除/修改 Releases 资产（应由 bootstrap CI 自动维护）
- **禁止**在本仓库直接 commit 二进制文件（wheel / .deb / .zip / .tar.gz）
- **禁止**手动创建/删除 release tag（应由 bootstrap CI 自动创建）
- **禁止**手动修改仓库设置（Pages source、Branch protection 等）

### Release 命名规范

- 固定 26 个 tag：`pip-a` / `pip-b` / ... / `pip-z`（小写）
- 由 bootstrap CI 在首次发版时自动创建（如已存在则跳过创建，直接上传覆盖）
- **禁止**创建其他格式的 tag（如 `v1.0.0` / `bootstrap-v0.5.0`）

### 仓库设置要求

- **GitHub Pages**：Source = `Deploy from a branch`，Branch = `gh-pages` / `(root)`
- **Branches**：`main` 分支建议开启 branch protection（require pull request review）
- **Actions**：`Allow all actions and reusable workflows`
- **Secrets**：
  - `HAISADES_GPG_PRIVATE_KEY`（可选）：GPG 私钥，用于签名 apt Release
  - `RELEASE_REPO_TOKEN`（在 bootstrap 仓库中）：本仓库的 PAT（需 `contents:write` + `actions:write` 权限）

---

## Release 布局

### 固定 26 个 tag（pip-a ~ pip-z）

所有资产按文件名首字母归到对应 release：

| Release tag | 包含的资产示例 |
|---|---|
| `pip-a` | attrs / aiohttp / async-timeout 等 |
| `pip-b` | bootstrap-arm64-v8a.zip / boto3 / beautifulsoup4 等 |
| `pip-c` | certifi / charset-normalizer / click 等 |
| `pip-l` | libandroid-glob / libffi / libgcrypt 等 |
| `pip-n` | numpy / networkx 等 |
| `pip-p` | packages.json / pillow / pip 等 |
| ... | ... |
| `pip-z` | zipp / zstandard 等 |

### 设计理由

| 项 | 旧方案（单 release） | 新方案（26 个字母 release） |
|---|---|---|
| 单 release 体积 | 超 2 GB（GitHub 限制） | 每个字母 < 2 GB |
| 同名覆盖 | 全局覆盖 | 仅同字母内覆盖 |
| 客户端兼容 | 完全兼容 | 完全兼容（href 指向绝对 URL） |
| 扫描速度 | 慢（单 release 大） | 快（并行扫描 26 个） |

---

## 首字母规则

**所有资产（.whl / .deb / .zip / .tar.gz / .json）统一按以下规则计算首字母**：

1. **取文件名第一段**：
   - `.whl`：`numpy-2.1.0-cp313-cp313-manylinux_2_17_aarch64.whl` → `numpy`
   - `.deb`：`libgcrypt_1.10.3_aarch64.deb` → `libgcrypt`
   - `.zip`：`bootstrap-arm64-v8a.zip` → `bootstrap`
   - `.json`：`packages.json` → `packages`

2. **规范化**（与 PEP 503 一致）：
   - 大写转小写
   - 连续的 `-` `_` `.` 合并为单个 `-`

3. **取首字母**（小写）：
   - `numpy` → `n` → `pip-n`
   - `libgcrypt` → `l` → `pip-l`
   - `bootstrap` → `b` → `pip-b`
   - `packages` → `p` → `pip-p`

**实现位置**（必须保持一致）：
- [scripts/organize-repo.sh](scripts/organize-repo.sh) 中的 `normalize_pip` / `apt_prefix` / 首字母提取
- bootstrap CI 的 `get_letter()` 函数（`.github/workflows/ci.yml` 的 "Publish assets" step）
- [scripts/merge-releases.py](scripts/merge-releases.py) 中的 `get_letter`

---

## CI 自动化整理系统

### 整理流程

```
bootstrap CI (tag 触发)
  ↓
  1. 编译所有包 + wheel
  2. 按首字母上传到 haisa-des-repo 的 26 个 release（--clobber 覆盖）
  3. 调用 repository_dispatch 触发 haisa-des-repo 的 organize workflow
  ↓
haisa-des-repo organize workflow (repository_dispatch 触发)
  ↓
  1. 并行扫描 26 个 release（8 并发）
  2. 生成 apt Packages + Release（gh-pages/apt-repo/）
  3. 生成 PEP 503 simple 索引（gh-pages/pip-repo/）
  4. 部署到 gh-pages 分支
  ↓
GitHub Pages 自动构建
  ↓
  https://xion-hn.github.io/haisa-des-repo/{apt-repo,pip-repo}/...
```

### 触发方式

| 触发方式 | 何时用 | 配置 |
|---|---|---|
| `repository_dispatch`（自动） | bootstrap CI 发版后自动触发 | bootstrap CI 调用 `gh api repos/XION-HN/haisa-des-repo/dispatches -f event_type=organize-repo` |
| `workflow_dispatch`（手动） | 仓库 owner 在 Actions 页面手动触发 | Actions → organize-repo → Run workflow |

### organize workflow 步骤

1. **Install dependencies**：安装 gnupg / python3 / git / curl / jq
2. **Show trigger info**：显示触发方式（自动/手动）和 payload
3. **Run organize-repo.sh**：扫描 26 个 release，生成 apt + pip 索引
4. **Sign Release（可选）**：用 GPG 私钥签名 apt Release（需 `HAISADES_GPG_PRIVATE_KEY` Secret）
5. **Upload organize report**：上传 `organize-report.json` artifact（保留 30 天）
6. **Deploy to gh-pages**：清空 gh-pages，部署新的 apt-repo + pip-repo

### bootstrap CI 的上传逻辑

在 [haisa-des-bootstrap/.github/workflows/ci.yml](https://github.com/XION-HN/haisa-des-bootstrap/blob/main/.github/workflows/ci.yml) 的 "Publish assets" step：

```bash
# 1. 确保 26 个 release 存在
for c in {a..z}; do
  gh release create "pip-$c" --repo XION-HN/haisa-des-repo ...
done

# 2. 按首字母分发上传
for f in dist/wheels/*.whl dist/packages/*.deb ...; do
  letter=$(get_letter "$(basename "$f")")
  gh release upload "pip-$letter" --repo XION-HN/haisa-des-repo "$f" --clobber
done

# 3. 触发整理
gh api repos/XION-HN/haisa-des-repo/dispatches \
  -f event_type=organize-repo \
  -f client_payload[release_tag]=$TAG
```

### index-only 模式

**gh-pages 只存索引，不存文件本体**：

| 项 | gh-pages（索引） | Releases（文件本体） |
|---|---|---|
| 内容 | `index.html` / `Packages` / `Release` | `.whl` / `.deb` / `.zip` |
| 体积 | < 5 MB | 数 GB |
| 更新方式 | CI 全量重建 | bootstrap CI 上传覆盖 |
| 客户端访问 | pip/apt 先读索引 | 根据 href 跳转到 Releases 下载 |

**理由**：GitHub Pages 单仓库推荐 < 1 GB，全量托管 wheel 会超限并导致 push HTTP 500。

---

## 提交规范

### Conventional Commits

所有 commit message 必须遵循 [Conventional Commits](https://www.conventionalcommits.org/)：

```
<type>(<scope>): <subject>

<body>

<footer>
```

### type（必填）

| type | 用途 |
|---|---|
| `feat` | 新功能 |
| `fix` | 修复 bug |
| `docs` | 文档变更（README / 注释） |
| `style` | 代码格式（不影响功能） |
| `refactor` | 重构（ neither feat nor fix ） |
| `perf` | 性能优化 |
| `test` | 测试相关 |
| `chore` | 构建/工具/CI 配置 |
| `ci` | CI 配置变更 |
| `revert` | 回滚 commit |

### scope（可选）

本仓库常用的 scope：

| scope | 用途 |
|---|---|
| `organize` | 整理脚本/工作流 |
| `merge` | 一次性合并工具 |
| `gh-pages` | gh-pages 部署相关 |
| `readme` | README 变更 |
| `release` | Release 相关 |

### subject（必填）

- 简明描述变更内容
- 不超过 50 字符
- 不以句号结尾
- 用祈使句（如 "add" 而非 "added"）

### 示例

```
feat(organize): 支持并行扫描 26 个 release

用 xargs -P 8 并行调用 gh release view，扫描时间从 60s 降到 10s。

更新 organize-repo.sh 和 organize.yml。
```

```
fix(organize): 修复 wheel 文件名解析错误

wheel 文件名格式为 <name>-<ver>-<py>-<abi>-<plat>[-<build>].whl，
之前用 5 段 split 会漏掉 build_tag，改为 >= 5 段。
```

```
docs(readme): 重写仓库规范和整理系统文档
```

---

## 提交方式

### 方式 1：直接 push 到 main（推荐）

```bash
git clone https://github.com/XION-HN/haisa-des-repo.git
cd haisa-des-repo
# 修改 scripts/ 或 .github/workflows/
git add -A
git commit -m "feat(organize): 支持并行扫描"
git push origin main
```

### 方式 2：Pull Request

 Fork → 修改 → PR → Review → Merge

### 方式 3：触发 organize workflow（手动整理）

在 GitHub Actions 页面：
1. 访问 https://github.com/XION-HN/haisa-des-repo/actions/workflows/organize.yml
2. 点击 "Run workflow"
3. 选择参数：
   - `sign_release`：是否 GPG 签名（默认 false）
   - `keep_old_gh_pages`：是否保留 gh-pages 现有文件（默认 false）
4. 点击 "Run workflow"

### 方式 4：bootstrap 仓库发版（自动触发）

在 [haisa-des-bootstrap](https://github.com/XION-HN/haisa-des-bootstrap) 仓库打 tag：

```bash
cd haisa-des-bootstrap
git tag v0.5.0
git push origin v0.5.0
```

bootstrap CI 会自动：
1. 编译所有包
2. 按首字母上传到本仓库的 26 个 release
3. 调用 `repository_dispatch` 触发本仓库的 organize workflow

---

## 资产清单

### Release 资产（GitHub Releases）

26 个 release（`pip-a` ~ `pip-z`）包含：

| 类型 | 说明 | 上传方 |
|---|---|---|
| `*.whl` | Python wheel 文件 | bootstrap CI |
| `*.deb` | Debian 包 | bootstrap CI |
| `bootstrap-arm64-v8a.zip` | 完整 bootstrap（Python + 原生包） | bootstrap CI |
| `packages.json` | 包索引（App 端 PM 老接口兼容） | bootstrap CI |
| `bootstrap-version.json` | bootstrap 版本信息（App OTA） | bootstrap CI |
| `wheels-index.json` | wheel 索引（App 端 PM 老接口兼容） | bootstrap CI |

### gh-pages 索引

| 路径 | 说明 |
|---|---|
| `apt-repo/dists/stable/Release` | apt 仓库元数据 |
| `apt-repo/dists/stable/main/binary-aarch64/Packages` | apt 包索引 |
| `pip-repo/simple/index.html` | PEP 503 顶层索引 |
| `pip-repo/simple/<首字母>/<包名>/index.html` | 单个包的所有 wheel 链接 |

---

## 下载与使用

### apt（设备端）

```bash
# sources.list 配置（App 端自动配置）
echo "deb [trusted=yes] https://xion-hn.github.io/haisa-des-repo/apt-repo stable main" \
  > $PREFIX/etc/apt/sources.list

apt update
apt install python
```

### pip（设备端）

```bash
pip install --index-url https://xion-hn.github.io/haisa-des-repo/pip-repo/simple/ numpy
```

### 直接下载（latest 别名）

```
https://github.com/XION-HN/haisa-des-repo/releases/download/pip-b/bootstrap-arm64-v8a.zip
https://github.com/XION-HN/haisa-des-repo/releases/download/pip-p/packages.json
https://github.com/XION-HN/haisa-des-repo/releases/download/pip-b/bootstrap-version.json
```

### 在线浏览

- apt 仓库元数据：https://xion-hn.github.io/haisa-des-repo/apt-repo/dists/stable/Release
- pip 顶层索引：https://xion-hn.github.io/haisa-des-repo/pip-repo/simple/
- numpy 包索引：https://xion-hn.github.io/haisa-des-repo/pip-repo/simple/n/numpy/

---

## 相关仓库

| 仓库 | 职责 |
|---|---|
| [haisa-des](https://github.com/XION-HN/haisa-des) | Android App 源码（包管理器 UI、运行时） |
| [haisa-des-bootstrap](https://github.com/XION-HN/haisa-des-bootstrap) | 构建系统（编译 apt/dpkg/Python/wheel，CI 发版） |
| **haisa-des-repo**（本仓库） | 发布仓库（Releases + gh-pages 索引） |

### 数据流

```
haisa-des-bootstrap (CI 编译)
  → haisa-des-repo (Releases 资产 + gh-pages 索引)
  → haisa-des (App 下载 bootstrap + apt/pip 安装包)
```

---

## 合规

- `LICENSES/NOTICE.md`：项目通知
- `LICENSES/termux-app-LICENSE.md`：Termux 补丁引用许可证（仅引用 patch 文件，不提交 Termux 编译脚本和产物）
