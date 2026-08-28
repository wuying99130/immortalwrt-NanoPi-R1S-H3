
# NanoPi-R1S-H3 ImmortalWrt 固件与硬件开发仓库

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
├── .config                       # 锁定了硬件与内核特性的总配置文件
├── build.sh                      # 主编译流水线脚本（内置源码初始化、第三方插件顺延注入）
├── patch-dts.sh                  # DTS 自动化挂载与 Makefile 目标板注册脚本
└── feeds.conf.default            # 扩展插件源配置

```

---



```text
此仓库为初始编译版本，仅规划架构，跑通编译，做为进一步开发的基础母版。

```
