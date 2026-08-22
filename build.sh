#!/bin/bash
set -e

# ============================================
# ImmortalWrt 纯净编译脚本 (现代解耦版)
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

# 1. 下载源码包与编译工具链
log_prog "下载源码依赖包..."
make download -j8
find dl -size -1024c -exec rm -f {} \;

log_prog "编译基础 tools..."
make tools/install -j$(nproc)

log_prog "编译 toolchain..."
make toolchain/install -j$(nproc)

# 2. 执行核心编译（带静默防爆与智能截错）
log_prog "正在编译固件（耗时较长，请耐心等待）..."
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

log_done "固件编译成功"

# 3. 收集产物并严格转换为你指定的命名格式
log_prog "正在提取并规范化固件产物..."
BUILD_DATE=$(date +%Y%m%d)
mkdir -p bin/out

# ext4 镜像（使用 *nanopi-r1* 确保宽泛命中，重命名为 nanopi-r1s-h3）
for file in bin/targets/sunxi/cortexa7/*nanopi-r1*ext4-sdcard*.img.gz; do
    if [ -f "$file" ]; then
        new_filename="immortalwrt-sunxi-cortexa7-friendlyarm_nanopi-r1s-h3-ext4-sdcard-${BUILD_DATE}.img.gz"
        cp -f "$file" "bin/out/$new_filename"
        echo "已生成: $new_filename"
    fi
done

# squashfs 镜像（使用 *nanopi-r1* 确保宽泛命中，重命名为 nanopi-r1s-h3）
for file in bin/targets/sunxi/cortexa7/*nanopi-r1*squashfs-sdcard*.img.gz; do
    if [ -f "$file" ]; then
        new_filename="immortalwrt-sunxi-cortexa7-friendlyarm_nanopi-r1s-h3-squashfs-sdcard-${BUILD_DATE}.img.gz"
        cp -f "$file" "bin/out/$new_filename"
        echo "已生成: $new_filename"
    fi
done

# rootfs.tar.gz
for file in bin/targets/sunxi/cortexa7/*rootfs*.tar.gz; do
    if [ -f "$file" ]; then
        new_filename="immortalwrt-sunxi-cortexa7-rootfs-${BUILD_DATE}.tar.gz"
        cp -f "$file" "bin/out/$new_filename"
        echo "已生成: $new_filename"
    fi
done

# sha256 校验码
if [ -f "bin/targets/sunxi/cortexa7/sha256sums" ]; then
    cp -f bin/targets/sunxi/cortexa7/sha256sums bin/out/
fi

# 编译信息说明
echo "=== 编译信息 ===" > bin/out/build-info.txt
echo "目标设备: NanoPi R1S-H3" >> bin/out/build-info.txt
echo "架构平台: sunxi/cortexa7" >> bin/out/build-info.txt
echo "编译时间: $(date '+%Y-%m-%d %H:%M:%S')" >> bin/out/build-info.txt
cp -f .config bin/out/config.buildinfo 2>/dev/null || true

log_done "所有产物已整洁打包至 bin/out/ 目录"