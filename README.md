# haisa-des-repo

HaisaDes 项目的公开发布仓库，托管 GitHub Releases 资产。

## 仓库职责

此仓库不存放源码，仅作为 Releases 资产托管点。资产由 `XION-HN/haisa-des-bootstrap` 仓库的 CI 在 tag 触发时自动上传。

## Releases 资产

每次 `haisa-des-bootstrap` 仓库打 tag（如 `v0.2.0`），CI 会自动上传以下资产到本仓库 Releases：

| 资产 | 用途 | 消费方 |
|---|---|---|
| `bootstrap-arm64-v8a.zip` | 完整 bootstrap（Python 3.13 + pip + 14 个原生包） | haisa-des 软件 CI（注入 APK assets） |
| `packages.json` | 包索引 | App 端 PackageManager |
| `bootstrap-version.json` | bootstrap 版本信息 | App 端 BootstrapUpdater（OTA 升级） |
| `packages/*.tar.gz` | 单独包归档 | App 端按需安装 |

## 下载路径（latest 自动跟随最新 release）

```
https://github.com/XION-HN/haisa-des-repo/releases/latest/download/bootstrap-arm64-v8a.zip
https://github.com/XION-HN/haisa-des-repo/releases/latest/download/packages.json
https://github.com/XION-HN/haisa-des-repo/releases/latest/download/bootstrap-version.json
```

## 相关仓库

- [`XION-HN/haisa-des`](https://github.com/XION-HN/haisa-des) —— Android Java 源码（私有）
- [`XION-HN/haisa-des-bootstrap`](https://github.com/XION-HN/haisa-des-bootstrap) —— bootstrap 源码 + 构建 CI（私有，本仓库 Releases 的资产来源）

## 合规

bootstrap 内的 bash/openssl/toybox 等二进制按各自上游许可证分发；对应源码与构建配方在 `haisa-des-bootstrap` 仓库的 `build-system/packages/<name>/build.sh`。许可证详情见该仓库 `LICENSES/NOTICE.md`。

本仓库 `LICENSES/` 保留 terminal-view / terminal-emulator 的 Apache 2.0 许可证文本（这些组件源码在 haisa-des 仓库）。
