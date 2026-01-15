# ROCm 编译问题与解决方案汇总

**文档日期**: 2025-01-07  
**总结人**: AI Assistant  
**来源**: 实际编译过程中遇到的所有问题  

---

## 📋 问题清单

| 问题 | 严重程度 | 频率 | 解决难度 |
|------|----------|------|---------|
| [LLVM 工具链缺失](#1-llvm-工具链缺失) | 🔴 高 | 频繁 | 中等 |
| [符号导出问题](#2-符号导出问题) | 🔴 高 | 偶尔 | 容易 |
| [GPU 着色器编译失败](#3-gpu-着色器编译失败) | 🟡 中 | 偶尔 | 中等 |
| [源码文件缺失](#4-源码文件缺失) | 🟡 中 | 偶尔 | 容易 |
| [内存不足](#5-内存不足) | 🟡 中 | 罕见 | 容易 |
| [CMake 版本问题](#6-cmake-版本问题) | 🟢 低 | 罕见 | 容易 |
| [路径问题](#7-docker-路径问题) | 🟢 低 | 偶尔 | 容易 |
| [依赖库缺失](#8-依赖库缺失) | 🟡 中 | 罕见 | 中等 |

---

## 1. LLVM 工具链缺失

### 问题描述

**错误信息**:
```
CMake Error at runtime/hsa-runtime/core/runtime/CMakeLists.txt:XXX (add_custom_command):
  No rule to make target '/opt/rocm-6.4.3/lib/llvm/bin/clang-19', needed by 
  'runtime/hsa-runtime/core/runtime/trap_handler/trap_handler_v2.hsaco'.
  Stop.
```

或者:
```
CMake Error: The following variables are used in this project, but they are set to NOTFOUND.
Please set them or make sure they are set and tested correctly in the CMake files:
CLANG_OFFLOAD_BUNDLER
    linked by target "trap_handler_v2" in directory ...
```

### 根本原因

ROCm Runtime 编译过程需要：
1. **clang-19** (或兼容版本) - 编译 GPU kernels
2. **llvm-objcopy** - 处理 GPU 二进制文件
3. **clang-offload-bundler** - 打包 GPU 代码

这些工具是 ROCm LLVM 工具链的一部分，某些容器环境可能缺失。

### 影响范围

**受影响的编译阶段**:
- ✅ CMake 配置: 通过（可能有警告）
- ❌ GPU trap handler 编译: **失败**
- ❌ GPU blit shaders 编译: **失败**
- ✅ C/C++ 源码编译: 通过

**编译会停在**:
```
[ 15%] Building trap_handler_v2.hsaco
make[2]: *** No rule to make target '/opt/rocm-6.4.3/lib/llvm/bin/clang-19'
make[1]: *** [CMakeFiles/Makefile2:XXX: runtime/hsa-runtime/...] Error 2
make: *** [Makefile:146: all] Error 2
```

### 解决方案

#### 方案A: 使用完整环境的容器 ⭐ 推荐

**最佳选择**: 使用包含完整 ROCm 开发环境的容器

```bash
# 推荐的容器类型
docker exec -it sglang_zhendebug2_8MB bash

# 验证工具链
find /opt/rocm*/lib/llvm/bin -name 'clang*' -type f | head -3
find /opt/rocm*/lib/llvm/bin -name 'llvm-objcopy' -type f
```

**这类容器包含**:
- ✅ clang-19 (或 clang-17)
- ✅ llvm-objcopy
- ✅ clang-offload-bundler
- ✅ ROCm device libraries
- ✅ 所有依赖库

---

#### 方案B: 创建软链接

**适用场景**: 系统有 clang，但路径不匹配

```bash
#!/bin/bash
# fix_llvm_links.sh

ROCM_LLVM_BIN="/opt/rocm-6.4.3/lib/llvm/bin"
mkdir -p "$ROCM_LLVM_BIN"

# 创建链接
ln -sf /usr/bin/clang-14 "$ROCM_LLVM_BIN/clang-19"
ln -sf /usr/bin/clang-14 "$ROCM_LLVM_BIN/clang"
ln -sf /usr/bin/llvm-objcopy "$ROCM_LLVM_BIN/llvm-objcopy"
ln -sf /usr/bin/llvm-ar "$ROCM_LLVM_BIN/llvm-ar"

echo "✅ 软链接创建完成"
ls -l "$ROCM_LLVM_BIN/"
```

**注意**:
- ⚠️ clang-14 可能不完全兼容 ROCm 6.4.3
- ⚠️ GPU kernel 编译可能失败或产生不兼容的代码
- ⚠️ 仅作为临时解决方案

---

#### 方案C: 使用预编译的 GPU Kernels

**适用场景**: 只需重新编译 C/C++ 部分，GPU kernel 不需要修改

```bash
#!/bin/bash
# copy_prebuilt_kernels.sh

SOURCE_BUILD="/data2/code/rocm6.4.3/ROCR-Runtime/build_8mb"
TARGET_BUILD="/data2/code/rocm6.4.3/ROCR-Runtime/build_new"

# 复制 trap handlers
mkdir -p "$TARGET_BUILD/runtime/hsa-runtime/core/runtime/trap_handler"
cp -r "$SOURCE_BUILD/runtime/hsa-runtime/core/runtime/trap_handler"/*.hsaco \
      "$TARGET_BUILD/runtime/hsa-runtime/core/runtime/trap_handler/"

# 复制 blit shaders
mkdir -p "$TARGET_BUILD/runtime/hsa-runtime/core/runtime/blit_shaders"
cp -r "$SOURCE_BUILD/runtime/hsa-runtime/core/runtime/blit_shaders"/*.hsaco \
      "$TARGET_BUILD/runtime/hsa-runtime/core/runtime/blit_shaders/"

# 复制 OpenCL blit objects
mkdir -p "$TARGET_BUILD/runtime/hsa-runtime/core/runtime/blit_kernel"
cp -r "$SOURCE_BUILD/runtime/hsa-runtime/core/runtime/blit_kernel"/*.o \
      "$TARGET_BUILD/runtime/hsa-runtime/core/runtime/blit_kernel/"

echo "✅ GPU kernels 复制完成"
```

**优点**:
- ✅ 避免 GPU kernel 编译
- ✅ 编译速度快

**缺点**:
- ⚠️ 需要有已成功编译的版本
- ⚠️ GPU kernel 版本可能不匹配
- ⚠️ 不适用于修改了 GPU kernel 的情况

---

### 验证解决

```bash
# 检查工具是否存在
which clang-19 || ls /opt/rocm*/lib/llvm/bin/clang*
which llvm-objcopy || ls /opt/rocm*/lib/llvm/bin/llvm-objcopy

# 测试工具
/opt/rocm-6.4.3/lib/llvm/bin/clang-19 --version
/opt/rocm-6.4.3/lib/llvm/bin/llvm-objcopy --version

# 重新运行 cmake
cd build_dir
rm CMakeCache.txt
/opt/cmake-3.26.4/bin/cmake ..

# 查看是否找到工具
grep -E "clang|LLVM" CMakeCache.txt
```

---

## 2. 符号导出问题

### 问题描述

**错误信息**:
```python
>>> import torch
Traceback (most recent call last):
  File "<stdin>", line 1, in <module>
ImportError: /opt/rocm-6.4.3/lib/libhsa-runtime64.so.1: undefined symbol: hsaKmtCreateQueueExt
```

或者:
```
undefined symbol: hsaKmtRegisterGraphicsHandleToNodesExt
undefined symbol: hsaKmtWaitOnEvent_Ext
undefined symbol: hsaKmtWaitOnMultipleEvents_Ext
```

### 根本原因

libhsakmt.so 使用版本脚本 (`libhsakmt/src/libhsakmt.ver`) 控制符号导出：

```bash
# libhsakmt.ver 结构
HSAKMT_1 {
  global:
    hsaKmtOpenKFD;
    hsaKmtCloseKFD;
    hsaKmtCreateQueue;
    # ... 其他符号 ...
  local:
    *;  # 所有其他符号默认不导出
};
```

如果函数没有在 `global:` 部分列出，即使编译了也不会导出为公开符号。

### 检查方法

```bash
# 检查导出的符号
nm -D libhsakmt.so.1.0.6 | grep 'Ext'

# 如果为空，说明符号未导出

# 检查符号是否存在于库中（但未导出）
nm libhsakmt.so.1.0.6 | grep 'hsaKmtCreateQueueExt'
```

### 解决方案

#### 步骤1: 修改版本脚本

编辑 `libhsakmt/src/libhsakmt.ver`：

```bash
vi /data2/code/rocm6.4.3/ROCR-Runtime/libhsakmt/src/libhsakmt.ver
```

在 `global:` 部分添加缺失的符号：

```diff
 HSAKMT_1 {
   global:
     hsaKmtOpenKFD;
     hsaKmtCloseKFD;
     hsaKmtCreateQueue;
+    hsaKmtCreateQueueExt;
+    hsaKmtRegisterGraphicsHandleToNodesExt;
+    hsaKmtWaitOnEvent_Ext;
+    hsaKmtWaitOnMultipleEvents_Ext;
     # ... 其他符号 ...
   local:
     *;
 };
```

#### 步骤2: 重新编译 libhsakmt.so

```bash
cd /data2/code/rocm6.4.3/ROCR-Runtime/build_dir

# 清理旧的 libhsakmt
rm -f libhsakmt/lib/libhsakmt.so*
rm -f libhsakmt/src/CMakeFiles/hsakmt.dir/*.o

# 重新编译
make -j8 hsakmt

# 验证符号导出
nm -D libhsakmt/lib/libhsakmt.so.1.0.6 | grep 'Ext.*@@'
```

#### 步骤3: 验证

```bash
# 应该看到：
00000000000132e0 T hsaKmtCreateQueueExt@@HSAKMT_1
000000000000fb10 T hsaKmtRegisterGraphicsHandleToNodesExt@@HSAKMT_1
0000000000007bd0 T hsaKmtWaitOnEvent_Ext@@HSAKMT_1
0000000000007310 T hsaKmtWaitOnMultipleEvents_Ext@@HSAKMT_1
```

### 常见缺失符号列表

根据我们的经验，以下符号经常缺失：

```
hsaKmtCreateQueueExt
hsaKmtRegisterGraphicsHandleToNodesExt
hsaKmtWaitOnEvent_Ext
hsaKmtWaitOnMultipleEvents_Ext
hsaKmtGetMemoryClockRateExt
hsaKmtGetQueueInfoExt
```

### 预防措施

创建完整的版本脚本检查：

```bash
#!/bin/bash
# check_symbols.sh - 检查缺失的符号

LIBHSAKMT_SO="$1"

echo "检查 libhsakmt.so 符号导出..."

# 需要的符号列表
REQUIRED_SYMBOLS=(
    "hsaKmtCreateQueueExt"
    "hsaKmtRegisterGraphicsHandleToNodesExt"
    "hsaKmtWaitOnEvent_Ext"
    "hsaKmtWaitOnMultipleEvents_Ext"
)

MISSING=0

for symbol in "${REQUIRED_SYMBOLS[@]}"; do
    if nm -D "$LIBHSAKMT_SO" | grep -q "$symbol"; then
        echo "✅ $symbol"
    else
        echo "❌ $symbol - 缺失"
        MISSING=$((MISSING + 1))
    fi
done

if [ $MISSING -eq 0 ]; then
    echo "✅ 所有符号都已导出"
    exit 0
else
    echo "❌ 有 $MISSING 个符号缺失"
    exit 1
fi
```

---

## 3. GPU 着色器编译失败

### 问题描述

**错误信息**:
```
clang-19: error: cannot find ROCm device library for gfx942. Provide its path via --rocm-path or --rocm-device-lib-path, or pass -nogpulib to build without ROCm device library.
```

或:
```
clang: error: invalid target ID 'gfx942'
```

### 根本原因

1. **Device libraries 缺失**: ROCm device libraries 是 GPU 编译的必需文件
2. **路径配置错误**: CMake 找不到 device libraries
3. **LLVM 版本不支持目标架构**: 如 clang-14 不支持 gfx942

### 检查方法

```bash
# 1. 检查 device libraries 是否存在
ls -lh /opt/rocm-6.4.3/amdgcn/bitcode/

# 应该看到很多 .bc 文件：
# oclc_*.bc
# ocml.bc
# ockl.bc
# ...

# 2. 检查 ROCm 环境变量
echo $ROCM_PATH
# 应该输出: /opt/rocm-6.4.3 或 /opt/rocm

# 3. 检查 clang 支持的目标
/opt/rocm-6.4.3/lib/llvm/bin/clang-19 --print-supported-cpus 2>&1 | grep gfx942
```

### 解决方案

#### 方案A: 设置环境变量

```bash
# 方法1: 临时设置
export ROCM_PATH=/opt/rocm-6.4.3
export DEVICE_LIB_PATH=/opt/rocm-6.4.3/amdgcn/bitcode

# 方法2: 在 CMake 中设置
cd build_dir
rm CMakeCache.txt
cmake .. \
  -DROCM_PATH=/opt/rocm-6.4.3 \
  -DDEVICE_LIB_PATH=/opt/rocm-6.4.3/amdgcn/bitcode

# 方法3: 修改环境配置（永久）
echo 'export ROCM_PATH=/opt/rocm-6.4.3' >> ~/.bashrc
echo 'export DEVICE_LIB_PATH=/opt/rocm-6.4.3/amdgcn/bitcode' >> ~/.bashrc
source ~/.bashrc
```

#### 方案B: 创建软链接

如果 device libraries 在非标准位置：

```bash
# 找到 device libraries
find /opt -name "*.bc" -path "*/amdgcn/bitcode/*" 2>/dev/null | head -3

# 创建标准链接
sudo mkdir -p /opt/rocm-6.4.3/amdgcn
sudo ln -s /actual/path/to/bitcode /opt/rocm-6.4.3/amdgcn/bitcode
```

#### 方案C: 安装缺失的 device libraries

```bash
# Ubuntu/Debian
sudo apt-get install rocm-device-libs

# 或从 ROCm 包安装
sudo apt-get install rocm-dev
```

### 验证

```bash
# 测试 GPU 编译
cat > test_kernel.cl << 'EOF'
__kernel void test(__global float* data) {
    int i = get_global_id(0);
    data[i] = i * 2.0f;
}
EOF

# 编译测试
/opt/rocm-6.4.3/lib/llvm/bin/clang-19 \
  -target amdgcn-amd-amdhsa \
  -mcpu=gfx942 \
  -nogpulib \
  test_kernel.cl \
  -o test_kernel.o

# 如果成功，说明基本工具链工作正常

# 再测试带 device libraries
/opt/rocm-6.4.3/lib/llvm/bin/clang-19 \
  -target amdgcn-amd-amdhsa \
  -mcpu=gfx942 \
  --rocm-path=/opt/rocm-6.4.3 \
  test_kernel.cl \
  -o test_kernel_with_libs.o
```

---

## 4. 源码文件缺失

### 问题描述 (PyTorch 特有)

**错误信息**:
```
CMake Error: File /workspace/pytorch_new/c10/hip/impl/hip_cmake_macros.h.in does not exist.
CMake Error at c10/hip/CMakeLists.txt:14 (configure_file):
  configure_file Problem configuring file
```

或:
```
CMake Error at aten/CMakeLists.txt:83 (add_subdirectory):
  add_subdirectory given source "src/THH" which is not an existing directory.
```

### 根本原因

1. **源码不完整**: 克隆时网络问题导致部分文件缺失
2. **清理过度**: `git clean -fdx` 删除了生成的必需文件
3. **分支/版本不匹配**: 某些分支缺少特定文件

### 检查方法

```bash
cd /workspace/pytorch_new

# 检查 git 状态
git status
git ls-files --deleted

# 检查缺失的文件
ls c10/hip/impl/hip_cmake_macros.h.in
ls aten/src/ATen/hip/HIPConfig.h.in
ls aten/src/THH/
```

### 解决方案

#### 方案A: 恢复删除的文件

```bash
cd /workspace/pytorch_new

# 恢复所有被删除的文件
git checkout -- .

# 或恢复特定文件
git checkout -- c10/hip/impl/hip_cmake_macros.h.in
git checkout -- aten/src/ATen/hip/HIPConfig.h.in
```

#### 方案B: 重新初始化子模块

```bash
cd /workspace/pytorch_new

# 更新子模块
git submodule sync
git submodule update --init --recursive
```

#### 方案C: 重新克隆（如果以上都失败）

```bash
# 备份当前修改
cd /workspace/pytorch_new
git diff > /tmp/pytorch_patches.diff

# 重新克隆
cd /workspace
mv pytorch_new pytorch_new.bak
git clone --recursive https://github.com/pytorch/pytorch.git pytorch_new
cd pytorch_new

# 应用之前的修改
patch -p1 < /tmp/pytorch_patches.diff
```

### 预防措施

```bash
# 编译前备份源码
cd /workspace/pytorch_new
git diff > /tmp/pytorch_backup_$(date +%Y%m%d_%H%M%S).patch
git status > /tmp/pytorch_status_$(date +%Y%m%d_%H%M%S).txt

# 只清理编译产物，不删除源码
python3 setup.py clean
rm -rf build/ dist/ torch.egg-info/

# 不要用: git clean -fdx (过于激进)
```

---

## 5. 内存不足

### 问题描述

**错误信息**:
```
c++: fatal error: Killed signal terminated program cc1plus
compilation terminated.
make[2]: *** [xxx.o] Error 1
```

或系统日志中:
```
Out of memory: Killed process XXX (cc1plus)
```

### 根本原因

- 编译 C++ 模板代码需要大量内存
- 并行编译使用过多内存
- 系统 swap 空间不足

### 检查方法

```bash
# 查看当前内存使用
free -h

# 查看编译时内存
watch -n 1 free -h

# 查看系统日志
dmesg | tail -20 | grep -i "out of memory"
```

### 解决方案

#### 方案A: 减少并行度

```bash
# 从 -j8 减少到 -j2 或 -j4
make -j2 hsa-runtime64

# 或完全串行
make hsa-runtime64
```

#### 方案B: 增加 Swap

```bash
# 检查当前 swap
swapon --show

# 创建 swap 文件（需要 root）
sudo fallocate -l 8G /swapfile
sudo chmod 600 /swapfile
sudo mkswap /swapfile
sudo swapon /swapfile

# 永久启用（添加到 /etc/fstab）
echo '/swapfile none swap sw 0 0' | sudo tee -a /etc/fstab
```

#### 方案C: 分批编译

```bash
# 只编译特定目标
make hsakmt
make hsa-runtime64

# 而不是一次编译所有
make all
```

### 监控编译内存

```bash
#!/bin/bash
# monitor_build.sh

echo "开始监控编译内存使用..."

while true; do
    TIMESTAMP=$(date +"%Y-%m-%d %H:%M:%S")
    MEM_USED=$(free -h | awk '/Mem:/ {print $3}')
    MEM_TOTAL=$(free -h | awk '/Mem:/ {print $2}')
    
    echo "[$TIMESTAMP] Memory: $MEM_USED / $MEM_TOTAL"
    
    # 如果内存使用超过 90%，警告
    MEM_PCT=$(free | awk '/Mem:/ {printf "%.0f", $3/$2 * 100}')
    if [ $MEM_PCT -gt 90 ]; then
        echo "⚠️  警告: 内存使用率 ${MEM_PCT}%"
    fi
    
    sleep 5
done
```

---

## 6. CMake 版本问题

### 问题描述

**错误信息**:
```
CMake Error at CMakeLists.txt:X (cmake_minimum_required):
  CMake 3.26 or higher is required. You are running version 3.16.3
```

### 解决方案

```bash
# 查找可用的 cmake
find /opt -name cmake -type f 2>/dev/null

# 使用正确版本
/opt/cmake-3.26.4/bin/cmake --version

# 或创建别名
alias cmake=/opt/cmake-3.26.4/bin/cmake

# 在 Makefile 中指定
export CMAKE_BIN=/opt/cmake-3.26.4/bin/cmake
$CMAKE_BIN ..
```

---

## 7. Docker 路径问题

### 问题描述

容器内路径和宿主机路径不一致：
- 容器内: `/data2/code/...`
- 宿主机: `/data/zhehan/code/...`

### 解决方案

```bash
# 使用 docker cp 传输文件
docker cp local_file.so container:/target/path/

# 或在容器内编译
docker exec -it container bash
cd /data2/code/...
make
```

---

## 8. 依赖库缺失

### 问题描述

```
/usr/bin/ld: cannot find -lelf
/usr/bin/ld: cannot find -lnuma
```

### 解决方案

```bash
# Ubuntu/Debian
sudo apt-get update
sudo apt-get install -y \
    libelf-dev \
    libnuma-dev \
    libdrm-dev \
    libdrm-amdgpu-dev

# 验证
ldconfig -p | grep -E "libelf|libnuma|libdrm"
```

---

## 总结

### 编译成功的关键要素

1. ✅ **完整的工具链**
   - clang-19 (ROCm LLVM)
   - llvm-objcopy
   - ROCm device libraries

2. ✅ **正确的环境**
   - 推荐使用 Docker 容器
   - 完整的依赖库
   - 足够的内存和磁盘

3. ✅ **正确的流程**
   - 备份源码修改
   - 清理构建目录
   - 保存编译日志
   - 验证编译结果

### 快速诊断检查表

编译失败时，按以下顺序检查：

- [ ] 1. 检查 LLVM 工具链 (`which clang-19`)
- [ ] 2. 检查 CMake 版本 (`cmake --version`)
- [ ] 3. 检查依赖库 (`ldconfig -p | grep libelf`)
- [ ] 4. 检查源码完整性 (`git status`)
- [ ] 5. 检查内存使用 (`free -h`)
- [ ] 6. 查看编译日志错误
- [ ] 7. 检查符号导出 (`nm -D libhsakmt.so`)

---

**文档维护**: AI Assistant  
**最后更新**: 2025-01-07  
**基于实际编译经验总结**

