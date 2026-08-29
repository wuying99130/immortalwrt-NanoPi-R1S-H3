# ImmortalWrt NanoPi R1S-H3 固件与 SDK 自动化编译说明

本仓库基于 [build-firmware-sdk.yml](https://github.com/wuying99130/immortalwrt-NanoPi-R1S-H3/blob/feature/SDK/.github/workflows/build-firmware-sdk.yml) 工作流实现了固件与专属 SDK 的单文件一体化流水线。

## 一、 流水线架构设计与工作原理

1. **单一入口触发与参数共享 (`workflow_dispatch`)**
* 采用集中式的触发器管理，支持手动选择版本分支（`openwrt-24.10`、`openwrt-23.05`、`master`）及自定义额外的软件包。
* **运行机制**：该 `version` 参数会同时传递给两个任务，确保固件和 SDK 的源码克隆分支完全同步，避免版本不匹配。


2. **双任务串行编排 (`needs`)**
* 工作流划分为 `build-firmware`（固件编译）与 `build-sdk`（SDK 编译）两个独立 Job。
* **运行机制**：通过 `needs: build-firmware` 强制规定 SDK 任务必须等待固件编译成功后才能启动，防止高负载编译任务同时抢占云端计算资源。



---

## 二、 核心任务拆解

### 1. 固件编译任务 (`build-firmware`)

* **空间与依赖准备**：清理系统不必要的预装软件释放磁盘空间，并安装标准编译依赖项。
* **缓存加速**：通过 `actions/cache@v4` 对 `/tmp/immortalwrt/dl` 目录进行缓存，保障二次编译的稳定与下载速度。
* **源码拉取与注入**：依据输入的版本分支深度克隆官方源码至 `/tmp/immortalwrt`，并动态挂载仓库中的 `build.sh`、`.config` 及设备树补丁。
* **产出物保存**：执行编译脚本后，通过 `actions/upload-artifact@v4` 将 `/tmp/immortalwrt/bin/out/*` 目录下的升级包、刷机镜像和校验文件打包，保存至后台供专属下载。

### 2. 专属 SDK 编译任务 (`build-sdk`)

* **同源环境对齐**：检出 `feature/SDK` 分支，再次拉取与固件任务一致的版本源码，并将私有 `.config`、`dts` 目录及 `feeds.conf.default` 注入到编译目录中。
* **原生编译触发**：
```bash
./build.sh
make target/compile -j$(nproc) || true
make sdk/install -j$(nproc) || true

```


* **双重捕获机制**：自动检索官方生成的 `.tar.xz` 专属 SDK 压缩包；若未直接生成独立归档，则通过兜底策略手动打包核心工具链资产（如 `staging_dir`、`tools`、`toolchain` 等），并通过 `actions/upload-artifact@v4` 独立输出至运行后台。

---

## 三、 在此仓库分支下如何使用 SDK 编译匹配硬件核心的 ipk 文件及依赖

在成功运行工作流并在 GitHub Actions 后台下载并解压 `nanopi-r1s-h3-custom-sdk` 后，在本地 Linux 环境中按照以下步骤编译专属 ipk 插件：

1. **准备编译环境**
确保本地系统安装好构建依赖（如 `build-essential`、`libncurses5-dev`、`zlib1g-dev`、`gawk`、`git`、`unzip` 等）。
2. **解压并进入 SDK 目录**
将下载的 SDK 压缩包解压到本地并进入目录：
```bash
tar -xvf nanopi-r1s-h3-custom-sdk.tar.xz
cd openwrt-sdk-*  # 或直接进入解压后的 SDK 根目录

```


3. **配置 Feeds 源（如需引入第三方软件包）**
检查或修改 `feeds.conf.default` 文件，添加需要的软件源，然后更新并安装：
```bash
./scripts/feeds update -a
./scripts/feeds install -a

```


4. **加载硬件配置文件**
将编译固件时使用的 `.config` 文件复制到 SDK 根目录下：
```bash
cp /path/to/your/.config .config
make defconfig

```


5. **勾选需要编译的软件包**
执行菜单配置命令，在图形界面中找到想要编译的插件，将其修改为 `M`（编译为 ipk 模块）：
```bash
make menuconfig

```


6. **开始编译 ipk 及依赖**
指定编译目标包并开启多线程编译（以编译 `luci-app-example` 为例）：
```bash
make package/luci-app-example/compile V=s -j$(nproc)

```

## 四、 在 GitHub 网页端不使用本地终端，直接通过云端手动编译匹配硬件核心的 ipk 文件及依赖

如果不习惯使用本地终端，完全可以在 GitHub 网页端借助云端工作流直接完成配置、触发和编译：

调整本地配置以指定要编译的插件

在 GitHub 仓库网页端找到根目录下的 .config 文件，点击编辑图标（Edit）。

在文件中搜索或直接添加你需要的软件包配置项（例如将目标插件改为 =m 表示编译为 ipk 模块，或通过修改对应的 Makefile / 使用其他配置手段）。

确认修改无误后，点击页面下方的 Commit changes 提交保存到当前分支。

在网页端手动触发一体化工作流

点击仓库顶部的 Actions 标签页。

在左侧边栏找到并点击 编译 ImmortalWrt NanoPi R1S-H3 固件与专属 SDK 工作流。

点击页面右侧的 Run workflow 下拉按钮。

在弹出的选项中选择对应的版本分支（例如 openwrt-24.10），如果需要附加其他软件包可以在输入框中填写，最后点击绿色 Run workflow 按钮启动云端编译。

从云端后台下载编译好的 ipk 插件

等待工作流自动串行跑通（固件编译完成后会自动开始 SDK 编译）。

运行结束后，点击进入该次运行的详情页面，在下方的 Artifacts（制品）区域：

下载 nanopi-r1s-h3-custom-sdk 压缩包。

同时也能够在对应的 SDK 或编译输出目录中找到云端打包好的 .ipk 文件及相关依赖，直接下载并上传到路由器后台进行安装即可。

```


编译完成后，生成的 `.ipk` 文件会存放在 SDK 目录下的 `bin/packages/` 或 `bin/targets/sunxi/cortexa7/packages/` 路径中，直接拷到路由器上即可通过 `opkg install` 安装。
