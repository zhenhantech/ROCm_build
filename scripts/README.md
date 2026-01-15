# 编译脚本说明

**目录**: `/data/zhehan/code/0107_summary/ROCm_build/scripts/`  
**更新日期**: 2025-01-07  

---

## 📋 脚本列表

| 脚本 | 用途 | 耗时 | 难度 |
|------|------|------|------|
| [build_rocm_runtime.sh](#1-build_rocm_runtimesh) | 编译 ROCm Runtime | 2-5分钟 | ⭐⭐ |
| [build_pytorch_rocm.sh](#2-build_pytorch_rocmsh) | 编译 PyTorch | 2-4小时 | ⭐⭐⭐ |
| [install_rocm_version.sh](#3-install_rocm_versionsh) | 安装 ROCm 版本 | <1分钟 | ⭐ |
| [identify_version.sh](#4-identify_versionsh) | 识别 ROCm 版本 | <1秒 | ⭐ |

---

## 1. build_rocm_runtime.sh

### 用途
自动编译 ROCm Runtime (libhsa-runtime64.so)，支持 2MB/4MB/8MB 三个 block_size 版本。

### 使用方法

```bash
./build_rocm_runtime.sh [2mb|4mb|8mb]

# 示例
./build_rocm_runtime.sh 8mb  # 编译 8MB 版本
```

### 功能特性

- ✅ 自动修改源码 `block_size_` 参数
- ✅ 添加版本识别的 debug 输出
- ✅ 自动备份当前版本
- ✅ 并行编译（-j8）
- ✅ 编译日志保存
- ✅ 自动复制到 Docker 容器

### 输出文件

**编译产物**:
```
/data/zhehan/code/rocm6.4.3/ROCR-Runtime/build_${VERSION}mb_versioned/
└── src/libhsa-runtime64.so.1.15.0
```

**Docker 内**:
```
/opt/rocm-6.4.3/lib/libhsa-runtime64.so.1.15.0.${VERSION}mb_version_20250107
```

### 工作流程

1. 备份 Docker 内当前版本
2. 修改 `runtime/hsa-runtime/core/inc/amd_memory_region.h` 中的 `block_size_`
3. 修改 `runtime/hsa-runtime/core/runtime/amd_memory_region.cpp` 添加版本标识
4. 创建/使用构建目录
5. 清理并重新编译
6. 复制到 Docker 容器

### 依赖

- 已存在的 `build_8mb` 目录作为模板
- Docker 容器 `sglang_zhendebug4` 运行中
- `/opt/cmake-3.26.4/bin/cmake` 可用

### 常见问题

**Q: 找不到 build_8mb 模板目录**
```bash
# 先手动编译一次 8MB 版本作为模板
cd /data2/code/rocm6.4.3/ROCR-Runtime
mkdir build_8mb && cd build_8mb
cmake ..
make -j8
```

**Q: cmake 路径错误**
```bash
# 脚本会自动修复 Makefile 中的 cmake 路径
# 如果仍有问题，手动设置：
export CMAKE_BIN=/opt/cmake-3.26.4/bin/cmake
```

---

## 2. build_pytorch_rocm.sh

### 用途
编译 PyTorch ROCm 版本，支持三种编译模式。

### 使用方法

```bash
./build_pytorch_rocm.sh [develop|wheel|so_only]

# 示例
./build_pytorch_rocm.sh wheel      # 生成 wheel 包（推荐）
./build_pytorch_rocm.sh develop    # 开发模式（快速）
./build_pytorch_rocm.sh so_only    # 仅编译 .so（最快）
```

### 编译模式对比

| 模式 | 耗时 | 产物 | 适用场景 |
|------|------|------|---------|
| **develop** | 30-60分钟 | 安装到 Python 环境 | 快速测试 |
| **wheel** | 2-4小时 | .whl 文件 | 生产部署 |
| **so_only** | 10-20分钟 | .so 文件 | 快速迭代 |

### 功能特性

- ✅ 自动检查 ROCm 环境
- ✅ 自动检查 Python 依赖
- ✅ 设置编译环境变量
- ✅ 备份源码修改
- ✅ 清理旧构建（可选）
- ✅ 编译验证
- ✅ 彩色输出

### 输出文件

**wheel 模式**:
```
/data/zhehan/code/script/source_backWA_docker2/1216_pytorch_build/torch-*.whl
```

**develop 模式**:
直接安装到 Python 环境

**so_only 模式**:
```
/data/zhehan/code/script/source_backWA_docker2/1216_pytorch_build/libc10_hip.so
```

### 环境变量

脚本自动设置的关键环境变量：
```bash
USE_ROCM=1
USE_CUDA=0
PYTORCH_ROCM_ARCH="gfx90a;gfx942"
MAX_JOBS=$(nproc)
BUILD_TEST=0
USE_MKLDNN=1
USE_DISTRIBUTED=1
USE_RCCL=1
```

### 工作流程

1. 检查 ROCm 环境（hipcc, ROCM_PATH）
2. 检查 Python 和依赖
3. 设置环境变量
4. 备份当前修改
5. 清理旧构建（询问）
6. 根据模式编译
7. 验证编译结果
8. 显示摘要

### 常见问题

**Q: 找不到 hipcc**
```bash
# 确认 ROCm 已安装
which hipcc
export PATH=/opt/rocm/bin:$PATH
```

**Q: Python 依赖缺失**
```bash
pip install numpy pyyaml typing_extensions
```

**Q: 内存不足**
```bash
# 编辑脚本，减少 MAX_JOBS
export MAX_JOBS=2
```

---

## 3. install_rocm_version.sh

### 用途
安装指定版本的 ROCm Runtime 到 Docker 容器。

### 使用方法

```bash
./install_rocm_version.sh <container_name> <version>

# 示例
./install_rocm_version.sh sglang_zhendebug4 8mb
./install_rocm_version.sh sglang_zhendebug3 2mb
```

### 支持的版本

- `2mb` - 2MB block_size 版本
- `4mb` - 4MB block_size 版本
- `8mb` - 8MB block_size 版本

### 功能特性

- ✅ 自动查找源文件（多个位置）
- ✅ 自动备份当前版本
- ✅ 更新符号链接
- ✅ 清理 Python 缓存
- ✅ 验证安装
- ✅ 彩色输出

### 源文件查找顺序

1. `/data/zhehan/code/debug_summary/rocmdebugSO/` （优先）
2. Docker 内已部署版本
3. Docker 内源码编译目录
4. cleanup 目录
5. 旧的备份目录

### 备份位置

```
/data/zhehan/code/pagefault_WA_8Mblocksize/backup/
└── backup_${CONTAINER}_${VERSION}_${TIMESTAMP}/
    ├── libhsa-runtime64.so.1.15.0.current
    └── info.txt
```

### 工作流程

1. 验证容器运行状态
2. 查找源文件
3. 备份当前版本
4. 复制新版本到容器
5. 更新符号链接
6. 清理 Python 缓存
7. 验证安装

### 重要提示

⚠️ **安装后必须重启容器才能生效**:
```bash
docker restart <container_name>
```

### 验证安装

```bash
# 使用 identify_version.sh 验证
./identify_version.sh <container_name>

# 或手动验证
docker exec <container_name> python3 -c 'import torch; torch.zeros(1).cuda()' 2>&1 | grep "version-block_size"
```

---

## 4. identify_version.sh

### 用途
识别 ROCm Runtime 文件的版本（通过 MD5 哈希值）。

### 使用方法

```bash
# 识别本地文件
./identify_version.sh <file_path>

# 识别容器内文件（默认路径）
./identify_version.sh <container_name>

# 识别容器内文件（指定路径）
./identify_version.sh <container_name> <file_path>
```

### 示例

```bash
# 识别本地文件
./identify_version.sh /data/zhehan/code/debug_summary/rocmdebugSO/libhsa-runtime64.so.1.15.0.8mb_20251127

# 识别容器内当前版本
./identify_version.sh sglang_zhendebug4

# 识别容器内指定文件
./identify_version.sh sglang_zhendebug4 /opt/rocm/lib/libhsa-runtime64.so.1.15.0
```

### 已知版本 MD5

```
bd5d6f367a568e2f6a8a971d3b96dc7f  - 2MB 版本
8d0bcf473327a6c5865680fc9b53ec7d  - 4MB 版本
c1e6741fab9fb8b351a7f595f535ec1f  - 8MB 版本（新）
2cf3ff968a46d99064080ef052ece6fb  - 8MB 版本（旧）
```

### 输出信息

```
ROCm Runtime 版本识别
====================================

文件: libhsa-runtime64.so.1.15.0
MD5:  c1e6741fab9fb8b351a7f595f535ec1f
大小: 4.0M

检测到: 8MB 版本
block_size: 8MB
支持splits: <=63

建议: ✅ 推荐用于生产环境（修复 BS=64 pagefault）
```

### 识别方法

1. **MD5 匹配**（最准确）- 通过文件哈希值精确匹配
2. **文件大小推测**（备用）- 当 MD5 未知时，根据文件大小推测

---

## 🔧 脚本维护

### 更新源文件位置

如果源文件位置改变，需要更新 `install_rocm_version.sh` 中的查找路径：

```bash
# 编辑脚本
vi install_rocm_version.sh

# 修改 SEARCH_PATHS 数组
SEARCH_PATHS=(
    "/data/zhehan/code/debug_summary/rocmdebugSO"
    "/new/path/to/files"
    # ... 其他路径 ...
)
```

### 添加新的 MD5 签名

如果编译了新版本，需要更新 `identify_version.sh`：

```bash
# 1. 计算新版本的 MD5
md5sum libhsa-runtime64.so.1.15.0.new_version

# 2. 编辑 identify_version.sh
vi identify_version.sh

# 3. 在 identify_by_md5() 函数中添加：
case "$MD5" in
    "YOUR_NEW_MD5")
        VERSION="New Version"
        BLOCKSIZE="XMB"
        ;;
```

---

## 📚 使用示例

### 完整工作流：编译 → 安装 → 验证

```bash
#!/bin/bash
# 完整工作流示例

cd /data/zhehan/code/0107_summary/ROCm_build/scripts

# 1. 编译 8MB 版本
echo "=== 步骤1: 编译 8MB 版本 ==="
./build_rocm_runtime.sh 8mb

# 2. 安装到容器
echo "=== 步骤2: 安装到容器 ==="
./install_rocm_version.sh sglang_zhendebug4 8mb

# 3. 重启容器
echo "=== 步骤3: 重启容器 ==="
docker restart sglang_zhendebug4
sleep 10

# 4. 验证版本
echo "=== 步骤4: 验证版本 ==="
./identify_version.sh sglang_zhendebug4

# 5. 测试运行
echo "=== 步骤5: 测试运行 ==="
docker exec sglang_zhendebug4 python3 -c 'import torch; torch.zeros(1).cuda()' 2>&1 | grep "version-block_size"

echo "✅ 完成！"
```

---

## ⚠️ 注意事项

1. **备份重要**: 安装前会自动备份，但建议手动额外备份
2. **容器重启**: 安装后必须重启容器
3. **版本验证**: 安装后务必验证版本
4. **路径一致**: 注意 Docker 内外路径映射
5. **权限问题**: 某些操作可能需要 sudo

---

## 🐛 故障排查

### 脚本执行失败

```bash
# 检查脚本权限
ls -l *.sh

# 添加执行权限
chmod +x *.sh

# 查看错误日志
./script.sh 2>&1 | tee error.log
```

### Docker 相关问题

```bash
# 检查容器状态
docker ps -a | grep sglang_zhendebug

# 检查容器日志
docker logs sglang_zhendebug4 | tail -20

# 进入容器调试
docker exec -it sglang_zhendebug4 bash
```

---

**脚本来源**: 多个项目整合  
**维护者**: AI Assistant  
**最后更新**: 2025-01-07

