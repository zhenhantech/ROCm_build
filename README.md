# ROCm 编译总结与归档

**归档日期**: 2025-01-07  
**内容来源**: `/data/zhehan/code/debug_summary`, `/data/zhehan/code/script/source_backWA_docker2`  
**状态**: ✅ 完整归档  

---

## 📋 目录

1. [编译问题与解决方案](#编译问题与解决方案)
2. [编译流程指南](#编译流程指南)
3. [编译脚本说明](#编译脚本说明)
4. [文件索引](#文件索引)
5. [快速参考](#快速参考)

---

## 📚 文档清单

| 文档 | 用途 | 状态 |
|------|------|------|
| [README.md](README.md) | 本文档，总索引 | ✅ |
| [COMPILATION_ISSUES.md](COMPILATION_ISSUES.md) | 编译遇到的主要问题及解决方案 | ✅ |
| [COMPILATION_GUIDE.md](COMPILATION_GUIDE.md) | 完整编译指南 | ✅ |
| [BUILD_SCRIPTS.md](BUILD_SCRIPTS.md) | 编译脚本说明与使用 | ✅ |
| [PYTORCH_BUILD.md](PYTORCH_BUILD.md) | PyTorch 编译专题 | ✅ |

### 编译脚本

| 脚本 | 用途 | 位置 |
|------|------|------|
| `build_rocm_runtime.sh` | ROCm Runtime 编译脚本 | [scripts/](scripts/) |
| `build_pytorch_rocm.sh` | PyTorch ROCm 编译脚本 | [scripts/](scripts/) |
| `install_rocm_version.sh` | ROCm 版本安装脚本 | [scripts/](scripts/) |
| `identify_version.sh` | 版本识别脚本 | [scripts/](scripts/) |

---

## 编译问题与解决方案

我们在 ROCm 编译过程中遇到了以下主要问题：

### 1. ⚠️ LLVM 工具链缺失问题

**问题描述**:
```
CMake Error: No rule to make target '/opt/rocm-6.4.3/lib/llvm/bin/clang-19'
```

**根本原因**: 
- GPU kernel 编译需要 ROCm 的 LLVM 工具链（clang-19）
- 某些容器环境缺少完整的 LLVM 工具

**解决方案**:
- ✅ **方案A**: 使用包含完整工具链的 Docker 容器（推荐）
  - 如 `sglang_zhendebug2_8MB` 类型容器
  - 包含完整 LLVM, clang-19, llvm-objcopy 等

- ✅ **方案B**: 创建软链接到系统 clang
  ```bash
  mkdir -p /opt/rocm-6.4.3/lib/llvm/bin
  ln -s /usr/bin/clang-14 /opt/rocm-6.4.3/lib/llvm/bin/clang-19
  ln -s /usr/bin/llvm-objcopy /opt/rocm-6.4.3/lib/llvm/bin/llvm-objcopy
  ```

- ✅ **方案C**: 从成功的构建复制预编译的 GPU kernels
  ```bash
  cp -r /path/to/successful_build/runtime/hsa-runtime/core/runtime/trap_handler/*.hsaco \
        build_dir/runtime/hsa-runtime/core/runtime/trap_handler/
  ```

详见: [COMPILATION_ISSUES.md](COMPILATION_ISSUES.md#llvm工具链缺失)

---

### 2. ⚠️ 符号导出问题

**问题描述**:
```
ImportError: undefined symbol: hsaKmtCreateQueueExt
ImportError: undefined symbol: hsaKmtRegisterGraphicsHandleToNodesExt
```

**根本原因**:
- libhsakmt.so 的版本脚本 (`libhsakmt/src/libhsakmt.ver`) 缺少某些 `Ext` 后缀的符号
- 虽然函数编译了，但没有导出为公开符号

**解决方案**:
修改 `libhsakmt/src/libhsakmt.ver`，添加以下符号：
```
hsaKmtCreateQueueExt;
hsaKmtRegisterGraphicsHandleToNodesExt;
hsaKmtWaitOnEvent_Ext;
hsaKmtWaitOnMultipleEvents_Ext;
```

重新编译：
```bash
cd build_dir
rm -f libhsakmt/lib/libhsakmt.so*
make -j8 hsakmt
```

验证：
```bash
nm -D libhsakmt.so.1.0.6 | grep 'Ext.*@@'
```

详见: [COMPILATION_ISSUES.md](COMPILATION_ISSUES.md#符号导出问题)

---

### 3. ⚠️ GPU 着色器编译失败

**问题描述**:
```
clang: error: cannot find ROCm device library
clang: error: invalid target ID 'gfx940'
```

**根本原因**:
- 缺少 ROCm device libraries
- LLVM 版本不匹配

**解决方案**:
```bash
# 1. 确认 device libraries 存在
ls /opt/rocm-6.4.3/amdgcn/bitcode/

# 2. 设置环境变量
export ROCM_PATH=/opt/rocm-6.4.3
export DEVICE_LIB_PATH=/opt/rocm-6.4.3/amdgcn/bitcode

# 3. 重新运行 cmake
```

详见: [COMPILATION_ISSUES.md](COMPILATION_ISSUES.md#gpu着色器编译失败)

---

### 4. ⚠️ PyTorch 源码文件缺失

**问题描述**:
```
CMake Error: File /workspace/pytorch_new/c10/hip/impl/hip_cmake_macros.h.in does not exist.
CMake Error: File /workspace/pytorch_new/aten/src/ATen/hip/HIPConfig.h.in does not exist.
```

**根本原因**:
- 源码不完整
- 清理过度导致文件丢失
- 版本不匹配

**解决方案**:
```bash
# 检查源码完整性
cd /workspace/pytorch_new
git status
git checkout -- .  # 恢复被删除的文件

# 或重新克隆源码
```

详见: [PYTORCH_BUILD.md](PYTORCH_BUILD.md#常见问题)

---

### 5. ⚠️ 编译内存不足

**问题描述**:
```
c++: fatal error: Killed signal terminated program cc1plus
```

**解决方案**:
```bash
# 减少并行编译数
make -j2 hsa-runtime64  # 而不是 -j8

# 或者增加 swap 空间
```

---

## 编译流程指南

### ROCm Runtime 编译

完整流程请参见: [COMPILATION_GUIDE.md](COMPILATION_GUIDE.md)

**快速开始**:

1. **准备环境**
   ```bash
   # 使用包含完整工具链的容器
   docker exec -it sglang_zhendebug2_8MB bash
   ```

2. **配置和编译**
   ```bash
   cd /data2/code/rocm6.4.3/ROCR-Runtime
   mkdir build_2mb_patched && cd build_2mb_patched
   
   /opt/cmake-3.26.4/bin/cmake .. \
     -DCMAKE_BUILD_TYPE=Release \
     -DCMAKE_INSTALL_PREFIX=/opt/rocm-6.4.3 \
     -DBUILD_SHARED_LIBS=ON
   
   make -j8 hsakmt
   make -j8 hsa-runtime64
   ```

3. **验证和部署**
   ```bash
   ls -lh rocr/lib/libhsa-runtime64.so.1.15.0
   cp rocr/lib/libhsa-runtime64.so.1.15.0 \
      /data2/code/debug_summary/rocmdebugSO/
   ```

**编译时间**: ~2-5 分钟（根据并行度）  
**最终产物**: 
- `libhsa-runtime64.so.1.15.0` (3.7-3.9 MB)
- `libhsakmt.so.1.0.6` (211 KB)

---

### PyTorch 编译

完整流程请参见: [PYTORCH_BUILD.md](PYTORCH_BUILD.md)

**快速开始**:

```bash
# 使用编译脚本
cd /data/zhehan/code/0107_summary/ROCm_build/scripts
./build_pytorch_rocm.sh wheel
```

**编译时间**: 2-4 小时  
**编译产物**: `torch-2.7.1a0+gite2d141d-*.whl`

---

## 编译脚本说明

### 1. build_rocm_runtime.sh

**用途**: 自动编译 ROCm Runtime (libhsa-runtime64.so)

**特性**:
- ✅ 支持 2MB/4MB/8MB 三个版本
- ✅ 自动修改源码 block_size
- ✅ 添加版本识别 debug 输出
- ✅ 自动备份
- ✅ 验证编译结果

**使用方法**:
```bash
cd scripts
./build_rocm_runtime.sh [2mb|4mb|8mb]
```

详见: [BUILD_SCRIPTS.md](BUILD_SCRIPTS.md#build-rocm-runtime)

---

### 2. build_pytorch_rocm.sh

**用途**: 编译 PyTorch ROCm 版本

**特性**:
- ✅ 支持三种编译模式（develop/wheel/so_only）
- ✅ 自动环境检查
- ✅ 自动备份修改
- ✅ 编译验证

**使用方法**:
```bash
cd scripts
./build_pytorch_rocm.sh [develop|wheel|so_only]
```

详见: [BUILD_SCRIPTS.md](BUILD_SCRIPTS.md#build-pytorch-rocm)

---

### 3. install_rocm_version.sh

**用途**: 安装指定版本的 ROCm Runtime 到容器

**特性**:
- ✅ 智能源文件查找
- ✅ 自动备份当前版本
- ✅ 更新符号链接
- ✅ 验证安装

**使用方法**:
```bash
cd scripts
./install_rocm_version.sh <container_name> <version>

# 示例
./install_rocm_version.sh sglang_zhendebug4 8mb
```

详见: [BUILD_SCRIPTS.md](BUILD_SCRIPTS.md#install-rocm-version)

---

## 文件索引

### 编译产物位置

#### ROCm Runtime

**源码位置**:
```
容器内: /data2/code/rocm6.4.3/ROCR-Runtime
宿主机: /data/zhehan/code/rocm6.4.3/ROCR-Runtime
```

**编译产物**:
```
build_2mb_patched/
├── libhsakmt/lib/libhsakmt.so.1.0.6 (211KB)
└── rocr/lib/libhsa-runtime64.so.1.15.0 (3.7-3.9MB)
```

**备份位置**:
```
宿主机: /data/zhehan/code/debug_summary/rocmdebugSO/
├── libhsa-runtime64.so.1.15.0.2mb_20251127
├── libhsa-runtime64.so.1.15.0.4mb_20251127
├── libhsa-runtime64.so.1.15.0.8mb_20251127
└── libhsa-runtime64.so.1.15.0.2mb_patched_guard_FIXED_20251201_154846
```

**安装位置**:
```
容器内: /opt/rocm-6.4.3/lib/
└── libhsa-runtime64.so.1.15.0
```

---

#### PyTorch

**源码位置**:
```
/data/zhehan/code/pytorch
```

**编译产物**:
```
/data/zhehan/code/script/source_backWA_docker2/1216_pytorch_build/
├── torch-2.7.1a0+gite2d141d.no2mbpatch-cp312-cp312-linux_x86_64.whl
├── torch-no_2MB_patch-2.7.1a0+gite2d141d-cp312-cp312-linux_x86_64.whl
└── torch_no_2mb_patch-2.7.1a0+gite2d141d-cp312-cp312-linux_x86_64.whl
```

---

## 快速参考

### 常用命令

#### 查看当前版本
```bash
# 通过 debug 输出识别
docker exec sglang_zhendebug4 python3 -c 'import torch; torch.zeros(1).cuda()' 2>&1 | grep "version-block_size"

# 通过 MD5 识别
cd scripts
./identify_version.sh sglang_zhendebug4
```

#### 切换版本
```bash
# 方法1: 使用脚本（推荐）
cd scripts
./install_rocm_version.sh sglang_zhendebug4 8mb

# 方法2: 手动切换
docker exec sglang_zhendebug4 \
  cp /opt/rocm/lib/libhsa-runtime64.so.1.15.0.8mb_20251127 \
     /opt/rocm/lib/libhsa-runtime64.so.1.15.0

# 重启容器
docker restart sglang_zhendebug4
```

#### 编译新版本
```bash
# ROCm Runtime
cd scripts
./build_rocm_runtime.sh 8mb

# PyTorch
cd scripts
./build_pytorch_rocm.sh wheel
```

---

## 版本对比

### ROCm Runtime 版本

| 版本 | block_size | BS=64 结果 | 文件大小 | 用途 |
|------|-----------|-----------|---------|------|
| 2MB | 2MB | ❌ Pagefault | 3.8-4.0M | 复现问题 |
| 4MB | 4MB | ⏳ 未测试 | 3.8-4.0M | 找临界点 |
| 8MB | 8MB | ✅ 成功 | 3.8-4.0M | 生产环境 |
| 2MB+Guard | 2MB+Guard Pages | ✅ 成功 | 3.8M | 最优方案 |

### PyTorch 版本

| 版本 | 2MB Patch | 编译模式 | 文件大小 | 状态 |
|------|-----------|---------|---------|------|
| 2.7.1a0+gite2d141d | ❌ 无 | Release | ~1GB | ✅ 已编译 |
| 2.10.0a0+git1c23a67 | ❌ 无 | Release | 失败 | ❌ 配置错误 |

---

## 关键发现

### 1. ✅ Guard Pages 是最优方案

**对比**:
- **8MB block_size**: 解决问题但浪费内存（每次分配额外 6MB）
- **2MB + Guard Pages**: 既解决问题又不浪费内存
  - Block size 保持 2MB
  - Permission 范围扩展到 10MB
  - 覆盖 hardware prefetch 范围

**实现**: 已在 `libhsa-runtime64.so.1.15.0.2mb_patched_guard_FIXED_20251201_154846` 中

---

### 2. ✅ 容器环境是编译关键

**成功要素**:
- 完整的 LLVM 工具链（clang-19）
- ROCm device libraries
- 正确的 CMake 版本（3.26.4+）

**推荐容器**: `sglang_zhendebug2_8MB`

---

### 3. ✅ 符号导出必须显式声明

libhsakmt.so 的符号必须在版本脚本中明确列出，否则即使编译了也不会导出。

---

## 最佳实践

### 编译前
- [ ] 检查工具链完整性
- [ ] 确认源码和 patch 正确
- [ ] 清理旧的构建目录
- [ ] 准备足够的磁盘空间（5GB+）

### 编译中
- [ ] 使用 `-j8` 并行编译
- [ ] 保存编译日志 (`tee`)
- [ ] 监控编译进度和错误

### 编译后
- [ ] 验证文件大小和类型
- [ ] 检查依赖关系 (`ldd`)
- [ ] 验证符号表 (`nm`)
- [ ] 测试基本功能
- [ ] 备份到部署目录（带时间戳）

---

## 相关文档链接

### 原始文档位置
- `/data/zhehan/code/debug_summary/ROCR_COMPILATION_GUIDE.md`
- `/data/zhehan/code/debug_summary/06_COMPILATION_COMPLETE.md`
- `/data/zhehan/code/debug_summary/COMPILATION_RECORD_20251201.md`
- `/data/zhehan/code/cursor_chat_backup_md/20251226_PyTorch_CUDA_SGLang.md`

### 编译脚本位置
- `/data/zhehan/code/script/source_backWA_docker2/1127_hipalloc_issue_cleanup/scripts/`
- `/data/zhehan/code/script/source_backWA_docker2/1216_pytorch_build/`
- `/data/zhehan/code/debug_summary/scripts/`

---

## 总结

✅ **编译任务完成情况**:
- ROCm Runtime: ✅ 100% 完成（2MB/4MB/8MB/2MB+Guard）
- PyTorch: ✅ 部分完成（no-2MB-patch 版本成功）
- 编译脚本: ✅ 齐全且经过验证
- 文档: ✅ 完整归档

✅ **关键成果**:
- Guard Pages Patch 版本（最优方案）
- 多版本 ROCm Runtime 可切换
- 完整的编译脚本和文档
- 丰富的故障排查经验

---

**归档完成时间**: 2025-01-07  
**文档维护**: AI Assistant  
**状态**: ✅ 完整归档，可直接使用

