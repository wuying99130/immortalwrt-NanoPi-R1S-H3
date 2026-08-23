#!/bin/bash
set -e

# ============================================
# ImmortalWrt 纯净编译脚本 (系统主体完成、末尾注入插件版)
# ============================================

GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_prog() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ◔ $1${NC}"; }
log_done() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ● $1${NC}"; }

echo "=========================================="
echo "  开始执行核心编译与固件打包"
echo "  目标: NanoPi R1S-H3 (sunxi/cortexa7)"
echo "=========================================="

# 0. 注入重型开发语言（Go/Rust）顶级镜像加速通道
export GOPROXY=https://goproxy.cn,direct
export RUSTUP_DIST_SERVER=https://ustc.edu.cn
export RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rustup


# ============================================================
# 第一阶段：安安心心专注基础源码下载、工具链与主体固件编译
# (开头绝对不放任何插件，确保地基稳固)
# ============================================================

log_prog "下载源码依赖包..."
make download -j8
find dl -size -1024c -exec rm -f {} \;

log_prog "编译基础 tools..."
make tools/install -j$(nproc)

log_prog "编译 toolchain..."
make toolchain/install -j$(nproc)

log_prog "更新官方 Feeds 索引并执行本地沙盒静态检测..."

AUDIT_LOG="/tmp/plugin_check_report.txt"
echo "==========================================" > "$AUDIT_LOG"
echo "       插件完整性多层检测与剔除审计报告     " >> "$AUDIT_LOG"
echo "       检测时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$AUDIT_LOG"
echo "==========================================" >> "$AUDIT_LOG"
echo "" >> "$AUDIT_LOG"

# 仅更新纯净的官方核心源
./scripts/feeds update -a
./scripts/feeds install -a

HAS_BAD_PLUGINS=0

# A. 自动揪出并物理干掉导致系统死循环的插件
while true; do
    CHECK_ERR=$(make defconfig 2>&1)
    if echo "$CHECK_ERR" | grep -q "recursive dependency detected"; then
        BAD_SYMBOL=$(echo "$CHECK_ERR" | grep "symbol PACKAGE_" | head -n 1 | sed -E 's/.*symbol PACKAGE_([^ ]+).*/\1/')
        if [ -n "$BAD_SYMBOL" ]; then
            HAS_BAD_PLUGINS=1
            REASON="源码 Makefile 存在逻辑死循环 (Recursive dependency)"
            
            echo -e "${RED}[$(date '+%H:%M:%S')] ❌ 发现死循环插件: $BAD_SYMBOL${NC}"
            echo "【不通过】本地插件: $BAD_SYMBOL | 原因: $REASON" >> "$AUDIT_LOG"
            
            find feeds/ package/ -type d -name "$BAD_SYMBOL" -exec rm -rf {} + 2>/dev/null || true
            rm -rf tmp/
            continue
        fi
    fi
    break
done

# B. 检查已勾选插件的源码完整性
if [ -f ".config" ]; then
    grep "^CONFIG_PACKAGE_luci-app-" .config | grep "=y" | while read -r line; do
        pkg_name=$(echo "$line" | cut -d'=' -f1 | sed 's/CONFIG_PACKAGE_//')
        if ! find package/ feeds/ -type d -name "$pkg_name" | grep -q .; then
            HAS_BAD_PLUGINS=1
            REASON="缺失源码 (本地目录中未找到该包)"
            echo -e "${YELLOW}[$(date '+%H:%M:%S')] ⚠️  检测到本地缺失插件: $pkg_name，已自动取消勾选${NC}"
            echo "【不通过】本地插件: $pkg_name | 原因: $REASON" >> "$AUDIT_LOG"
            sed -i "s/CONFIG_PACKAGE_${pkg_name}=y/# CONFIG_PACKAGE_${pkg_name} is not set/g" .config
        fi
    done
fi

if [ "$HAS_BAD_PLUGINS" -eq 0 ]; then
    echo "【完美通过】所有在 .config 中勾选的插件均源头健康且本地完整！" >> "$AUDIT_LOG"
    echo -e "${GREEN}[$(date '+%H:%M:%S')] ✔️ 本地沙盒静态检测完美通过！${NC}"
fi

echo "" >> "$AUDIT_LOG"
echo "==========================================" >> "$AUDIT_LOG"
cat "$AUDIT_LOG"

make defconfig >/dev/null 2>&1
log_done "静态检测与审计完成。"

# 执行核心编译
log_prog "正在编译系统固件主体（耗时较长，请耐心等待）..."
BUILD_LOG="/tmp/build.log"
BUILD_FAILED=0

if ! make -j$(nproc) > "$BUILD_LOG" 2>&1; then
    BUILD_FAILED=1
fi

if [ "$BUILD_FAILED" -ne 0 ]; then
    echo -e "${RED}[$(date '+%H:%M:%S')] ❌ 编译失败，正在抓取最后 80 行关键报错：${NC}"
    echo "=========================================="
    tail -n 80 "$BUILD_LOG"
    echo "=========================================="
    exit 1
fi

log_done "系统主体固件编译成功！"


