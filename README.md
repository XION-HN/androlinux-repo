# AndroLinux（工作名称）

在 Android 上运行原生 Linux 工具链 —— **内部技术验证 demo**。

采用 Termux 式 Bionic 交叉编译路线（非 proot/虚拟机），闭源商业合规架构。
设计文档：[`docs/superpowers/specs/2026-07-23-demo-tech-validation-design.md`](docs/superpowers/specs/2026-07-23-demo-tech-validation-design.md)

## 仓库结构

| 目录 | 说明 |
|---|---|
| `build-system/` | 交叉编译系统（NDK r29，7 个包，产出 bootstrap zip） |
| `app/` | Android App（Java，minSdk=28 / **targetSdk=28** / compileSdk=36） |
| `terminal-view/`、`terminal-emulator/` | 终端渲染/PTY 模块（vendored Apache 2.0，源自 termux-app） |
| `.github/workflows/ci.yml` | CI：bootstrap（prod/test 双变体）→ APK |
| `docs/` | 设计文档 + 设备测试清单 |

## 构建（全部在 CI 完成）

- **bootstrap**：`.github/workflows/ci.yml` 的 `bootstrap` job
  （`sdkmanager "ndk;29.0.14206865"` → `build-system/build.sh build all` → `make-bootstrap.sh`）
- **APK**：`apk` job 注入 `bootstrap-arm64-v8a.zip` 资产后 `assembleDebug`
- 产物在 Actions 页面的 Artifacts：`bootstrap-prod` / `bootstrap-test` / `androlinux-apk`

本地手动构建 bootstrap（x86_64 Linux 主机，需 NDK r29）：

```bash
export ANDROID_NDK_HOME=/path/to/android-sdk/ndk/29.0.14206865
cd build-system
./build.sh build all      # 构建 7 个包
./make-bootstrap.sh       # 产出 dist/bootstrap-arm64-v8a.zip
```

## 关键设计（为什么是 targetSdk=28）

Android 10（API 29）起 SELinux 禁止 targetSdk≥29 的应用从可写私有目录 exec 二进制文件（W^X）。
本项目的包管理本质依赖该能力，因此与 Termux 一样锁定 `targetSdkVersion=28`，
代价是无法上架 Google Play / 主流商店，仅侧载分发。详见设计文档。

## 合规

- `terminal-view` / `terminal-emulator`：Apache License 2.0（vendored 自 termux-app @ `3df69d1`），许可证文本保留于各模块内及 `LICENSES/`
- bootstrap 内的 bash/openssl/toybox 等二进制按各自上游许可证分发；对应源码即 `build-system/packages/*/build.sh` 中 `PKG_SRC_URL` 指向的上游 tarball
- 本项目不使用 "Termux" 名称与标识

## 下一步（demo 之后）

见设计文档第 5 节：设备矩阵验证（5 台设备 checklist）→ Go/No-Go → M2（包管理器与软件中心）。
