# ROCm 编译快速开始指南

**适用人员**: 需要快速编译 ROCm 或 PyTorch 的开发者  
**预计时间**: ROCm Runtime 2-5分钟，PyTorch 2-4小时  
**难度**: ⭐⭐⭐  

---

## 🚀 最快方式：使用编译脚本

### 1. 编译 ROCm Runtime (2-5分钟)

```bash
cd /data/zhehan/code/0107_summary/ROCm_build/scripts

# 编译 8MB 版本（推荐，修复 pagefault）
./build_rocm_runtime.sh 8mb

# 或编译其他版本
./build_rocm_runtime.sh 2mb   # 2MB 版本
./build_rocm_runtime.sh 4mb   # 4MB 版本
```

**生成的文件**:
- `/data/zhehan/code/rocm6.4.3/ROCR-Runtime/build_8mb_versioned/src/libhsa-runtime64.so.1.15.0`

---

### 2. 编译 PyTorch (2-4小时)

```bash
cd /data/zhehan/code/0107_summary/ROCm_build/scripts

# 生成 wheel 包（推荐）
./build_pytorch_rocm.sh wheel

# 或开发模式（更快）
./build_pytorch_rocm.sh develop

# 或仅编译 .so 文件（最快）
./build_pytorch_rocm.sh so_only
```

**生成的文件**:
- wheel 模式: `/data/zhehan/code/script/source_backWA_docker2/1216_pytorch_build/torch-*.whl`
- develop 模式: 直接安装到 Python 环境
- so_only 模式: `/data/zhehan/code/script/source_backWA_docker2/1216_pytorch_build/*.so`

---

## 📝 手动编译步骤

### ROCm Runtime 手动编译

#### 前提条件

```bash
# 1. 在正确的容器中
docker exec -it sglang_zhendebug2_8MB bash

# 2. 验证工具链
which clang-19 || ls /opt/rocm*/lib/llvm/bin/clang*
which cmake || ls /opt/cmake*/bin/cmake
```

#### 编译步骤

```bash
# 1. 进入源码目录
cd /data2/code/rocm6.4.3/ROCR-Runtime

# 2. 创建构建目录
mkdir build_custom && cd build_custom

# 3. CMake 配置
/opt/cmake-3.26.4/bin/cmake .. \
  -DCMAKE_BUILD_TYPE=Release \
  -DCMAKE_INSTALL_PREFIX=/opt/rocm-6.4.3 \
  -DCMAKE_C_COMPILER=/usr/bin/gcc \
  -DCMAKE_CXX_COMPILER=/usr/bin/g++ \
  -DBUILD_SHARED_LIBS=ON

# 4. 编译
make -j8 hsakmt 2>&1 | tee build_hsakmt.log
make -j8 hsa-runtime64 2>&1 | tee build_hsa_runtime.log

# 5. 验证
ls -lh rocr/lib/libhsa-runtime64.so.1.15.0
ls -lh libhsakmt/lib/libhsakmt.so.1.0.6

# 6. 复制到部署位置
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
cp rocr/lib/libhsa-runtime64.so.1.15.0 \
   /data2/code/debug_summary/rocmdebugSO/libhsa-runtime64.so.1.15.0.custom_${TIMESTAMP}
```

**耗时**: 约 2-5 分钟

---

### PyTorch 手动编译

#### 前提条件

```bash
# 1. 检查 ROCm
hipcc --version

# 2. 检查 Python
python3 --version
python3 -c "import numpy, yaml"
```

#### 编译步骤（Wheel 模式）

```bash
# 1. 设置环境变量
export USE_ROCM=1
export USE_CUDA=0
export PYTORCH_ROCM_ARCH="gfx90a;gfx942"
export MAX_JOBS=$(nproc)
export BUILD_TEST=0
export USE_KINETO=0

# 2. 进入源码目录
cd /data/zhehan/code/pytorch

# 3. 清理旧构建（可选）
rm -rf build/ dist/ torch.egg-info/

# 4. 开始编译
python3 setup.py bdist_wheel 2>&1 | tee /tmp/pytorch_build.log

# 5. 查找生成的 wheel
ls -lht dist/torch-*.whl | head -1
```

**耗时**: 约 2-4 小时

---

## 🔧 安装编译好的文件

### 安装 ROCm Runtime

```bash
# 方法1: 使用脚本（推荐）
cd /data/zhehan/code/0107_summary/ROCm_build/scripts
./install_rocm_version.sh sglang_zhendebug4 8mb

# 方法2: 手动安装
docker exec sglang_zhendebug4 bash -c "
  cp /data/zhehan/code/debug_summary/rocmdebugSO/libhsa-runtime64.so.1.15.0.8mb_20251127 \
     /opt/rocm-6.4.3/lib/libhsa-runtime64.so.1.15.0
"

# 重启容器使其生效
docker restart sglang_zhendebug4
```

