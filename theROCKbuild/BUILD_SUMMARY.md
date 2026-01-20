# ROCm Build Summary - TheRock Build System

## 概述

本文档记录了使用 TheRock 构建系统编译 ROCm（针对 gfx942/MI300A/MI300X GPU）的完整过程，包括遇到的问题、解决方案和最终构建状态。

**构建日期**: 2025年1月  
**目标GPU**: gfx942 (MI300A/MI300X, CDNA3)  
**构建系统**: TheRock (https://github.com/ROCm/TheRock)  
**编译器**: TheRock-built Clang 22  
**构建环境**: Docker容器 (zhen_rockmbuild)

---

## 构建配置

### GPU 配置
- **THEROCK_AMDGPU_TARGETS**: `gfx942`
- **THEROCK_AMDGPU_FAMILIES**: `gfx94X-dcgpu`
- **THEROCK_AMDGPU_DIST_BUNDLE_NAME**: `gfx94X-dcgpu`

### CMake 配置命令
```bash
cmake -B build -GNinja . \
    -DTHEROCK_AMDGPU_TARGETS=gfx942 \
    -DTHEROCK_AMDGPU_FAMILIES=gfx94X-dcgpu \
    -DTHEROCK_AMDGPU_DIST_BUNDLE_NAME=gfx94X-dcgpu \
    -DTHEROCK_ENABLE_ROCGDB=OFF \
    -DCMAKE_C_COMPILER_LAUNCHER=ccache \
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
```

### 构建性能
- **首次配置时间**: ~38分钟 (2269秒)
- **修复后配置时间**: ~10.5分钟 (629秒)
- **完整构建时间**: 数小时（取决于CPU核心数和ccache命中率）

---

## 遇到的问题及解决方案

### 问题 1: Git 子模块所有权错误

**错误信息**:
```
fatal: detected dubious ownership in repository at '/data/TheRock/iree-libs/iree'
```

**原因**: Docker容器中挂载的卷文件所有权与容器内用户不匹配

**解决方案**:
```bash
git config --global --add safe.directory '*'
```

---

### 问题 2: CMake 配置错误 - 缺少 DIST AMDGPU targets

**错误信息**:
```
CMake Error: Subproject therock-boost requires dist AMDGPU targets but none were set. 
Set THEROCK_DIST_AMDGPU_FAMILIES.
```

**原因**: 使用 `THEROCK_AMDGPU_TARGETS` 时，必须同时设置 `THEROCK_AMDGPU_FAMILIES` 和 `THEROCK_AMDGPU_DIST_BUNDLE_NAME`

**解决方案**: 在CMake配置中添加：
```bash
-DTHEROCK_AMDGPU_FAMILIES=gfx94X-dcgpu
-DTHEROCK_AMDGPU_DIST_BUNDLE_NAME=gfx94X-dcgpu
```

---

### 问题 3: ROCgdb 编译失败 - 缺少 TeX 系统

**错误信息**:
```
make[2]: *** [Makefile:498: gdb.pdf] Error 1
```

**原因**: ROCgdb 需要 TeX 系统来生成 PDF 文档

**解决方案**: 禁用 ROCgdb（可选组件）
```bash
-DTHEROCK_ENABLE_ROCGDB=OFF
```

**注意**: 如果需要 ROCgdb，可以安装 `texlive` 包：
```bash
sudo apt install texlive texlive-latex-extra
```

---

### 问题 4: aqlprofile 编译错误 - 头文件包含问题

**错误信息**:
```
error: unknown type name 'hsa_handle_t'
```

**原因**: `intercept.cpp` 使用了错误的头文件包含路径

**解决方案**: 修改头文件包含
```bash
sed -i 's|#include <hsa_ext_amd.h>|#include <hsa/hsa_ext_amd.h>|' \
    rocm-systems/projects/aqlprofile/test/integration/intercept.cpp
```

---

### 问题 5: rocBLAS/hipBLAS/rocSPARSE 编译错误 - cstdint 类型未定义

**错误信息**:
```
error: no member named 'int_least16_t' in the global namespace
error: no member named 'uint64_t' in the global namespace
error: unknown type name 'uint32_t'
```

**根本原因**: 
- 这些组件的 CMakeLists.txt 硬编码了 `/opt/rocm` 路径
- 导致使用系统安装的 ROCm 20 头文件（`/opt/rocm/llvm/lib/clang/20/include`）
- 系统头文件在设备端编译时，C++ 标准库的 `cstdint` 存在问题
- TheRock 构建的 clang 22 头文件已正确包含 `stdint.h`

**解决方案**: 移除所有 `/opt/rocm` 硬编码路径，强制使用 TheRock 构建的编译器

#### rocBLAS 修复
```bash
# 备份原始文件
cp rocm-libraries/projects/rocblas/CMakeLists.txt rocm-libraries/projects/rocblas/CMakeLists.txt.bak

# 移除 /opt/rocm 路径
sed -i 's|list( APPEND CMAKE_PREFIX_PATH \${ROCM_PATH}/llvm \${ROCM_PATH} \${ROCM_PATH}/hip /opt/rocm/llvm /opt/rocm /opt/rocm/hip )|list( APPEND CMAKE_PREFIX_PATH \${ROCM_PATH}/llvm \${ROCM_PATH} \${ROCM_PATH}/hip )|' \
    rocm-libraries/projects/rocblas/CMakeLists.txt

sed -i 's|set( hipblaslt_path \"/opt/rocm\" CACHE PATH|set( hipblaslt_path \"\${ROCM_PATH}\" CACHE PATH|' \
    rocm-libraries/projects/rocblas/CMakeLists.txt

sed -i 's|find_package( hip REQUIRED CONFIG PATHS \${HIP_DIR} \${ROCM_PATH} /opt/rocm )|find_package( hip REQUIRED CONFIG PATHS \${HIP_DIR} \${ROCM_PATH} )|' \
    rocm-libraries/projects/rocblas/CMakeLists.txt

sed -i 's|PATHS /opt/rocm/llvm/bin|PATHS \${ROCM_PATH}/llvm/bin|g' \
    rocm-libraries/projects/rocblas/CMakeLists.txt
```

#### hipBLAS 修复
```bash
cp rocm-libraries/projects/hipblas/CMakeLists.txt rocm-libraries/projects/hipblas/CMakeLists.txt.bak
cp rocm-libraries/projects/hipblas/library/src/CMakeLists.txt rocm-libraries/projects/hipblas/library/src/CMakeLists.txt.bak

sed -i 's|list( APPEND CMAKE_MODULE_PATH \${CMAKE_CURRENT_SOURCE_DIR}/cmake  \${ROCM_PATH}/lib/cmake/hip /opt/rocm/lib/cmake/hip \${HIP_DIR}/cmake )|list( APPEND CMAKE_MODULE_PATH \${CMAKE_CURRENT_SOURCE_DIR}/cmake  \${ROCM_PATH}/lib/cmake/hip \${HIP_DIR}/cmake )|' \
    rocm-libraries/projects/hipblas/CMakeLists.txt

sed -i 's|list( APPEND CMAKE_PREFIX_PATH \${ROCM_PATH}/lib/cmake/hip /opt/rocm /opt/rocm/llvm /opt/rocm/hip )|list( APPEND CMAKE_PREFIX_PATH \${ROCM_PATH}/lib/cmake/hip )|' \
    rocm-libraries/projects/hipblas/CMakeLists.txt

sed -i 's|find_package( hip CONFIG PATHS \${HIP_DIR} \${ROCM_PATH} /opt/rocm )|find_package( hip CONFIG PATHS \${HIP_DIR} \${ROCM_PATH} )|' \
    rocm-libraries/projects/hipblas/CMakeLists.txt

sed -i 's|PATHS /opt/rocm/llvm/bin|PATHS \${ROCM_PATH}/llvm/bin|g' \
    rocm-libraries/projects/hipblas/CMakeLists.txt

sed -i 's|find_package( rocblas REQUIRED CONFIG PATHS \${ROCM_PATH} /opt/rocm /opt/rocm/rocblas /usr/local/rocblas )|find_package( rocblas REQUIRED CONFIG PATHS \${ROCM_PATH} /usr/local/rocblas )|' \
    rocm-libraries/projects/hipblas/library/src/CMakeLists.txt

sed -i 's|find_package( rocsolver REQUIRED CONFIG PATHS \${ROCM_PATH} /opt/rocm /opt/rocm/rocsolver /usr/local/rocsolver )|find_package( rocsolver REQUIRED CONFIG PATHS \${ROCM_PATH} /usr/local/rocsolver )|' \
    rocm-libraries/projects/hipblas/library/src/CMakeLists.txt
```

#### rocSPARSE 修复
```bash
cp rocm-libraries/projects/rocsparse/CMakeLists.txt rocm-libraries/projects/rocsparse/CMakeLists.txt.bak
cp rocm-libraries/projects/rocsparse/clients/CMakeLists.txt rocm-libraries/projects/rocsparse/clients/CMakeLists.txt.bak

sed -i 's|list( APPEND CMAKE_PREFIX_PATH /opt/rocm/llvm /opt/rocm )|# list( APPEND CMAKE_PREFIX_PATH /opt/rocm/llvm /opt/rocm )|' \
    rocm-libraries/projects/rocsparse/CMakeLists.txt

sed -i 's|list(APPEND CMAKE_MODULE_PATH \${CMAKE_CURRENT_SOURCE_DIR}/cmake \${ROCM_PATH}/lib/cmake/hip /opt/rocm/lib/cmake/hip /opt/rocm/hip/cmake)|list(APPEND CMAKE_MODULE_PATH \${CMAKE_CURRENT_SOURCE_DIR}/cmake \${ROCM_PATH}/lib/cmake/hip )|' \
    rocm-libraries/projects/rocsparse/CMakeLists.txt

sed -i 's|find_package( hip REQUIRED CONFIG PATHS \${HIP_DIR} \${ROCM_PATH} /opt/rocm )|find_package( hip REQUIRED CONFIG PATHS \${HIP_DIR} \${ROCM_PATH} )|' \
    rocm-libraries/projects/rocsparse/CMakeLists.txt

sed -i 's|exec /opt/rocm/llvm/bin/llvm-cov|exec \${ROCM_PATH}/llvm/bin/llvm-cov|' \
    rocm-libraries/projects/rocsparse/CMakeLists.txt

sed -i 's|find_package(rocsparse REQUIRED CONFIG PATHS /opt/rocm/rocsparse)|find_package(rocsparse REQUIRED CONFIG PATHS \${ROCM_PATH}/rocsparse)|' \
    rocm-libraries/projects/rocsparse/clients/CMakeLists.txt

sed -i 's|list(APPEND CMAKE_PREFIX_PATH /opt/rocm)|# list(APPEND CMAKE_PREFIX_PATH /opt/rocm)|' \
    rocm-libraries/projects/rocsparse/clients/CMakeLists.txt
```

**影响**: 
- 配置时间从 ~38分钟 降至 ~10.5分钟
- 所有组件成功编译，使用 TheRock 构建的 clang 22 编译器

---

### 问题 6: ccache 未安装

**错误信息**:
```
FileNotFoundError: [Errno 2] No such file or directory: 'ccache'
```

**解决方案**:
```bash
sudo apt install ccache
# 或从源码构建 ccache 4.11+（推荐）
```

---

## 最终构建状态

### ✅ 成功构建的组件（30+ 个）

#### 核心运行时组件
- ✅ amd_comgr (编译器组件管理器)
- ✅ amdhip64 (HIP 运行时库)
- ✅ hsa-runtime64 (HSA 运行时)
- ✅ hiprtc (HIP 运行时编译)

#### 数学库组件
- ✅ rocblas (ROCm BLAS 库)
- ✅ hipblas (HIP BLAS 库)
- ✅ hipblaslt (HIP BLASLt 库)
- ✅ rocsparse (ROCm 稀疏矩阵库)
- ✅ hipsparse (HIP 稀疏矩阵库)
- ✅ hipsparselt (HIP SPARSELt 库)
- ✅ rocsolver (ROCm 求解器库)
- ✅ hipsolver (HIP 求解器库)
- ✅ rocfft (ROCm FFT 库)
- ✅ hipfft (HIP FFT 库)
- ✅ rocrand (ROCm 随机数生成库)
- ✅ hiprand (HIP 随机数生成库)

#### 深度学习组件
- ✅ MIOpen (深度学习库)
- ✅ hipdnn_backend (HIP DNN 后端)

#### 通信和集群组件
- ✅ rccl (ROCm 通信集合库)
- ✅ rdc (ROCm 设备管理)

#### 性能分析和调试工具
- ✅ roctracer64 (ROCm 跟踪器)
- ✅ roctx64 (ROCm 跟踪扩展)
- ✅ rocprofiler-sdk (ROCm 性能分析器 SDK)
- ✅ rocprof-sys (ROCm 性能分析系统库)
- ✅ rocm-dbgapi (ROCm 调试 API)
- ✅ rocm-debug-agent (ROCm 调试代理)
- ✅ rocm_smi64 (ROCm 系统管理接口)
- ✅ amd_smi (AMD 系统管理接口)
- ✅ rocm-core (ROCm 核心库)
- ✅ rocroller (ROCm 滚动器)

### ❌ 禁用的组件
- ❌ ROCgdb (需要 TeX 系统，已禁用)

### 构建产物位置
- **安装目录**: `build/dist/rocm/`
- **库文件数量**: 55+ 个 .so 文件
- **可执行文件**: 30+ 个工具和测试程序

---

## 关键经验总结

1. **使用 TheRock 构建的编译器**: 避免依赖系统安装的 ROCm，确保版本一致性
2. **移除硬编码路径**: 所有 `/opt/rocm` 硬编码路径都应替换为 `${ROCM_PATH}`
3. **ccache 加速**: 使用 ccache 可以显著加速后续构建
4. **配置时间**: 首次配置需要较长时间，这是正常的
5. **组件依赖**: 某些组件（如 hipBLAS）依赖其他组件（rocBLAS、rocSOLVER），需要按顺序构建

---

## 后续步骤

### 使用构建产物
```bash
# 设置环境变量
export ROCM_PATH=/data/TheRock/build/dist/rocm
export PATH=$ROCM_PATH/bin:$PATH
export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH

# 或安装到系统目录
sudo cp -r build/dist/rocm/* /opt/rocm/
```

### 打包分发
- 使用 `package_deb.sh` 创建 Debian/Ubuntu 包
- 使用 `package_rpm.sh` 创建 RedHat/CentOS 包

---

## 参考文档

- TheRock 官方仓库: https://github.com/ROCm/TheRock
- ROCm 文档: https://rocm.docs.amd.com/
- GPU 架构参考: gfx942 (MI300A/MI300X, CDNA3)

---

**构建完成日期**: 2025年1月  
**构建状态**: ✅ 全部成功  
**总构建时间**: 数小时（取决于系统配置）

