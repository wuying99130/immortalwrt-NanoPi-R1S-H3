#!/bin/bash
set -e

# ============================================
# ImmortalWrt 编译脚本 (精简日志版)
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

# ---- 1. 安装编译依赖 ----
log_prog "安装编译依赖..."
sudo sed -i 's|http://azure.archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
sudo sed -i 's|http://archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
sudo sed -i 's|https://archive.ubuntu.com|https://mirrors.tuna.tsinghua.edu.cn|g' /etc/apt/sources.list
sudo apt update
sudo apt install -y build-essential clang flex bison g++ gawk \
gcc-multilib g++-multilib gettext git libfuse-dev libncurses5-dev \
libssl-dev python3 python3-dev python3-pip python3-setuptools \
rsync unzip zlib1g-dev file wget subversion patch upx-ucl \
autoconf automake libtool
log_sub "编译依赖安装完成"

# ---- 2. 检查环境 ----
log_sub "工作目录: $WORKDIR（已是源码根目录，跳过克隆）"

# ---- 3. 更新 feeds ----
log_prog "更新 feeds..."
./scripts/feeds update -a
./scripts/feeds install -a
log_sub "feeds 更新完成"

# ---- 4. 确认 .config ----
log_prog "确认 .config..."
if [ ! -f .config ]; then
    echo "错误: 缺少 .config，请检查 CI 是否已复制"
    exit 1
fi
log_sub ".config 就绪（仓库版本，路径: $PWD/.config）"

# ---- 5. defconfig ----
log_prog "展开默认配置..."
make defconfig
log_sub "defconfig 完成"

# ---- 6. 下载源码 ----
log_prog "下载源码包..."
make download -j8
find dl -size -1024c -exec rm -f {} \;
log_sub "源码包下载完成"

# ---- 7. 编译工具链 ----
log_prog "编译工具链..."
make tools/install -j$(nproc)
log_sub "工具链编译完成"

# ---- 8. 编译交叉工具链 ----
log_prog "编译交叉工具链..."
make toolchain/install -j$(nproc)
log_sub "交叉工具链编译完成"

log_done "阶段一完成，环境就绪"

# ============================================
# 阶段二：编译固件（精简目录级进度）
# ============================================
echo ""
echo "=========================================="
echo "  阶段二：编译固件"
echo "=========================================="

log_prog "编译固件，耗时较长，请耐心等待..."
echo ""

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

# ============================================
# 阶段三：收集产物
# ============================================
echo ""
echo "=========================================="
echo "  阶段三：收集产物"
echo "=========================================="

log_prog "查找生成的固件..."
echo "=== 正在精准提取固件 ==="
BUILD_DATE=$(date +%Y%m%d)

mkdir -p bin/out

# ext4-sdcard 镜像（使用 *nanopi-r1* 宽泛匹配，确保能抓到目标固件并加上日期）
for file in bin/targets/sunxi/cortexa7/*nanopi-r1*ext4-sdcard*.img.gz; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        new_filename=$(echo "$filename" | sed 's/^openwrt-/immortalwrt-/' | sed "s/\.img\.gz$/-${BUILD_DATE}.img.gz/")
        cp -f "$file" "bin/out/$new_filename"
        echo "已提取: $new_filename"
    fi
done

# squashfs-sdcard 镜像（使用 *nanopi-r1* 宽泛匹配，确保能抓到目标固件并加上日期）
for file in bin/targets/sunxi/cortexa7/*nanopi-r1*squashfs-sdcard*.img.gz; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        new_filename=$(echo "$filename" | sed 's/^openwrt-/immortalwrt-/' | sed "s/\.img\.gz$/-${BUILD_DATE}.img.gz/")
        cp -f "$file" "bin/out/$new_filename"
        echo "已提取: $new_filename"
    fi
done

# rootfs.tar.gz (保持原样不动，按通用 rootfs 匹配)
for file in bin/targets/sunxi/cortexa7/*rootfs*.tar.gz; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        # 自动将前缀标准化并带上日期版本号
        new_filename=$(echo "$filename" | sed 's/^openwrt-/immortalwrt-/' | sed "s/\.tar\.gz$/-${BUILD_DATE}.tar.gz/")
        cp -f "$file" "bin/out/$new_filename"
        echo "已提取: $new_filename"
    fi
done

# sha256sums
if [ -f "bin/targets/sunxi/cortexa7/sha256sums" ]; then
    cp -f bin/targets/sunxi/cortexa7/sha256sums bin/out/
fi

# 编译信息
echo "=== 编译信息 ===" > bin/out/build-info.txt
echo "分支: openwrt-24.10" >> bin/out/build-info.txt
echo "目标: NanoPi R1S-H3 (sunxi/cortexa7)" >> bin/out/build-info.txt
echo "日期: $(date '+%Y-%m-%d %H:%M:%S')" >> bin/out/build-info.txt
cp -f .config bin/out/config.buildinfo 2>/dev/null || true

echo "=== 打包输出目录清单 ==="
ls -lh bin/out/
log_done "产物就绪"

# ---- 汇总 ----
echo ""
echo "=========================================="
echo "          编译汇总"
echo "=========================================="
printf "  %-20s : %s\n" "源码分支" "openwrt-24.10"
printf "  %-20s : %s\n" "目标设备" "NanoPi R1S-H3 (Allwinner H3)"
printf "  %-20s : %s\n" "目标平台" "sunxi/cortexa7"
printf "  %-20s : %s\n" "LuCI 主题" "Argon"
printf "  %-20s : %s\n" "WiFi" "BCM43430 (brcmfmac)"
printf "  %-20s : %s\n" "USB 网络" "RTL8152"
printf "  %-20s : %s\n" "文件系统" "ext4/squashfs/targz"
printf "  %-20s : %s\n" "固件目录" "bin/out/"
echo "=========================================="
echo ""
log_done "全部完成! 固件位于 bin/out/"
echo ""