---

### 安装 PyTorch Wheel

```bash
# 安装 wheel 包
pip install /path/to/torch-*.whl --force-reinstall

# 验证安装
python3 -c "import torch; print(torch.__version__); print(torch.cuda.is_available())"
```

---

## ✅ 验证编译结果

### 验证 ROCm Runtime

```bash
# 1. 检查文件
ls -lh /opt/rocm-6.4.3/lib/libhsa-runtime64.so.1.15.0

# 2. 检查依赖
ldd /opt/rocm-6.4.3/lib/libhsa-runtime64.so.1.15.0

# 3. 检查版本
cd /data/zhehan/code/0107_summary/ROCm_build/scripts
./identify_version.sh sglang_zhendebug4

# 4. 测试运行
python3 -c "import torch; torch.zeros(1).cuda()" 2>&1 | grep "version-block_size"
# 应该输出: version-block_size: 8 MB
```

---

### 验证 PyTorch

```bash
python3 << 'EOF'
import torch

print(f"✅ PyTorch版本: {torch.__version__}")
print(f"✅ ROCm可用: {torch.cuda.is_available()}")

if torch.cuda.is_available():
    print(f"✅ ROCm版本: {torch.version.hip}")
    print(f"✅ GPU数量: {torch.cuda.device_count()}")
    
    # 简单测试
    x = torch.randn(10, 10).cuda()
    y = torch.randn(10, 10).cuda()
    z = torch.matmul(x, y)
    print(f"✅ GPU计算测试通过")
else:
    print("❌ ROCm不可用")
EOF
```

---

## ⚠️ 常见问题快速解决

### 问题1: 找不到 clang-19

**错误**: `No rule to make target '/opt/rocm-6.4.3/lib/llvm/bin/clang-19'`

**解决**:
```bash
# 检查是否在正确的容器
docker ps | grep sglang_zhendebug2

# 或创建软链接
mkdir -p /opt/rocm-6.4.3/lib/llvm/bin
ln -s /usr/bin/clang-14 /opt/rocm-6.4.3/lib/llvm/bin/clang-19
```

---

### 问题2: 符号未定义

**错误**: `undefined symbol: hsaKmtCreateQueueExt`

**解决**:
```bash
# 修改版本脚本
vi /data2/code/rocm6.4.3/ROCR-Runtime/libhsakmt/src/libhsakmt.ver

# 添加以下行到 HSAKMT_1 { global: 部分:
# hsaKmtCreateQueueExt;
# hsaKmtRegisterGraphicsHandleToNodesExt;
# hsaKmtWaitOnEvent_Ext;
# hsaKmtWaitOnMultipleEvents_Ext;

# 重新编译 libhsakmt
cd build_dir
rm -f libhsakmt/lib/libhsakmt.so*
make -j8 hsakmt
```

---

### 问题3: 内存不足

**错误**: `c++: fatal error: Killed`

**解决**:
```bash
# 减少并行度
make -j2 hsa-runtime64  # 而不是 -j8

# 或完全串行
make hsa-runtime64
```

---

### 问题4: PyTorch 源码文件缺失

**错误**: `File .../hip_cmake_macros.h.in does not exist`

**解决**:
```bash
cd /data/zhehan/code/pytorch
git checkout -- .  # 恢复删除的文件
git submodule update --init --recursive  # 更新子模块
```

---

## 📚 更多信息

- **完整编译指南**: [COMPILATION_GUIDE.md](COMPILATION_GUIDE.md)
- **问题排查**: [COMPILATION_ISSUES.md](COMPILATION_ISSUES.md)
- **脚本说明**: [BUILD_SCRIPTS.md](BUILD_SCRIPTS.md)
- **PyTorch专题**: [PYTORCH_BUILD.md](PYTORCH_BUILD.md)

---

## 🎯 推荐编译流程

### 新手推荐

```bash
# 1. 使用包含完整工具链的容器
docker exec -it sglang_zhendebug2_8MB bash

# 2. 使用编译脚本
cd /data/zhehan/code/0107_summary/ROCm_build/scripts
./build_rocm_runtime.sh 8mb

# 3. 验证结果
./identify_version.sh sglang_zhendebug2_8MB
```

### 经验用户

```bash
# 1. 手动编译，完全控制
cd /data2/code/rocm6.4.3/ROCR-Runtime
mkdir build && cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j8

# 2. 自定义修改和 patch
vim runtime/hsa-runtime/core/driver/kfd/amd_kfd_driver.cpp
# ... 应用修改 ...
make -j8

# 3. 详细验证
ldd rocr/lib/libhsa-runtime64.so.1.15.0
nm -D rocr/lib/libhsa-runtime64.so.1.15.0 | grep hsa_init
```

---

**创建时间**: 2025-01-07  
**适用版本**: ROCm 6.4.3, PyTorch 2.7.1+  
**维护**: AI Assistant

