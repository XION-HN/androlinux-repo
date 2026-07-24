# readline —— 行编辑库（Python readline 模块依赖，交互式 REPL 行编辑）
PKG_NAME="readline"
PKG_VERSION="8.2"
PKG_SRC_URL="https://ftp.gnu.org/gnu/readline/readline-8.2.tar.gz"
PKG_SRC_SHA256="3feb7171f16a84ee82ca18a36d7b9be109a52c04f492a053331d7d1095007c35"
PKG_SRC_DIR="readline-8.2"

pkg_build() {
    # 依赖 ncurses（已在总 staging 中）：头文件 include/ncursesw，库 libncursesw + libncurses.so 兼容链接
    export CPPFLAGS="-I$STAGE_DIR$PREFIX/include -I$STAGE_DIR$PREFIX/include/ncursesw"
    export LDFLAGS="$LDFLAGS -L$STAGE_DIR$PREFIX/lib"
    gnu_configure --with-curses
    make -j"$JOBS"
    stage_install
}
