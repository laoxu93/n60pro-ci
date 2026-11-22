#!/usr/bin/env bash
# ============================================================
# 在 openwrt 源码根目录执行。必须在 feeds update/install 之后、
# make defconfig 之前。
#
# 作用：修掉 rust [host] 构建失败。
#
# 为什么需要这一步（run 44922715193 实锤）：
#   feeds/packages/lang/rust 是 HOST 包，编译它要跑 rustc 的
#   x.py bootstrap。bootstrap 默认 download-ci-llvm=true，会去
#   拉 rust 官方 CI 预编译的 LLVM 产物。
#   Rust 官方只保留最近几个版本的 CI LLVM，旧版本会被定期清理；
#   immortalwrt/packages 的 openwrt-25.12 分支还锁在 rust 1.96.0，
#   那个版本的 CI LLVM 已经被删档，于是 bootstrap 拉不到东西：
#
#     Bootstrap failed while executing `--ci false --build-dir .../rustc-1.96.0-src/build dist build-manifest rustc rust-std cargo`
#     make[3]: *** [Makefile:111: .../host/rustc-1.96.0-src/.built] Error 1
#     ERROR: package/feeds/packages/rust [host] failed to build.
#
#   上游 openwrt/packages 已经修了同一件事（master 分支）：
#     - PKG_VERSION: 1.96.0 -> 1.96.1（换到还在的版本）
#     - --set=llvm.download-ci-llvm=true  ->  false
#       （不用 CI 预编译 LLVM，改为自己编。代价是编译变慢，
#         但省掉了对已删档产物的依赖，不会再随机挂。）
#
# 为什么在这里打补丁而不改 feeds.conf：
#   feeds 来自 immortalwrt/packages 的 openwrt-25.12 分支，那是
#   别人仓库，改了下一次 feeds update 就被覆盖。这里改的是
#   已经拉到本地的源码副本，每次构建都会重新 clone+update，
#   补丁跟着走，幂等且不会丢。
#
# 已核对：上游 openwrt/packages master 的 lang/rust/Makefile 就是
# 下面这两个值。本脚本按"值"改而不是按"行号"改，上游再改版本也认。
# ============================================================
set -euo pipefail

log() { printf '%s\n' "$*" >&2; }

RUST_MK="feeds/packages/lang/rust/Makefile"

if [ ! -f "$RUST_MK" ]; then
  log "::warning::没找到 $RUST_MK，跳过 rust 修补"
  exit 0
fi

# ---- 1. download-ci-llvm: true -> false ----
if grep -q -- '--set=llvm.download-ci-llvm=true' "$RUST_MK"; then
  sed -i 's|--set=llvm\.download-ci-llvm=true|--set=llvm.download-ci-llvm=false|' "$RUST_MK"
  log "rust: download-ci-llvm true -> false"
elif grep -q -- '--set=llvm.download-ci-llvm=false' "$RUST_MK"; then
  log "rust: download-ci-llvm 已是 false，无需改动"
else
  log "::warning::$RUST_MK 里没有 download-ci-llvm 配置行，跳过该项"
fi

# ---- 2. rust 版本：1.96.0 -> 1.96.1 ----
# 版本和哈希必须一起改，只改版本会导致 PKG_HASH 校验失败。
if grep -q '^PKG_VERSION:=1\.96\.0$' "$RUST_MK"; then
  sed -i \
    -e 's|^PKG_VERSION:=1\.96\.0$|PKG_VERSION:=1.96.1|' \
    -e 's|^PKG_HASH:=b99ce16cdf0ecfc761b585ac84d131b46733465a02f8ecd0ff2de9713c62ee09$|PKG_HASH:=77a6ff3003a4ad0cb00697b043c879e3e1a15d945b1a1f63818903bfc3fa8b98|' \
    "$RUST_MK"
  log "rust: 1.96.0 -> 1.96.1（哈希同步更新）"
elif grep -q '^PKG_VERSION:=1\.96\.1$' "$RUST_MK"; then
  log "rust: 已是 1.96.1，无需改动"
else
  log "::warning::rust 版本不是 1.96.0/1.96.1，当前：$(grep -m1 '^PKG_VERSION:=' "$RUST_MK" || echo '未知')"
fi

# ---- 3. 校验结果 ----
echo "----- 修补后的 rust 配置 -----"
grep -E '^PKG_VERSION:=|^PKG_HASH:=|download-ci-llvm' "$RUST_MK" || true

if grep -q -- '--set=llvm.download-ci-llvm=true' "$RUST_MK"; then
  log "::error::download-ci-llvm 仍是 true，rust host 编译会再次失败"
  exit 1
fi

log "rust 修补完成"
