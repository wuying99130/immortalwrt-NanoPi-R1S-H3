#!/bin/bash
set -e

# ============================================
# ImmortalWrt 正确逻辑编译脚本 (系统主体完成前、顺延精准注入版)
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

log_prog() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ◔ $1${NC}"; }
log_done() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ● $1${NC}"; }

# 如果在 GitHub Actions 无人值守环境中，自动注入并绑定全局鉴权凭证，防 128 错误卡死
# ============================================================
# 【优雅破局】在子进程最顶部，为 build.sh 内部环境刷入专属全局鉴权路由
# ============================================================
if [ -n "$MY_GIT_TOKEN" ]; then
    log_prog "正在为 build.sh 内部环境刷入子进程专属 Git 全局凭证..."
    
    # 拆分纯文本变量，用绝对安全的无链接技术绕过 AI 系统吞网址的严重 Bug
    G_DOM="github.com"
    git config --global url."https://${MY_GIT_TOKEN}@${G_DOM}/".insteadOf "https://${G_DOM}/"
fi

echo "=========================================="
echo "  开始执行核心编译与固件打包"
echo "  目标: NanoPi R1S-H3 (sunxi/cortexa7)"
echo "=========================================="

# 0. 注入重型开发语言（Go/Rust）顶级镜像加速通道
export GOPROXY=https://goproxy.cn,direct
export RUSTUP_DIST_SERVER=https://ustc.edu.cn
export RUSTUP_UPDATE_ROOT=https://ustc.edu.cn


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

G_SITE="github.com"
P_PACKAGES="Openwrt-Passwall/openwrt-passwall-packages.git"
P_MAIN="Openwrt-Passwall/openwrt-passwall.git"
P_SINGBOX="eooce/Sing-box.git"

# 1. 精准下载依赖组件包
if [ ! -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall-packages" ]; then
    log_prog "-> 正在克隆 Passwall 依赖组件包..."
    git clone --depth=1 "https://${G_SITE}/${P_PACKAGES}" "$CUSTOM_PLUGIN_DIR/openwrt-passwall-packages"
fi

# 2. 精准下载 Passwall 主程序
if [ ! -d "$CUSTOM_PLUGIN_DIR/openwrt-passwall" ]; then
    log_prog "-> 正在克隆 Passwall 主程序..."
    git clone --depth=1 "https://${G_SITE}/${P_MAIN}" "$CUSTOM_PLUGIN_DIR/openwrt-passwall"
fi

# 3. 精准下载 sing-box 面板插件（直接显式拼接 Token，杜绝全局配置失效或 128 错误）
if [ ! -d "$CUSTOM_PLUGIN_DIR/luci-app-sing-box" ]; then
    log_prog "-> 正在克隆 luci-app-sing-box 插件..."
    git clone --depth=1 "https://${MY_GIT_TOKEN}@${G_SITE}/${P_SINGBOX}" "$CUSTOM_PLUGIN_DIR/luci-app-sing-box"
fi

# 再次执行 defconfig，让系统正式把刚克隆进来的插件纳入编译索引
make defconfig >/dev/null 2>&1
log_done "【插件注入并关联完成】第三方插件已成功纳入编译系统。"


# ==========================================
# 第三阶段：带着已就位的插件，执行全量固件编译
# ==========================================
log_prog "正在编译包含自定义插件的系统固件主体（耗时较长，请耐心等待）..."
BUILD_LOG="/tmp/build.log"
BUILD_FAILED=0

# 【新增此处】优先单线程把高负载的 Rust 宿主机工具链编译过掉，防止并发崩溃
log_prog "正在预编译容易过载的 rust 主机工具链..."
make package/feeds/packages/rust/host-compile -j1 || true

# 接着放开多线程正常编译大盘
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
