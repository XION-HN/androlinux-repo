# NDK r29 工具链（CI / x86_64 Linux 主机，权威构建路径）
# 需要环境变量 ANDROID_NDK_HOME（或 ANDROID_NDK / ANDROID_NDK_ROOT 之一）

_ndk="${ANDROID_NDK_HOME:-${ANDROID_NDK:-$ANDROID_NDK_ROOT}}"
if [ -z "$_ndk" ] || [ ! -d "$_ndk/toolchains/llvm/prebuilt" ]; then
    die "未找到 NDK。请设置 ANDROID_NDK_HOME（需要 ndk;$NDK_VERSION）"
fi
HOST_PREBUILT="$_ndk/toolchains/llvm/prebuilt/linux-x86_64"
[ -d "$HOST_PREBUILT" ] || die "仅支持 linux-x86_64 主机 NDK（当前: $HOST_PREBUILT 不存在）"
export PATH="$HOST_PREBUILT/bin:$PATH"

export CC="$TARGET_TRIPLE$API_LEVEL-clang"
export CXX="$TARGET_TRIPLE$API_LEVEL-clang++"
export AR="llvm-ar"
export RANLIB="llvm-ranlib"
export STRIP="llvm-strip"
export READELF="llvm-readelf"
export CFLAGS="$COMMON_CFLAGS"
export CXXFLAGS="$COMMON_CFLAGS"
export LDFLAGS="$COMMON_LDFLAGS"
export PKG_CONFIG_PATH="$STAGE_DIR$PREFIX/lib/pkgconfig"

# openssl 的 android-arm64 target 依赖此变量推导工具链
export ANDROID_NDK_HOME="$_ndk"
export OPENSSL_TARGET="android-arm64"

# NDK r29 已移除 GCC 包装器；OpenSSL 等构建系统的 android-* 目标仍会探测
# aarch64-linux-android-gcc → 创建兼容 symlink 指向 NDK clang。
ln -sf "$CC" "$HOST_PREBUILT/bin/aarch64-linux-android-gcc"
ln -sf "$CXX" "$HOST_PREBUILT/bin/aarch64-linux-android-g++"

log "工具链: NDK ($(basename "$_ndk")) @ $HOST_PREBUILT"
$CC --version | head -1
