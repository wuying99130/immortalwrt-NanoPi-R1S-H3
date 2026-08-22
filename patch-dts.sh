#!/bin/bash
set -e

echo "=== 安装 NanoPi R1S H3 DTS 文件 ==="

# 脚本所在目录（仓库根目录）
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# ImmortalWrt 源码根目录
TARGET_DIR="${TARGET_DIR:-/tmp/immortalwrt}"

DTS_DST_DIR="${TARGET_DIR}/target/linux/sunxi/dts"
MAKEFILE="${TARGET_DIR}/target/linux/sunxi/image/cortex-a7.mk"
DTSI_SRC="${SCRIPT_DIR}/dts/sun8i-h3-nanopi.dtsi"
DTS_SRC="${SCRIPT_DIR}/dts/sun8i-h3-nanopi-r1s-h3.dts"

# 检查源文件
if [ ! -f "$DTSI_SRC" ]; then
    echo "错误: 找不到 $DTSI_SRC"
    exit 1
fi
if [ ! -f "$DTS_SRC" ]; then
    echo "错误: 找不到 $DTS_SRC"
    exit 1
fi

# 创建目标目录并复制 DTS 文件
mkdir -p "$DTS_DST_DIR"
cp -v "$DTSI_SRC" "$DTS_DST_DIR/"
cp -v "$DTS_SRC" "$DTS_DST_DIR/"

# 确保 Makefile 里有对应条目
if ! grep -q "nanopi-r1s-h3" "$MAKEFILE" 2>/dev/null; then
    echo "=== 添加 R1S 到 Makefile ==="
    cat >> "$MAKEFILE" << 'MK_EOF'

define Device/friendlyarm_nanopi-r1s-h3
	DEVICE_VENDOR := FriendlyARM
	DEVICE_MODEL := NanoPi R1S H3
	DEVICE_DTS := sun8i-h3-nanopi-r1s-h3
	SUPPORTED_DEVICES += friendlyarm,nanopi-r1s-h3
	DEVICE_PACKAGES := kmod-usb-net-rtl8152
endef
TARGET_DEVICES += friendlyarm_nanopi-r1s-h3
MK_EOF
    echo "=== Makefile 条目已添加 ==="
else
    echo "=== Makefile 条目已存在，跳过 ==="
fi

echo "=== DTS 安装完成 ==="