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

# 0. 注入重型开发语言（Go/Rust）顶级镜像加速通道
export GOPROXY=https://goproxy.cn,direct
export RUSTUP_DIST_SERVER=https://ustc.edu.cn
export RUSTUP_UPDATE_ROOT=https://ustc.edu.cn/rustup

# 1. 下载源码包与编译工具链
log_prog "下载源码依赖包..."
make download -j8
find dl -size -1024c -exec rm -f {} \;

log_prog "编译基础 tools..."
make tools/install -j$(nproc)

log_prog "编译 toolchain..."
make toolchain/install -j$(nproc)


# ============================================================
# ⚙️ 核心新增：全自动沙盒依赖检测与审计报告系统
# ============================================================
log_prog "启动全自动沙盒依赖检测与审计..."

REPORT_FILE="/tmp/plugin_check_report.txt"
echo "==========================================" > "$REPORT_FILE"
echo "       插件完整性静态检测与剔除报告       " >> "$REPORT_FILE"
echo "       检测时间: $(date '+%Y-%m-%d %H:%M:%S')" >> "$REPORT_FILE"
echo "==========================================" >> "$REPORT_FILE"
echo "" >> "$REPORT_FILE"

HAS_BAD_PLUGINS=0

# A. 自动揪出并物理干掉导致系统死循环（Recursive dependency）的垃圾插件
while true; do
    CHECK_ERR=$(make defconfig 2>&1)
    if echo "$CHECK_ERR" | grep -q "recursive dependency detected"; then
        BAD_SYMBOL=$(echo "$CHECK_ERR" | grep "symbol PACKAGE_" | head -n 1 | sed -E 's/.*symbol PACKAGE_([^ ]+).*/\1/')
        if [ -n "$BAD_SYMBOL" ]; then
            HAS_BAD_PLUGINS=1
            echo "【不通过】插件: $BAD_SYMBOL | 原因: 源码 Makefile 存在逻辑死循环 (Recursive dependency)" >> "$REPORT_FILE"
            
            # 物理删除源码目录，彻底阻断其参与 Kconfig 扫描
            find feeds/ package/ -type d -name "$BAD_SYMBOL" -exec rm -rf {} + 2>/dev/null || true
            rm -rf tmp/
            continue
        fi
    fi
    break
done

# B. 挨个核对已勾选插件的源码完整性，缺失源的插件自动取消勾选，不留隐患
grep "^CONFIG_PACKAGE_luci-app-" .config | grep "=y" | while read -r line; do
    pkg_name=$(echo "$line" | cut -d'=' -f1 | sed 's/CONFIG_PACKAGE_//')
    if ! find package/ feeds/ -type d -name "$pkg_name" | grep -q .; then
        HAS_BAD_PLUGINS=1
        echo "【不通过】插件: $pkg_name | 原因: 缺失源码 (Feeds 软件源中没有该包，或网络拉取失败)" >> "$REPORT_FILE"
        
        # 自动关闭勾选，不带病进入 5 小时编译流程
        sed -i "s/CONFIG_PACKAGE_${pkg_name}=y/# CONFIG_PACKAGE_${pkg_name} is not set/g" .config
    fi
done

# C. 记录检测结果
if [ "$HAS_BAD_PLUGINS" -eq 0 ]; then
    echo "【完美通过】所有在 .config 中勾选的插件均源码完整、依赖合法！" >> "$REPORT_FILE"
fi

echo "" >> "$REPORT_FILE"
echo "==========================================" >> "$REPORT_FILE"

# 终端实时打印报告，让你在 Actions 网页上前几秒即可知晓结果
cat "$REPORT_FILE"

# 确保检测过滤完成后，配置文件干净对齐
make defconfig >/dev/null 2>&1
log_done "依赖与插件审计完成，不合格插件已静默剔除。"
# ============================================================


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

# 安全转储检测审计报告到你的固件输出包中
cp -f /tmp/plugin_check_report.txt bin/out/ 2>/dev/null || true

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