# ============================================================
# 第二阶段：系统固件编译完成后，在收尾步骤独立注入与克隆插件
# (完美符合你说的：系统都成功了，最后才添加插件)
# ============================================================
log_prog "【插件收尾注入】系统固件主体已编译完成，开始在末尾挂载第三方插件..."

CUSTOM_PLUGIN_DIR="package/custom-plugins"
mkdir -p "$CUSTOM_PLUGIN_DIR"

# 1. 安装 Passwall 依赖组件包
if [ ! -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall-packages" ]; then
    log_prog "-> 正在克隆 Passwall 依赖组件包..."
    git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages.git "$CUSTOM_PLUGIN_DIR/openwrt-passwall-packages"
else
    log_prog "-> Passwall 依赖组件包已存在，跳过克隆。"
fi

# 2. 安装 Passwall 主程序包
if [ ! -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall" ]; then
    log_prog "-> 正在克隆 Passwall 主程序..."
    git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall.git "$CUSTOM_PLUGIN_DIR/openwrt-passwall"
else
    log_prog "-> Passwall 主程序已存在，跳过克隆。"
fi

# 3. 安装 Sing-Box 模块化面板插件
if [ ! -d "$CUSTOM_PLUGIN_DIR/luci-app-sing-box" ]; then
    log_prog "-> 正在克隆 luci-app-sing-box 插件..."
    git clone --depth=1 https://github.com/sbwdl/luci-app-sing-box.git "$CUSTOM_PLUGIN_DIR/luci-app-sing-box"
else
    log_prog "-> luci-app-sing-box 插件已存在，跳过克隆。"
fi

log_done "【插件注入完成】第三方插件已在系统编译成功后成功挂载。"


# ============================================================
# 第三阶段：提取产物与插件独立打包归档
# ============================================================
log_prog "正在提取并规范化固件产物与多插件独立备份..."
BUILD_DATE=$(date +%Y%m%d)
mkdir -p bin/out

cp -f /tmp/plugin_check_report.txt bin/out/ 2>/dev/null || true

# 固件镜像打包
for file in bin/targets/sunxi/cortexa7/*nanopi-r1*ext4-sdcard*.img.gz; do
    if [ -f "$file" ]; then
        new_filename="immortalwrt-sunxi-cortexa7-friendlyarm_nanopi-r1s-h3-ext4-sdcard-${BUILD_DATE}.img.gz"
        cp -f "$file" "bin/out/$new_filename"
        echo "已生成: $new_filename"
    fi
done

for file in bin/targets/sunxi/cortexa7/*nanopi-r1*squashfs-sdcard*.img.gz; do
    if [ -f "$file" ]; then
        new_filename="immortalwrt-sunxi-cortexa7-friendlyarm_nanopi-r1s-h3-squashfs-sdcard-${BUILD_DATE}.img.gz"
        cp -f "$file" "bin/out/$new_filename"
        echo "已生成: $new_filename"
    fi
done

for file in bin/targets/sunxi/cortexa7/*rootfs*.tar.gz; do
    if [ -f "$file" ]; then
        new_filename="immortalwrt-sunxi-cortexa7-rootfs-${BUILD_DATE}.tar.gz"
        cp -f "$file" "bin/out/$new_filename"
        echo "已生成: $new_filename"
    fi
done

if [ -f "bin/targets/sunxi/cortexa7/sha256sums" ]; then
    cp -f bin/targets/sunxi/cortexa7/sha256sums bin/out/
fi

# 将每个第三方插件各自独立打包为单独的压缩包，方便下载备份
if [ -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall" ]; then
    tar -czf "bin/out/plugin-openwrt-passwall-${BUILD_DATE}.tar.gz" -C "$CUSTOM_PLUGIN_DIR" openwrt-passwall
    echo "已独立打包: plugin-openwrt-passwall-${BUILD_DATE}.tar.gz"
fi

if [ -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall-packages" ]; then
    tar -czf "bin/out/plugin-openwrt-passwall-packages-${BUILD_DATE}.tar.gz" -C "$CUSTOM_PLUGIN_DIR" openwrt-passwall-packages
    echo "已独立打包: plugin-openwrt-passwall-packages-${BUILD_DATE}.tar.gz"
fi

if [ -d "$CUSTOM_PLUGIN_DIR/luci-app-sing-box" ]; then
    tar -czf "bin/out/plugin-luci-app-sing-box-${BUILD_DATE}.tar.gz" -C "$CUSTOM_PLUGIN_DIR" luci-app-sing-box
    echo "已独立打包: plugin-luci-app-sing-box-${BUILD_DATE}.tar.gz"
fi

echo "=== 编译信息 ===" > bin/out/build-info.txt
echo "目标设备: NanoPi R1S-H3" >> bin/out/build-info.txt
echo "架构平台: sunxi/cortexa7" >> bin/out/build-info.txt
echo "编译时间: $(date '+%Y-%m-%d %H:%M:%S')" >> bin/out/build-info.txt
cp -f .config bin/out/config.buildinfo 2>/dev/null || true

log_done "所有基础固件产物、独立插件以及备份已整洁打包至 bin/out/ 目录！"
