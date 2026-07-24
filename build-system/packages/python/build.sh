# python —— CPython 3.13 解释器 + pip（动态交叉编译到 aarch64-linux-android）
PKG_NAME="python"
PKG_VERSION="3.13.14"
PKG_SRC_URL="https://www.python.org/ftp/python/3.13.14/Python-3.13.14.tar.xz"
PKG_SRC_SHA256="639e43243c620a308f968213df9e00f2f8f62332f7adbaa7a7eeb9783057c690"
PKG_SRC_DIR="Python-3.13.14"

pkg_build() {
    local srcdir="$(pwd)"

    # ---- 补丁（sed，幂等）----
    # Android 无 multiarch 目录布局，清空避免 sysconfig 路径错误
    sed -i 's/^MULTIARCH=.*$/MULTIARCH=/' configure.ac configure 2>/dev/null || true

    # ---- 1. 构建宿主 Python（native x86_64，供 --with-build-python 用）----
    # CPython 3.11+ 交叉编译要求 --with-build-python 指向同版本的 native python；
    # 用 out-of-tree build 在 build-host/ 子目录里只构建解释器二进制（make python
    # 不含扩展模块，不依赖宿主的 libssl-dev / libbz2-dev 等开发头文件）。
    local host_build="$srcdir/build-host"
    rm -rf "$host_build"; mkdir -p "$host_build"
    ( cd "$host_build" && ../configure --without-ensurepip --without-pymalloc \
        && make -j"$JOBS" python )
    local host_python="$host_build/python"
    [ -x "$host_python" ] || die "宿主 Python 构建失败"

    # ---- 2. 交叉配置 ----
    export CPPFLAGS="-I$STAGE_DIR$PREFIX/include -I$STAGE_DIR$PREFIX/include/ncursesw"
    export LDFLAGS="$LDFLAGS -L$STAGE_DIR$PREFIX/lib"

    local cross_build="$srcdir/build-cross"
    rm -rf "$cross_build"; mkdir -p "$cross_build"
    ( cd "$cross_build" && \
        CONFIG_SITE="$BS_ROOT/packages/python/config.site" \
        ../configure \
            --build="$(sh "$srcdir/config.guess" 2>/dev/null || echo x86_64-pc-linux-gnu)" \
            --host="$TARGET_TRIPLE" \
            --with-build-python="$host_python" \
            --prefix="$PREFIX" \
            --enable-shared \
            --with-system-ffi \
            --with-system-expat \
            --without-ensurepip \
            --with-openssl="$STAGE_DIR$PREFIX" \
            --enable-loadable-sqlite-extensions )

    # ---- 3. 交叉编译 ----
    ( cd "$cross_build" && make -j"$JOBS" )

    # ---- 4. 安装到 staging ----
    # make install 末尾的 compileall 会尝试运行目标 python（aarch64）生成 .pyc，
    # 在 x86_64 宿主上无法执行；.py 文件在此步之前已全部安装，.pyc 可在设备首跑时生成。
    ( cd "$cross_build" && make install DESTDIR="$PKG_STAGE" ) || {
        warn "make install 部分步骤失败（可能是 compileall 交叉运行），检查核心产物..."
        [ -x "$PKG_STAGE$PREFIX/bin/python3.13" ] || die "python3.13 二进制未安装"
        [ -d "$PKG_STAGE$PREFIX/lib/python3.13" ] || die "stdlib 未安装"
    }

    # ---- 5. 手动安装 pip（交叉编译不能用 ensurepip）----
    # CPython 源码树 Lib/ensurepip/_bundled/ 内含 pip wheel，直接解压到 site-packages
    local pyver="python${PKG_VERSION%.*}"   # python3.13
    local pydir="$PKG_STAGE$PREFIX/lib/$pyver"
    mkdir -p "$pydir/site-packages"
    local wheel
    wheel=$(ls "$srcdir/Lib/ensurepip/_bundled/pip-"*.whl 2>/dev/null | head -1)
    [ -n "$wheel" ] || die "未找到 pip wheel"
    "$host_python" -m zipfile -e "$wheel" "$pydir/site-packages/"

    # pip 入口脚本（shebang 指向目标设备上的 python3.13）
    local pip_bin="$PKG_STAGE$PREFIX/bin"
    local pip_name="pip${PKG_VERSION#3.}"   # pip3.13
    cat > "$pip_bin/$pip_name" << PIP_EOF
#!$PREFIX/bin/$pyver
import sys
from pip._internal.cli.main import main
if __name__ == '__main__':
    sys.exit(main())
PIP_EOF
    chmod +x "$pip_bin/$pip_name"
    ln -sf "$pip_name" "$pip_bin/pip3"
    ln -sf "$pip_name" "$pip_bin/pip"
}
