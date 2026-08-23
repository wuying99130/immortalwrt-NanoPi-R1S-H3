#!/bin/bash
set -e

# ============================================
# ImmortalWrt 正确逻辑编译脚本 (系统主体完成前、顺延精准注入版)
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
# 第一阶段：安安心心专注基础源码下载、工具链与官方纯净生态初始化
# ============================================================

log_prog "下载源码依赖包..."
make download -j8
find dl -size -1024c -exec rm -f {} \;

log_prog "编译基础 tools..."
make tools/install -j$(nproc)

log_prog "编译 toolchain..."
make toolchain/install -j$(nproc)

log_prog "更新官方 Feeds 索引并执行纯净系统配置..."

AUDIT_LOG="/tmp/plugin_check_report.txt"
echo "==========================================" > "$AUDIT_LOG"
echo "       官方纯净系统初始化与基础检测报告     " >> "$AUDIT_LOG"
echo "       检测时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$AUDIT_LOG"
echo "==========================================" >> "$AUDIT_LOG"
echo "" >> "$AUDIT_LOG"

# 仅更新纯净的官方核心源
./scripts/feeds update -a
./scripts/feeds install -a

# 纯净状态下的 defconfig
make defconfig >/dev/null 2>&1
log_done "官方纯净系统初始化与基础检测已完成。"


# ============================================================
# 第二阶段：官方基础流程已安全走完，在正式大编译前顺延注入插件
# ============================================================
log_prog "【插件顺延注入】官方前期地基已稳，开始在编译大动作前挂载第三方插件..."

CUSTOM_PLUGIN_DIR="package/custom-plugins"
mkdir -p "$CUSTOM_PLUGIN_DIR"

# 【隔离测试：暂时注释掉 Passwall 相关克隆，排查 128 报错根源】
# # 1. 安装 Passwall 依赖组件包
# if [ ! -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall-packages" ]; then
#     log_prog "-> 正在克隆 Passwall 依赖组件包..."
#     git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall-packages.git "$CUSTOM_PLUGIN_DIR/openwrt-passwall-packages"
# else
#     log_prog "-> Passwall 依赖组件包已存在，跳过克隆。"
# fi
# 
# # 2. 安装 Passwall 主程序包
# if [ ! -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall" ]; then
#     log_prog "-> 正在克隆 Passwall 主程序..."
#     git clone --depth=1 https://github.com/xiaorouji/openwrt-passwall.git "$CUSTOM_PLUGIN_DIR/openwrt-passwall"
# else
#     log_prog "-> Passwall 主程序已存在，跳过克隆。"
# fi

# 3. 安装 Sing-Box 模块化面板插件（保持正常安装，测试其他插件）
if [ ! -d "$CUSTOM_PLUGIN_DIR/luci-app-sing-box" ]; then
    log_prog "-> 正在克隆 luci-app-sing-box 插件..."
    git clone --depth=1 https://github.com/sbwdl/luci-app-sing-box.git "$CUSTOM_PLUGIN_DIR/luci-app-sing-box"
else
    log_prog "-> luci-app-sing-box 插件已存在，跳过克隆。"
fi

# 再次执行 defconfig，让系统正式把刚克隆进来的插件纳入编译索引
make defconfig >/dev/null 2>&1
log_done "【插件注入并关联完成】第三方插件已成功纳入编译系统。"


# ============================================================
# 第三阶段：带着已就位的插件，执行全量固件编译
# ============================================================
log_prog "正在编译包含自定义插件的系统固件主体（耗时较长，请耐心等待）..."
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

log_done "系统主体固件及插件编译成功！"


# ============================================================
# 第四阶段：提取产物与归档
# ============================================================
log_prog "正在提取并规范化固件产物..."
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

echo "=== 编译信息 ===" > bin/out/build-info.txt
echo "目标设备: NanoPi R1S-H3" >> bin/out/build-info.txt
echo "架构平台: sunxi/cortexa7" >> bin/out/build-info.txt
echo "编译时间: $(date '+%Y-%m-%d %H:%M:%S')" >> bin/out/build-info.txt
cp -f .config bin/out/config.buildinfo 2>/dev/null || true

log_done "所有基础固件产物及编译信息已整洁打包至 bin/out/ 目录！"
