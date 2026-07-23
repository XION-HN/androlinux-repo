# build-system —— AndroLinux 交叉编译系统

按 Buildroot 风格自研：每包一个 `packages/<name>/build.sh`（元数据 + `pkg_build()`），
公共函数在 `lib/common.sh`，工具链在 `toolchains/`。**不复制 termux-packages 的任何脚本/补丁（GPLv3 避让）**。

## 用法

```bash
export ANDROID_NDK_HOME=/path/to/ndk/29.0.14206865   # 权威工具链（CI 路径）
./build.sh list                 # 包清单与依赖
./build.sh build all            # 或指定包名: build bash curl
./make-bootstrap.sh             # 产出 dist/bootstrap-arm64-v8a.zip + dist/packages/*.tar.gz
./build.sh clean                # 清理
```

环境变量：`TOOLCHAIN=ndk|termux-local`（默认 ndk）、`VARIANT=prod|test`（默认 prod）、`JOBS=N`

- **prod**：`PREFIX=/data/data/com.androlinux.app/files/usr`（打进 APK）
- **test**：`PREFIX=/data/data/com.termux/files/home/al-test`（借 Termux 环境做真机冒烟，产物不可发布）
- **termux-local**：在 Android 设备上的 Termux 里用 clang 冒烟构建（仅验证用）

## 包格式约定

- 编译期 `--prefix=$PREFIX` + `-Wl,-rpath,$PREFIX/lib` 写死，运行期不依赖 `LD_LIBRARY_PATH`
- 全部链接显式 `-Wl,-z,max-page-size=16384`（16KB 页对齐合规）
- 单包 staging → 合并 staging → zip。符号链接无法入 zip：记录在 `SYMLINKS.txt`
  （每行 `link路径<TAB>目标`，相对 prefix 根），由 App 安装时重建
- 新包接入：复制现有包的 `build.sh`，改元数据与 configure 参数；依赖在 `build.sh` 的 `pkg_deps()` 登记

## 已知适配点（排障参考）

| 坑 | 处理 |
|---|---|
| lld ≥16 默认 `--no-undefined-version` → zlib 误判无共享库 | zlib 的 CFLAGS 追加 `-Wl,--undefined-version` |
| bionic 无 `libcrypt` | toybox 关闭 SU/LOGIN/PASSWD |
| API<28 缺 `getentropy` 等 | 全链路 API_LEVEL=28（demo 设备 Android 12+） |
| autoconf 交叉探测运行目标程序 | bash 用 `bash_cv_*` 缓存变量喂已知值 |
| openssl 目标选择 | NDK → `android-arm64`；termux-local → `linux-aarch64` |
