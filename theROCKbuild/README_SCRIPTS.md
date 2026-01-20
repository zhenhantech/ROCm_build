# ROCm 构建脚本使用指南

本目录包含用于构建和打包 ROCm 的脚本工具。

## 文件说明

### 文档
- **BUILD_SUMMARY.md** - 详细的构建总结，包含所有遇到的问题和解决方案
- **finished_steps.txt** - 完整的构建步骤记录
- **README_SCRIPTS.md** - 本文件，脚本使用指南

### 构建脚本
- **build_all.sh** - 编译全部 ROCm 组件
- **build_component.sh** - 编译指定的单个 ROCm 组件

### 打包脚本
- **package_deb.sh** - 打包为 Debian/Ubuntu .deb 包
- **package_rpm.sh** - 打包为 RedHat/CentOS .rpm 包

---

## 快速开始

### 1. 编译全部组件

```bash
# 使用默认配置（所有CPU核心）
./build_all.sh

# 指定并行任务数
./build_all.sh -j 32

# 清理后重新编译
./build_all.sh -c

# 遇到错误时继续编译
./build_all.sh -k

# 显示详细输出
./build_all.sh -v
```

### 2. 编译单个组件

```bash
# 编译 rocBLAS
./build_component.sh rocBLAS

# 编译 hipBLAS，使用 32 个并行任务
./build_component.sh hipBLAS -j 32

# 清理后重新编译 rocSPARSE
./build_component.sh rocSPARSE -c

# 编译 MIOpen，遇到错误时继续
./build_component.sh MIOpen -k
```

支持的组件名称：
- 数学库: `rocBLAS`, `hipBLAS`, `hipBLASLt`, `rocSPARSE`, `hipSPARSE`, `hipSPARSELt`, `rocSOLVER`, `hipSOLVER`, `rocFFT`, `hipFFT`, `rocRAND`, `hipRAND`
- 深度学习: `MIOpen`, `hipDNN`
- 通信: `rccl`
- 其他: `rocprofiler`, `roctracer`, `rocm-smi`

### 3. 打包为 Debian/Ubuntu 包

```bash
# 使用默认配置
./package_deb.sh

# 指定版本号和输出目录
./package_deb.sh -v 7.2.0 -o /tmp/rocm-deb

# 指定架构
./package_deb.sh -a arm64
```

生成的 .deb 包将位于 `./packages/deb/` 目录。

安装：
```bash
sudo dpkg -i packages/deb/rocm_7.2.0_amd64.deb
```

### 4. 打包为 RedHat/CentOS 包

```bash
# 使用默认配置
./package_rpm.sh

# 指定版本号和发布版本
./package_rpm.sh -v 7.2.0 -r 2

# 指定架构
./package_rpm.sh -a aarch64
```

生成的 .rpm 包将位于 `./packages/rpm/` 目录。

安装：
```bash
sudo rpm -ivh packages/rpm/rocm-7.2.0-1.x86_64.rpm
```

---

## 环境变量

所有脚本支持以下环境变量：

- **ROCK_DIR** - TheRock 源码目录（默认: `/data/TheRock`）
- **AMDGPU_TARGETS** - GPU 目标架构（默认: `gfx942`）
- **AMDGPU_FAMILIES** - GPU 架构族（默认: `gfx94X-dcgpu`）
- **AMDGPU_DIST_BUNDLE** - 分发包名称（默认: `gfx94X-dcgpu`）

示例：
```bash
export ROCK_DIR=/path/to/TheRock
export AMDGPU_TARGETS=gfx942
./build_all.sh
```

---

## 常见问题

### Q: 脚本提示找不到 TheRock 目录？
A: 设置 `ROCK_DIR` 环境变量或确保 `/data/TheRock` 目录存在。

### Q: 编译失败怎么办？
A: 
1. 检查错误日志：`tail -f build/logs/*.log`
2. 使用 `-k` 选项继续编译其他组件
3. 查看 `BUILD_SUMMARY.md` 了解常见问题和解决方案

### Q: 如何加速编译？
A:
1. 安装并使用 ccache：`sudo apt install ccache`
2. 增加并行任务数：`./build_all.sh -j $(nproc)`
3. 后续构建会利用 ccache 缓存

### Q: 打包失败？
A:
- Debian/Ubuntu: 确保安装了 `dpkg-dev`：`sudo apt install dpkg-dev`
- RedHat/CentOS: 确保安装了 `rpm-build`：`sudo yum install rpm-build`

---

## 详细文档

更多详细信息请参考：
- **BUILD_SUMMARY.md** - 完整的构建总结和问题解决方案
- **finished_steps.txt** - 详细的构建步骤

---

## 注意事项

1. **首次构建需要很长时间**（数小时），请耐心等待
2. **确保有足够的磁盘空间**（建议至少 50GB）
3. **建议在 Docker 容器中构建**以避免污染系统环境
4. **所有脚本都需要在 TheRock 源码目录的父目录运行**，或设置正确的 `ROCK_DIR`

---

**最后更新**: 2025年1月

