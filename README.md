
# NanoPi-R1S-H3 ImmortalWrt 固件与硬件 SDK 开发仓库

本项目专为老旧硬件 **NanoPi R1S-H3**（Allwinner H3, sunxi/cortexa7）打造。由于官方已停止对该硬件架构的维护，本仓库集中归档了针对该设备的底层硬件设备树（DTS）、驱动修补脚本以及全功能的固件与插件裁剪配置，支持通过 GitHub Actions 进行云端手动触发构建。

---

## 仓库目录结构

```text
immortalwrt-NanoPi-R1S-H3/
├── .github/workflows/
│   ├── build.yml                 # 原有固件编译工作流
│   ├── build-firmware-sdk.yml    # 全功能固件与 SDK 双重产物编译工作流
│   └── sdk.yml                   # 专属硬件 SDK 轻量化打包工作流
├── dts/
│   ├── sun8i-h3-nanopi.dtsi      # H3 板级公共设备树头文件 (含引脚、LED、基础 regulator)
│   └── sun8i-h3-nanopi-r1s-h3.dts # NanoPi R1S 专属设备树 (含 vdd-cpux 电压与网口绑定)
├── sdk/                          # 专属硬件 SDK 核心归档
│   ├── bsp/                      # 板级支持与内核配置指引
│   │   └── board.mk              # 硬件特定编译参数
│   ├── patch/                    # 针对该板子的内核及驱动补丁
│   ├── target/                   # 目标板定义和自动化同步脚本
│   └── README.md                 # SDK 独立编译与维护手册
├── .config                       # 锁定了硬件与内核特性的总配置文件
├── build.sh                      # 主编译流水线脚本（内置源码初始化、第三方插件顺延注入）
├── patch-dts.sh                  # DTS 自动化挂载与 Makefile 目标板注册脚本
└── feeds.conf.default            # 扩展插件源配置

```

---

## 核心硬件适配特性

* **电压调控优化**：在设备树中精准定义了 `vdd-cpux` 调压器（`1100000mv` 至 `1300000mv`），保证 H3 核心在高负载下的稳定性。
* **板载网络与外设**：完美适配 `emac` 网口以及板载状态灯引脚（`PA10`/`PL10`），并内置了 USB 网卡 `rtl8152` 驱动支持。
* **第三方生态集成**：通过流水线编译脚本在主干源码初始化完成后，顺延精准注入 `Passwall` 及其依赖组件和 `Sing-box` 面板。

---

## GitHub Actions 云端编译说明

本项目配置了两个互补的手动触发工作流，均可在 Actions 页面中通过 `workflow_dispatch` 按需发起：

1. **`build-firmware-sdk.yml`（固件 + SDK 双重功能）**
* **适用场景**：完整构建生产环境使用的固件镜像。
* **执行流程**：拉取官方主干源码、更新 Feeds 源、注入 `.config` 与 DTS、执行 `build.sh` 完成全量编译，并在末尾打包输出固件镜像与编译元信息。


2. **`sdk.yml`（轻量化 SDK 专属打包）**
* **适用场景**：仅需提取该硬件底层 SDK 资产、设备树或开发环境模板时使用。
* **执行流程**：跳过耗时的大型工具链与系统编译，直接挂载 DTS 资产，将底层驱动定义与配置文件打包为独立的轻量压缩包。



```

```
