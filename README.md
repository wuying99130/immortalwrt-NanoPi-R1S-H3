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

⚙️ 核心架构与工作原理
零源码沉重负担：本地与 Git 仓库中仅保留几 KB 的核心配置、补丁和脚本，不存储体积庞大的上游源码树。

云端动态解耦：当在 GitHub Actions 触发编译时，云端虚拟机自动克隆一份干净的官方 openwrt-24.10 稳定分支。

精准硬件注入：通过 patch-dts.sh 脚本自动将手写的底层设备树（DTS）和设备条目塞入内核，完美适配 NanoPi R1S-H3 的网卡、LED 指示灯及存储驱动。

规范化固件产出：编译完成后，自动提取镜像并统一规范命名，整洁存放至 bin/out/ 目录供下载。

🧠 编译的思路与底层原理
本仓库采用的是典型的 DevOps 云端解耦编译流，其运作逻辑和核心思路如下：

资产与源码分离（分层管理）：

上游源码：代表操作系统的“大骨架”（由 ImmortalWrt 官方维护）。

私有资产：代表针对特定硬件的“灵魂”（即我们手写的 .config 裁剪菜单、feeds.conf.default 扩展插件源、以及 dts/ 硬件设备树）。

思路：我们不把骨架抱回家里（不 Fork 整个大仓），而是建一个精巧的“工具箱”仓。每次需要固件时，让云端去网上借骨架，然后把我们的灵魂和补丁现场缝合进去。

自动化流水线注入（CI/CD 闭环）：

准备阶段：GitHub Actions 虚拟环境拉取官方源码，并将本地的定制配置文件无缝覆盖到云端源码根目录。

内核热补丁（patch-dts.sh）：因为官方对 NanoPi R1S-H3 失去了原生支持，脚本会在编译前强行把 sun8i-h3-nanopi-r1s-h3.dts 注入到 target/linux/sunxi/dts/ 目录，并在 cortex-a7.mk 中注册设备条目，使编译器能够正确识别并编译该硬件。

依赖预编译与多线程构建（build.sh）：

先通过 make download 预下载依赖包，通过 make tools 和 make toolchain 编译交叉编译工具链。

随后调用多核性能（make -j$(nproc)）完成内核、根文件系统和 LuCI 插件的整体构建。

自动化收尾：跳过人工手动寻找镜像的繁琐步骤，通过脚本利用通配符精准捕获生成的镜像文件，统一重命名并归档至 bin/out/，最终由 Actions 统一打包成 Artifacts 上传。

🚀 如何使用与触发编译
进入仓库的 Actions 页面。

选择 Build ImmortalWrt NanoPi R1S-H3 工作流。

点击 Run workflow 手动触发云端编译。

编译结束后，直接在页面下方的 Artifacts 处下载打包好的固件。
