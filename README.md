# ImmortalWrt for NanoPi R1S-H3 (轻量化云端编译版)

本项目是一个专门为 **NanoPi R1S-H3**（Allwinner H3, sunxi/cortexa7）定制的 ImmortalWrt 轻量化资产与云端自动编译仓库。

通过**“核心资产留存 + 云端动态拉取源码”**的解耦架构，彻底告别了传统 OpenWrt 仓库体积庞大、本地维护沉重卡顿的痛点。

---

## 📂 仓库目录结构

```text
immortalwrt-NanoPi-R1S-H3/
├── .github/
│   └── workflows/
│       └── build.yml               # 云端工作流：自动拉取源码、注入补丁并触发编译
├── dts/
│   ├── sun8i-h3-nanopi.dtsi        # H3 系列公共板级设备树底座
│   └── sun8i-h3-nanopi-r1s-h3.dts  # NanoPi R1S-H3 硬件设备树
├── .config                         # 固件功能裁剪与精选插件配置
├── feeds.conf.default              # 官方源 + 第三方插件源定义
├── patch-dts.sh                    # 硬件资产自动注入脚本（写入 DTS 与 Makefile）
└── build.sh                        # 编译、打包与固件产物重命名脚本
