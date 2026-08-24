#!/bin/bash
set -e

# ============================================
# ImmortalWrt 终极优雅版 (全局鉴权 + 动态批量克隆)
# ============================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

log_prog() { echo -e "${YELLOW}[$(date '+%H:%M:%S')] ◔ $1${NC}"; }
log_done() { echo -e "${GREEN}[$(date '+%H:%M:%S')] ● $1${NC}"; }

# 【第 1 步：提前声明全局鉴权】
if [ -n "$MY_GIT_TOKEN" ]; then
    log_prog "正在刷入 Git 全局凭证（提前声明，修改所有后续脚本）..."
    G_DOM="github.com"
    git config --global url."https://${MY_GIT_TOKEN}@${G_DOM}/".insteadOf "https://${G_DOM}/"
fi

# 【第 2 步：您要加的 10 个插件列表放这里】
PLUGINS=(
    "xiaorouji/openwrt-passwall-packages"
    "xiaorouji/openwrt-passwall"
    "safing/luci-app-sing-box"
)

# ============================================================
# 插件自动化批量挂载阶段
# ============================================================
log_prog "【插件批量注入】官方前期地基已稳，开始自动挂载第三方插件..."

CUSTOM_PLUGIN_DIR="package/custom-plugins"
mkdir -p "$CUSTOM_PLUGIN_DIR"

for repo in "${PLUGINS[@]}"; do
    folder_name=$(basename "$repo")
    
    if [ ! -d "$CUSTOM_PLUGIN_DIR/$folder_name" ]; then
        log_prog "-> 正在克隆 $folder_name ..."
        
        # 🟢 【仅此处进行了规范化修正】：补齐了 $ 变量符与域名后的斜杠
        git clone --depth=1 "https://github.com/${repo}.git" "$CUSTOM_PLUGIN_DIR/$folder_name"
    else
        log_prog "-> $folder_name 已存在，跳过克隆。"
    fi
done

make defconfig >/dev/null 2>&1
log_done "【插件注入并关联完成】所有第三方插件已成功批量纳入编译系统！"
