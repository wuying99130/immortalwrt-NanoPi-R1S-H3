**NanoPi-R1S-H3 ImmortalWrt 专属硬件 SDK 开发与维护手册**

本项目专为老旧硬件 **NanoPi-R1S-H3**（Allwinner H3, `sunxi/cortexa7`）的 `feature/SDK` 分支打造。通过专属的自动化流水线，集中归档并产出带有全套内核符号表与交叉编译工具链的专属 **SDK**，彻底解决在本地编译外部 `ipk` 插件时因版本和内核依赖不匹配而报错的问题。

---

**仓库目录结构与核心功能说明**

```text
immortalwrt-NanoPi-R1S-H3/
├── .github/workflows/
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

* **`.github/workflows/sdk.yml`**：定义了轻量化打包专属 SDK 的云端工作流，负责拉取源码、注入配置并触发打包。
* **`dts/`**：存放板级设备树源码。`sun8i-h3-nanopi.dtsi` 提供通用 H3 外设定义，`sun8i-h3-nanopi-r1s-h3.dts` 专供 NanoPi R1S 适配高负载稳压与网络绑定。
* **`sdk/`**：存放 SDK 独立维护所需的板级支持（`bsp/`）、内核补丁（`patch/`）及目标板定义脚本（`target/`）。
* **`.config`**：锁定了 `sunxi/cortexa7` 架构、USB 网卡驱动、文件系统及各项 LuCI 插件的总配置文件。
* **`build.sh`**：封装了依赖安装、feeds 更新、`defconfig` 展开以及 `tools`/`toolchain` 编译的主流水线脚本。

---

**如何在云端一键生成专属 SDK**

仓库中已内置专属自动化打包工作流 [sdk.yml](https://github.com/wuying99130/immortalwrt-NanoPi-R1S-H3/blob/feature/SDK/.github/workflows/sdk.yml)。当您需要更新 SDK 时，只需执行以下操作：

1. 进入 GitHub 仓库的 **Actions** 页面。
2. 在左侧选择 **Build Custom Hardware SDK** 工作流。
3. 点击右侧的 **Run workflow** 按钮手动触发。
4. 流水线会自动克隆指定源码、注入私有配置 [.config](https://github.com/wuying99130/immortalwrt-NanoPi-R1S-H3/blob/feature/SDK/.config) 与设备树，并完成底层工具链编译及官方 SDK 打包。

---

**下载与本地编译 `ipk` 插件指南**

当云端 `sdk.yml` 运行完成后：

1. 在 GitHub 页面下载打包好的产物压缩包（名称通常为 `nanopi-r1s-h3-custom-sdk`）。
2. 将压缩包解压到您的 Linux 编译主机中。
3. 在 SDK 根目录下，通过以下命令开始定向编译您需要的专属 `ipk` 插件：

```bash
# 1. 更新或安装扩展 feeds
./scripts/feeds update -a
./scripts/feeds install -a

# 2. 配置需要编译的插件（在菜单中勾选为您需要的 package 为 M）
make menuconfig

# 3. 开始单包编译（以编译某插件为例）
make package/your-plugin-name/compile -j$(nproc)

```
