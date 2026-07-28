# haisa-des-repo

HaisaDes 项目的**公开发布仓库**，托管 GitHub Releases 资产与 apt / pip 仓库索引（通过 gh-pages 分支提供）。

> 本仓库不存放源码。所有构建配方和 CI 在 [`XION-HN/haisa-des-bootstrap`](https://github.com/XION-HN/haisa-des-bootstrap) 仓库；Android App 源码在 [`XION-HN/haisa-des`](https://github.com/XION-HN/haisa-des) 仓库。

---

## 目录

- [仓库职责](#仓库职责)
- [目录结构](#目录结构)
- [仓库规范](#仓库规范)
- [提交规范](#提交规范)
- [提交方式](#提交方式)
- [CI 工作流](#ci-工作流)
- [资产清单](#资产清单)
- [下载与使用](#下载与使用)
- [相关仓库](#相关仓库)
- [合规](#合规)

---

## 仓库职责

| 职责 | 实现位置 |
|---|---|
| 托管 GitHub Releases 资产 | `Releases`（由 bootstrap CI 自动上传） |
| 托管 Debian apt 仓库元数据 | `gh-pages` 分支 `apt-repo/` |
| 托管 PEP 503 pip 索引 | `gh-pages` 分支 `pip-repo/` |
| 提供整理脚本 | `scripts/organize-repo.sh` |
| 提供 CI 工作流 | `.github/workflows/organize.yml` |

资产**不直接提交到 main 分支**。`.deb` / `.whl` / `bootstrap.zip` 等二进制资产由 `haisa-des-bootstrap` 仓库的 CI 在 tag 触发时上传到 Releases；gh-pages 分支仅存放**索引文件**（HTML / Packages / Release），索引中的 href 指向 Releases 绝对 URL。

---

## 目录结构

```
haisa-des-repo/
├── .github/
│   └── workflows/
│       └── organize.yml          # 手动触发的整理 workflow
├── scripts/
│   └── organize-repo.sh          # 扫描 Releases 资产，生成索引部署到 gh-pages
├── LICENSES/
│   ├── NOTICE.md                  # 第三方组件与许可证声明
│   └── termux-app-LICENSE.md     # terminal-view / terminal-emulator 的 Apache 2.0
├── README.md                      # 本文件
└── (无源码)
```

**gh-pages 分支**（由 CI 自动生成，请勿手动修改）：

```
gh-pages/
├── README.md                      # 自动生成
├── apt-repo/                      # Debian 仓库
│   ├── dists/stable/
│   │   ├── Release                # 仓库元数据（+ InRelease / Release.gpg 如已签名）
│   │   └── main/binary-aarch64/
│   │       ├── Packages           # 包索引（Filename 字段用 Releases 绝对 URL）
│   │       └── Packages.gz
│   └── pool/main/<首字母>/<包名>/ # （index-only 模式下为空，仅占位）
└── pip-repo/                      # PEP 503 Simple Index
    └── simple/
        ├── index.html             # 顶层索引（列出所有包名）
        └── <首字母>/<规范化包名>/
            └── index.html         # 该包所有 wheel 下载链接（href 指向 Releases）
```

### 首字母布局规则

**apt pool（Debian 标准）：**
- 包名以 `lib` 开头：取前 4 字符（如 `liblz4` → `libl`，`libgnutls` → `libg`）
- 其他包：取首字母（小写）

**pip simple（PEP 503）：**
- 取规范化包名首字母（小写），不区分 `lib*`
- 规范化（PEP 503）：大写转小写，连续的 `-` `_` `.` 替换为单个 `-`

---

## 仓库规范

### 允许直接修改的内容

| 路径 | 说明 |
|---|---|
| `README.md` | 本文件 |
| `LICENSES/` | 许可证文本（与 bootstrap 仓库保持一致） |
| `.github/workflows/organize.yml` | 整理 workflow 定义 |
| `scripts/organize-repo.sh` | 整理脚本 |

### 禁止直接修改的内容

| 路径 | 原因 |
|---|---|
| `gh-pages` 分支 | 由 CI 自动生成，手动修改会被下次整理覆盖 |
| Releases 资产 | 由 `haisa-des-bootstrap` CI 在 tag 触发时上传，不可在本仓库直接增删 |
| `bootstrap-arm64-v8a.zip` 等 | 二进制产物，源码在 bootstrap 仓库 |

### Release 命名规范

- **Tag 命名**：`v<主>.<次>.<修>[-<预发布>]`，如 `v0.4.0`、`v1.0.0-rc1`
- **Tag 来源**：仅由 `haisa-des-bootstrap` 仓库打 tag 触发；本仓库**不主动打 tag**
- **资产命名**：
  - `bootstrap-arm64-v8a.zip`（固定名，同名覆盖以便重试）
  - `packages.json` / `bootstrap-version.json` / `wheels-index.json`（固定名）
  - `packages/<name>_<version>_aarch64.deb`（Debian 标准）
  - `wheels/<name>-<version>-<py>-<abi>-<platform>.whl`（PEP 427）

### 仓库设置要求

- **默认分支**：`main`
- **GitHub Pages**：源 = `Deploy from a branch`，分支 = `gh-pages`，路径 = `/ (root)`
- **Actions 权限**：`Allow all actions`
- **Workflow 权限**：`Read and write permissions`（organize workflow 需 push gh-pages）

---

## 提交规范

采用 **[Conventional Commits](https://www.conventionalcommits.org/)** 规范。

### 格式

```
<type>(<scope>): <subject>

<body>

<footer>
```

### 类型（type）

| type | 用途 | 示例 |
|---|---|---|
| `feat` | 新功能 | `feat(organize): 支持整理所有历史 release` |
| `fix` | 修复 bug | `fix(organize): 修复 SIGPIPE 导致 set -e 退出` |
| `ci` | CI 配置变更 | `ci(organize): 新增 only_latest 输入参数` |
| `docs` | 文档变更 | `docs: 更新 README 仓库规范` |
| `refactor` | 重构（无行为变化） | `refactor: 简化为纯 Releases 托管仓库` |
| `chore` | 杂项（构建、依赖等） | `chore(gh-pages): 部署 apt-repo + pip-repo` |
| `revert` | 回滚 | `revert: 撤销 xxx 提交` |

### 范围（scope）

可选，常用 scope：

- `organize` —— 整理脚本与 workflow
- `gh-pages` —— gh-pages 分支部署
- `apt` / `pip` —— 仓库类型相关
- `license` —— 许可证相关

### Subject 规则

- 使用祈使句、现在时：`新增` 而非 `新增了`
- 首字母不大写（中文无此问题）
- 结尾不加句号
- 一行不超过 72 字符

### Body 规则

- 解释 **为什么**（why），而非 **做什么**（what）——后者代码已说明
- 每行不超过 72 字符
- 空行分隔段落

### Footer

- 用于 **BREAKING CHANGE** 标注和 **Closes #issue** 引用
- 示例：
  ```
  BREAKING CHANGE: organize workflow 改为 index-only，不再下载文件本体
  Closes #12
  ```

### 完整示例

```
ci(organize): 支持 only_latest 输入参数，可整理所有历史 release

新增 workflow_dispatch 输入 only_latest（默认 true）：
- true=仅整理最新 release（旧行为）
- false=整理所有 release（含历史 v0.1.x/v0.2.x/v0.3.x）

将该参数透传给 organize-repo.sh 的 ONLY_LATEST 环境变量，
便于一次性归档所有历史 release 的 .deb/.whl 资产到 gh-pages 索引。
```

---

## 提交方式

### 方式一：直接 push 到 main（仓库 owner / 协作者）

适用于本仓库的脚本、workflow、README 等少量源文件修改。

```bash
git clone https://github.com/XION-HN/haisa-des-repo.git
cd haisa-des-repo

# 修改文件
$EDITOR scripts/organize-repo.sh

# 提交（遵循 Conventional Commits）
git add scripts/organize-repo.sh
git commit -m "fix(organize): 修复 <具体问题>

<解释 why>"

git push origin main
```

### 方式二：Pull Request（外部贡献者）

fork → 新建分支 → PR。

```bash
# fork 后 clone 你的 fork
git clone https://github.com/<你的用户名>/haisa-des-repo.git
cd haisa-des-repo
git remote add upstream https://github.com/XION-HN/haisa-des-repo.git

# 新建分支（分支名用 kebab-case，体现 type）
git checkout -b fix/organize-sigpipe

# 修改 + 提交（遵循 Conventional Commits）
git add scripts/organize-repo.sh
git commit -m "fix(organize): 修复 SIGPIPE 触发 set -e 退出"

git push origin fix/organize-sigpipe
# 在 GitHub 界面发起 PR，base = XION-HN/haisa-des-repo:main
```

**PR 标题** 即 commit message 的首行（`fix(organize): 修复 SIGPIPE 触发 set -e 退出`）。

### 方式三：触发整理 workflow（不修改源码）

只整理 Releases 资产到 gh-pages，不修改任何源文件。

**GitHub 界面操作：**
1. 访问 https://github.com/XION-HN/haisa-des-repo/actions/workflows/organize.yml
2. 点击 **Run workflow**
3. 选择参数：

| 参数 | 含义 | 默认 |
|---|---|---|
| `only_latest` | `true`=仅最新 release；`false`=所有历史 release | `true` |
| `sign_release` | 是否对 apt Release 做 GPG 签名（需配置 Secret `HAISADES_GPG_PRIVATE_KEY`） | `false` |
| `keep_old_gh_pages` | 是否保留 gh-pages 现有非 apt-repo/pip-repo 文件 | `false` |

4. 点击绿色 **Run workflow**

**CLI 触发（需 admin 权限）：**

```bash
gh workflow run organize-repo \
  -R XION-HN/haisa-des-repo \
  -f only_latest=false \
  -f sign_release=false \
  -f keep_old_gh_pages=false

# 查看运行状态
gh run list --workflow=organize-repo -R XION-HN/haisa-des-repo --limit 3
```

### 方式四：发布新 Release（bootstrap 仓库触发）

**本仓库不主动发版**。新 Release 由 `haisa-des-bootstrap` 仓库打 tag 自动触发：

```bash
# 在 haisa-des-bootstrap 仓库
git tag v0.5.0
git push origin v0.5.0
# → bootstrap CI 构建 → 上传资产到本仓库 Releases
# → bootstrap CI 部署 apt-repo/pip-repo 到本仓库 gh-pages
```

如需重新整理已有 Release（不重新构建），使用 **方式三**。

---

## CI 工作流

### `organize.yml`

手动触发（`workflow_dispatch`）的整理脚本。

| 步骤 | 说明 |
|---|---|
| Checkout | 拉取 main 分支 |
| Install deps | `gnupg python3 git curl jq` |
| Run organize-repo.sh | 扫描 Releases 资产，生成 `dist/apt-repo/` + `dist/pip-repo/` |
| Sign Release（可选） | 用 `HAISADES_GPG_PRIVATE_KEY` 签名 Release 生成 InRelease + Release.gpg |
| Upload report | `dist/organize-report.json` 作为 artifact（30 天保留） |
| Deploy to gh-pages | 清空 gh-pages（除 `.git`）→ 拷新索引 → commit → push |

**权限要求**：
- `contents: write`（push gh-pages）
- `actions: read`（读 release 列表）

### `pages-build-deployment`

GitHub 官方 workflow，gh-pages 分支 push 后自动触发，构建静态站点部署到 `https://xion-hn.github.io/haisa-des-repo/`。

---

## 资产清单

### Release 资产（每次发版由 bootstrap CI 上传）

| 资产 | 用途 | 消费方 |
|---|---|---|
| `bootstrap-arm64-v8a.zip` | 完整 bootstrap（Python 3.13 + pip + 原生包） | haisa-des 软件 CI（注入 APK assets） |
| `packages.json` | 包索引（旧接口兼容） | App 端 PackageManager |
| `bootstrap-version.json` | bootstrap 版本信息 | App 端 BootstrapUpdater（OTA 升级） |
| `wheels-index.json` | wheel 索引（旧接口兼容） | App 端 pip wrapper |
| `packages/*.deb` | 单独 Debian 包归档 | apt 仓库 / 按需安装 |
| `wheels/*.whl` | wheel 文件 | pip 仓库 / 按需安装 |

### gh-pages 部署的索引

| URL | 用途 |
|---|---|
| `https://xion-hn.github.io/haisa-des-repo/apt-repo/dists/stable/Release` | apt 仓库元数据 |
| `https://xion-hn.github.io/haisa-des-repo/apt-repo/dists/stable/main/binary-aarch64/Packages` | apt 包索引 |
| `https://xion-hn.github.io/haisa-des-repo/pip-repo/simple/` | PEP 503 顶层索引 |
| `https://xion-hn.github.io/haisa-des-repo/pip-repo/simple/<首字母>/<包名>/` | 单包 wheel 索引 |

---

## 下载与使用

### latest 自动跟随最新 release

```
https://github.com/XION-HN/haisa-des-repo/releases/latest/download/bootstrap-arm64-v8a.zip
https://github.com/XION-HN/haisa-des-repo/releases/latest/download/packages.json
https://github.com/XION-HN/haisa-des-repo/releases/latest/download/bootstrap-version.json
https://github.com/XION-HN/haisa-des-repo/releases/latest/download/wheels-index.json
```

### 设备端 apt 使用

设备端 `sources.list` 配置（已由 bootstrap 自动配置）：

```
deb [trusted=yes] https://xion-hn.github.io/haisa-des-repo/apt-repo stable main
```

```bash
apt update
apt install <package>
```

### 设备端 pip 使用

```bash
pip install --index-url https://xion-hn.github.io/haisa-des-repo/pip-repo/simple/ <package>
```

---

## 相关仓库

- [`XION-HN/haisa-des`](https://github.com/XION-HN/haisa-des) —— Android Java 源码（App 主仓库，拉取 bootstrap 注入 APK）
- [`XION-HN/haisa-des-bootstrap`](https://github.com/XION-HN/haisa-des-bootstrap) —— bootstrap 源码 + 构建 CI（本仓库 Releases 资产的来源）

---

## 合规

bootstrap 内的 bash/openssl/toybox 等二进制按各自上游许可证分发；对应源码与构建配方在 `haisa-des-bootstrap` 仓库的 `build-system/packages/<name>/build.sh`。许可证详情见 [`LICENSES/NOTICE.md`](LICENSES/NOTICE.md)。

本仓库 `LICENSES/` 保留 terminal-view / terminal-emulator 的 Apache 2.0 许可证文本（这些组件源码在 haisa-des 仓库）。
