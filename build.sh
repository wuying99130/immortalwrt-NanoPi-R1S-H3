#!/bin/bash
set -e

# ============================================
# ImmortalWrt 纯净编译脚本 (多插件独立集中管理版)
# ============================================

WORKDIR="/tmp/immortalwrt"
mkdir -p "$WORKDIR"
cd "$WORKDIR"

# 颜色
GREEN='\033[0;32m'
CYAN='\033[0;36m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log_step()    { echo -e "${CYAN}◉${NC} $1"; }
log_prog()    { echo -e "${YELLOW}◔${NC} $1"; }
log_done()    { echo -e "${GREEN}●${NC} $1"; }
log_sub()     { echo -e "    ➔ $1"; }
log_skip()    { echo -e "    ◌ $1 (跳过)"; }

echo ""
echo "=========================================="
echo "  ImmortalWrt 编译脚本"
echo "  目标: NanoPi R1S-H3 (Allwinner H3)"
echo "  分支: openwrt-24.10"
echo "  时间: $(date '+%Y-%m-%d %H:%M:%S')"
echo "=========================================="

# ============================================
# 阶段一：准备环境（步骤 1-8 合并）
# ============================================
echo ""
echo "=========================================="
echo "  阶段一：准备编译环境"
echo "=========================================="

# 0. 注入重型开发语言（Go/Rust）顶级镜像加速通道
export GOPROXY=https://goproxy.cn,direct
export RUSTUP_DIST_SERVER=https://ustc.edu.cn
export RUSTUP_UPDATE_ROOT=https://mirrors.ustc.edu.cn/rustup


# ==============================================================================
# [MODULE_START]: 第三方扩展插件独立集中管理模块
# ------------------------------------------------------------------------------
# 职责说明: 
#   1. 集中安装非官方、易因 Feeds 命名冲突或环境报错的第三方插件。
#   2. 直接克隆到 package/custom-plugins/ 目录，独立下载、独立打包备份。
# ==============================================================================
log_prog "【模块加载】正在初始化第三方扩展插件独立模块..."

CUSTOM_PLUGIN_DIR="package/custom-plugins"
mkdir -p "$CUSTOM_PLUGIN_DIR"

# 1. 安装 Passwall 依赖组件包 (使用真实的 GitHub 链接)
if [ ! -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall-packages" ]; then
    log_prog "-> 正在克隆 Passwall 依赖组件包..."
    git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages.git "$CUSTOM_PLUGIN_DIR/openwrt-passwall-packages"
else
    log_prog "-> Passwall 依赖组件包已存在，跳过克隆。"
fi

# 2. 安装 Passwall 主程序包 (使用真实的 GitHub 链接)
if [ ! -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall" ]; then
    log_prog "-> 正在克隆 Passwall 主程序..."
    git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall.git "$CUSTOM_PLUGIN_DIR/openwrt-passwall"
else
    log_prog "-> Passwall 主程序已存在，跳过克隆。"
fi

# 3. 安装 Sing-Box 模块化面板插件 (使用真实的 GitHub 链接)
if [ ! -d "$CUSTOM_PLUGIN_DIR/luci-app-sing-box" ]; then
    log_prog "-> 正在克隆 luci-app-sing-box 插件..."
    git clone --depth=1 https://github.com/sbwdl/luci-app-sing-box.git "$CUSTOM_PLUGIN_DIR/luci-app-sing-box"
else
    log_prog "-> luci-app-sing-box 插件已存在，跳过克隆。"
fi

log_done "【模块完成】第三方扩展插件独立模块加载完毕。"
# ==============================================================================
# [MODULE_END]: 第三方扩展插件独立管理模块
# ==============================================================================


# 1. 下载源码包与编译工具链
log_prog "下载源码依赖包..."
make download -j8
find dl -size -1024c -exec rm -f {} \;

log_prog "编译基础 tools..."
make tools/install -j$(nproc)

log_prog "编译 toolchain..."
make toolchain/install -j$(nproc)


# ============================================================
# 🛡️ 官方 Feeds 更新与本地沙盒完整性审计
# ============================================================
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
# ============================================================


# 2. 执行核心编译
log_prog "正在编译固件（耗时较长，请耐心等待）..."
BUILD_LOG="/tmp/build.log"
BUILD_FAILED=0

# 显示 make[N] 目录级进度 + 所有异常（错误/警告/fatal/未定义引用等）
make -j$(nproc) 2>&1 | tee "$BUILD_LOG" | grep -E "(^make\[|error:|warning:|Error |ERROR|WARNING|fatal:|undefined|FAILED)" || BUILD_FAILED=1

if [ ${PIPESTATUS[0]} -ne 0 ]; then
    BUILD_FAILED=1
fi

echo ""
if [ "$BUILD_FAILED" -eq 0 ]; then
    log_done "固件编译完成"
else
    echo ""
    echo "=========================================="
    echo "   编译失败，以下是错误详情"
    echo "=========================================="
    echo ""
    grep -n -i "error\|Error\|ERROR" "$BUILD_LOG" | head -20 | while IFS=: read -r line_num _; do
        start=$((line_num - 5))
        end=$((line_num + 5))
        [ $start -lt 1 ] && start=1
        echo "--- 错误附近 (行 ${line_num}) ---"
        sed -n "${start},${end}p" "$BUILD_LOG"
        echo ""
    done
    echo "=========================================="
    echo "   完整编译日志: $BUILD_LOG"
    echo "=========================================="
    exit 1
fi

log_done "固件编译成功"

# 3. 收集产物、规范化命名并【独立打包所有第三方插件备份】
log_prog "正在提取并规范化固件产物与多插件独立备份..."
BUILD_DATE=$(date +%Y%m%d)

mkdir -p bin/out

cp -f /tmp/plugin_check_report.txt bin/out/ 2>/dev/null || true

# 固件镜像打包
for file in bin/targets/sunxi/cortexa7/*nanopi-r1*ext4-sdcard*.img.gz; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        new_filename=$(echo "$filename" | sed 's/^openwrt-/immortalwrt-/' | sed "s/\.img\.gz$/-${BUILD_DATE}.img.gz/")
        cp -f "$file" "bin/out/$new_filename"
        echo "已提取: $new_filename"
    fi
done

for file in bin/targets/sunxi/cortexa7/*nanopi-r1*squashfs-sdcard*.img.gz; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        new_filename=$(echo "$filename" | sed 's/^openwrt-/immortalwrt-/' | sed "s/\.img\.gz$/-${BUILD_DATE}.img.gz/")
        cp -f "$file" "bin/out/$new_filename"
        echo "已提取: $new_filename"
    fi
done

for file in bin/targets/sunxi/cortexa7/*rootfs*.tar.gz; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        # 自动将前缀标准化并带上日期版本号
        new_filename=$(echo "$filename" | sed 's/^openwrt-/immortalwrt-/' | sed "s/\.tar\.gz$/-${BUILD_DATE}.tar.gz/")
        cp -f "$file" "bin/out/$new_filename"
        echo "已提取: $new_filename"
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
echo "分支: openwrt-24.10" >> bin/out/build-info.txt
echo "目标: NanoPi R1S-H3 (sunxi/cortexa7)" >> bin/out/build-info.txt
echo "日期: $(date '+%Y-%m-%d %H:%M:%S')" >> bin/out/build-info.txt
cp -f .config bin/out/config.buildinfo 2>/dev/null || true

log_done "所有产物及独立插件备份已整洁打包至 bin/out/ 目录"
