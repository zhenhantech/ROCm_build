#!/bin/bash
# ROCm版本编译脚本 - 自动编译2MB, 4MB, 8MB三个版本

set -e

ROCM_SRC="/data/zhehan/code/rocm6.4.3/ROCR-Runtime"
ROCM_LIB_DOCKER="/opt/rocm-6.4.3/lib"
DATE_STAMP=$(date +%Y%m%d)

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║     ROCm 多版本编译脚本                                   ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

# 备份当前版本
echo "=== 步骤1: 备份Docker内的当前版本 ==="
docker exec sglang_zhendebug4 bash -c "
  cd ${ROCM_LIB_DOCKER}
  if [ -f libhsa-runtime64.so.1.15.0 ]; then
    cp libhsa-runtime64.so.1.15.0 libhsa-runtime64.so.1.15.0.backup_$(date +%Y%m%d_%H%M%S)
    echo '✅ Backup created'
  else
    echo '⚠️  No existing file to backup'
  fi
"

# 修改源码并编译的函数
build_version() {
  local SIZE_MB=$1
  local SIZE_BYTES=$(($SIZE_MB * 1024 * 1024))
  local VERSION_NAME="ROCM_BLOCK_SIZE_${SIZE_MB}MB"
  local BUILD_DIR="${ROCM_SRC}/build_${SIZE_MB}mb_versioned"
  
  echo ""
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  echo "编译 ${SIZE_MB}MB 版本"
  echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
  
  # 步骤1: 修改 amd_memory_region.h
  echo "  [1/5] 修改 amd_memory_region.h ..."
  sed -i "s/static const size_t block_size_ = [0-9]* \* 1024 \* 1024;/static const size_t block_size_ = ${SIZE_MB} * 1024 * 1024;/" \
    ${ROCM_SRC}/runtime/hsa-runtime/core/inc/amd_memory_region.h
  
  # 步骤2: 修改 amd_memory_region.cpp 中的版本字符串
  echo "  [2/5] 修改 amd_memory_region.cpp 版本字符串 ..."
  # TODO: 需要先添加版本打印代码（如果还没有）
  
  # 步骤3: 使用已有的build目录（如果存在）或创建新的
  echo "  [3/5] 准备构建目录 ..."
  if [ -d "${ROCM_SRC}/build_8mb" ] && [ -f "${ROCM_SRC}/build_8mb/Makefile" ]; then
    # 使用已有的build_8mb作为模板
    if [ ! -d "$BUILD_DIR" ]; then
      cp -r ${ROCM_SRC}/build_8mb $BUILD_DIR
      # 更新CMakeCache
      sed -i "s|build_8mb|build_${SIZE_MB}mb_versioned|g" $BUILD_DIR/CMakeCache.txt
    fi
    
    # 步骤4: 编译
    echo "  [4/5] 编译中... (这可能需要几分钟)"
    cd $BUILD_DIR
    
    # 修复cmake路径问题
    if [ -f Makefile ]; then
      sed -i 's|/usr/local/lib/python3.10/dist-packages/cmake/data/bin/cmake|/usr/bin/cmake|g' Makefile
    fi
    
    # 清理并重新编译
    make clean 2>/dev/null || true
    make -j$(nproc) 2>&1 | tee /tmp/build_${SIZE_MB}mb.log | tail -20
    
    if [ -f src/libhsa-runtime64.so.1.15.0 ]; then
      echo "  ✅ 编译成功"
      
      # 步骤5: 保存到Docker
      echo "  [5/5] 复制到Docker ..."
      docker cp src/libhsa-runtime64.so.1.15.0 \
        sglang_zhendebug4:${ROCM_LIB_DOCKER}/libhsa-runtime64.so.1.15.0.${SIZE_MB}mb_version_${DATE_STAMP}
      
      echo "  ✅ ${SIZE_MB}MB版本完成: ${ROCM_LIB_DOCKER}/libhsa-runtime64.so.1.15.0.${SIZE_MB}mb_version_${DATE_STAMP}"
    else
      echo "  ❌ 编译失败，查看日志: /tmp/build_${SIZE_MB}mb.log"
      return 1
    fi
  else
    echo "  ❌ 无可用的build模板目录"
    return 1
  fi
}

# 编译3个版本
build_version 2
build_version 4
build_version 8

echo ""
echo "╔════════════════════════════════════════════════════════════╗"
echo "║                                                            ║"
echo "║     ✅ 所有版本编译完成                                   ║"
echo "║                                                            ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo "查看所有版本:"
docker exec sglang_zhendebug4 bash -c "
  ls -lh ${ROCM_LIB_DOCKER}/libhsa-runtime64.so.1.15.0.*mb_version_*
"

echo ""
echo "使用方法:"
echo "  cd /tmp/source_backWA_docker2/1127_hipalloc_issue_cleanup/scripts"
echo "  ./switch_rocm_version.sh {2mb|4mb|8mb}"

