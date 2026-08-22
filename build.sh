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

# 0. 注入重型开发语言（Go/Rust）顶级镜像加速通道
export GOPROXY=https://goproxy.cn,direct
export RUSTUP_DIST_SERVER=https://ustc.edu.cn
export RUSTUP_UPDATE_ROOT=https://ustc.edu.cn/rustup

# 1. 下载源码包与编译工具链
log_prog "下载源码依赖包..."
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

# 安全转储检测审计报告到你的固件输出包中
cp -f /tmp/plugin_check_report.txt bin/out/ 2>/dev/null || true

# ext4 镜像（使用 *nanopi-r1* 确保宽泛命中，重命名为 nanopi-r1s-h3）
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

log_done "所有产物已整洁打包至 bin/out/ 目录"
