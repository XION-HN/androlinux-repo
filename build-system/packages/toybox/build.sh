# toybox —— 基础命令集（0BSD 许可证，商业友好；安装产生大量符号链接，顺带验证 SYMLINKS 机制）
PKG_NAME="toybox"
PKG_VERSION="0.8.12"
PKG_SRC_URL="https://codeload.github.com/landley/toybox/tar.gz/refs/tags/0.8.12"
PKG_SRC_SHA256="3c529d93923dde67d048e7bcbd5d1bc0dd1ad09362269e2415f5f2eaab349b5b"
PKG_SRC_DIR="toybox-0.8.12"

pkg_build() {
    # toybox 是 Android 原生工具集，NDK 交叉编译基本零适配
    # 注：defconfig 在 proot 环境下偶发瞬时失败（proot 已知怪癖），重试一次兜底
    make defconfig || { sleep 1; make defconfig; }
    # bionic 无 libcrypt，且 App 沙箱内这些命令无意义（与 Android 官方 toybox 配置一致）；
    # ICONV: demo 不需要，且本机冒烟时会被 Termux 环境的 libiconv 探测污染
    for opt in SU LOGIN PASSWD ICONV; do
        sed -i "s/^CONFIG_${opt}=y/# CONFIG_${opt} is not set/" .config
    done
    make -j"$JOBS" CC="$CC" STRIP="$STRIP"
    # install 目标会在 $PREFIX/bin 下创建 toybox 及各命令符号链接
    make install PREFIX="$PKG_STAGE$PREFIX"
}
