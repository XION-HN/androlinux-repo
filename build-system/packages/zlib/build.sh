# zlib —— 底层压缩库（curl 依赖链第一层）
PKG_NAME="zlib"
PKG_VERSION="1.3.1"
PKG_SRC_URL="https://zlib.net/fossils/zlib-1.3.1.tar.gz"
PKG_SRC_SHA256="9a93b2b7dfdac77ceba5a558a580e74667dd6fede4585b91eefb60f03b72df23"
PKG_SRC_DIR="zlib-1.3.1"

pkg_build() {
    # lld ≥16 默认 --no-undefined-version：zlib configure 的共享库探测链接只有
    # 单个测试 .o，version script 引用的符号尚未定义 → 误判“无共享支持”只产静态库。
    # 注意：该探测命令只用 CFLAGS 不用 LDFLAGS，所以必须加进 CFLAGS。
    export CFLAGS="$CFLAGS -Wl,--undefined-version"
    # zlib 的 configure 非 autoconf，不支持 --host，直接读 CC/CFLAGS 环境
    ./configure --prefix="$PREFIX" --shared
    make -j"$JOBS"
    stage_install
}
