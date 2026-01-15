#!/bin/bash
# PyTorch ROCm 编译脚本
# 适用于 ROCm 6.4.3+ 环境
# 日期: 2025-12-16

set -e  # 遇到错误立即退出

# ============================================================================
# 配置区域
# ============================================================================

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# PyTorch源码目录
PYTORCH_SRC="/data/zhehan/code/pytorch"

# 构建目录
BUILD_DIR="/data/zhehan/code/script/source_backWA_docker2/1216_pytorch_build"

# 安装目录（可选，留空则安装到系统Python）
INSTALL_PREFIX=""

# 构建类型：
# - "develop": 开发模式（快速，适合测试）
# - "wheel": 生成wheel包（完整，适合部署）
# - "so_only": 仅编译libc10_cuda.so（最快，适合快速迭代）
BUILD_TYPE="${1:-develop}"

# 并行编译线程数（根据CPU核心数调整）
MAX_JOBS=$(nproc)

# ============================================================================
# 函数定义
# ============================================================================

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

check_rocm() {
    log_info "检查ROCm环境..."
    
    if ! command -v hipcc &> /dev/null; then
        log_error "未找到hipcc，请确认ROCm已正确安装"
        exit 1
    fi
    
    ROCM_VERSION=$(hipcc --version | grep "HIP version" | awk '{print $3}')
    log_info "检测到 HIP 版本: $ROCM_VERSION"
    
    if [ -z "$ROCM_PATH" ]; then
        export ROCM_PATH=/opt/rocm
        log_warn "ROCM_PATH未设置，使用默认值: $ROCM_PATH"
    fi
    
    log_info "ROCM_PATH: $ROCM_PATH"
}

check_dependencies() {
    log_info "检查编译依赖..."
    
    # 检查Python
    if ! command -v python3 &> /dev/null; then
        log_error "未找到python3"
        exit 1
    fi
    
    PYTHON_VERSION=$(python3 --version | awk '{print $2}')
    log_info "Python版本: $PYTHON_VERSION"
    
    # 检查必要的Python包
    log_info "检查Python依赖包..."
    python3 -c "import numpy" 2>/dev/null || log_warn "numpy未安装"
    python3 -c "import yaml" 2>/dev/null || log_warn "pyyaml未安装"
    
    # 检查CMake
    if ! command -v cmake &> /dev/null; then
        log_error "未找到cmake"
        exit 1
    fi
    
    CMAKE_VERSION=$(cmake --version | head -1 | awk '{print $3}')
    log_info "CMake版本: $CMAKE_VERSION"
}

setup_environment() {
    log_info "设置编译环境变量..."
    
    # ROCm相关
    export USE_ROCM=1
    export USE_CUDA=0
    export PYTORCH_ROCM_ARCH="gfx90a;gfx942"  # 根据您的GPU调整
    
    # 编译优化
    export MAX_JOBS=$MAX_JOBS
    export CMAKE_PREFIX_PATH=${CONDA_PREFIX:-"$(dirname $(which python3))"}
    
    # 构建配置
    export BUILD_TEST=0  # 不编译测试（加速）
    export USE_MKLDNN=1
    export USE_DISTRIBUTED=1
    export USE_NCCL=0  # ROCm使用RCCL
    export USE_RCCL=1
    
    # Debug选项（可选）
    # export DEBUG=1
    # export REL_WITH_DEB_INFO=1
    
    log_info "环境变量设置完成"
    log_info "  USE_ROCM=$USE_ROCM"
    log_info "  MAX_JOBS=$MAX_JOBS"
    log_info "  PYTORCH_ROCM_ARCH=$PYTORCH_ROCM_ARCH"
}

backup_source() {
    log_info "备份当前修改..."
    cd "$PYTORCH_SRC"
    
    # 保存当前修改
    if git diff --quiet; then
        log_info "没有未提交的修改"
    else
        log_warn "检测到未提交的修改，创建备份..."
        git diff > "$BUILD_DIR/pytorch_modifications_$(date +%Y%m%d_%H%M%S).patch"
        log_info "备份已保存到: $BUILD_DIR/pytorch_modifications_*.patch"
    fi
}

clean_build() {
    log_info "清理之前的构建..."
    cd "$PYTORCH_SRC"
    
    # 清理构建目录
    rm -rf build/
    rm -rf torch/lib/*.so
    rm -rf torch/lib/*.a
    
    # 清理Python缓存
    find . -type d -name __pycache__ -exec rm -rf {} + 2>/dev/null || true
    find . -type f -name "*.pyc" -delete 2>/dev/null || true
    
    log_info "清理完成"
}

build_develop() {
    log_info "开始编译（开发模式）..."
    log_info "预计时间: 30-60分钟"
    
    cd "$PYTORCH_SRC"
    
    # 开发模式安装
    python3 setup.py develop
    
    log_info "开发模式编译完成！"
    log_info "PyTorch已安装到: $(python3 -c 'import torch; print(torch.__file__)')"
}

build_wheel() {
    log_info "开始编译（wheel模式）..."
    log_info "预计时间: 2-4小时"
    
    cd "$PYTORCH_SRC"
    
    # 生成wheel包
    python3 setup.py bdist_wheel
    
    WHEEL_FILE=$(ls -t dist/torch-*.whl | head -1)
    log_info "Wheel包已生成: $WHEEL_FILE"
    
    # 复制到构建目录
    cp "$WHEEL_FILE" "$BUILD_DIR/"
    log_info "Wheel包已复制到: $BUILD_DIR/$(basename $WHEEL_FILE)"
    
    # 询问是否安装
    read -p "是否立即安装此wheel包？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        pip install "$WHEEL_FILE" --force-reinstall
        log_info "安装完成！"
    fi
}

build_so_only() {
    log_info "开始编译（仅.so模式）..."
    log_info "预计时间: 10-20分钟"
    
    cd "$PYTORCH_SRC"
    
    # 仅编译扩展
    python3 setup.py build_ext --inplace
    
    # 查找生成的.so文件
    SO_FILE=$(find build -name "libc10_cuda.so" -o -name "libc10_hip.so" | head -1)
    
    if [ -n "$SO_FILE" ]; then
        log_info "找到编译的.so文件: $SO_FILE"
        
        # 复制到构建目录
        cp "$SO_FILE" "$BUILD_DIR/"
        log_info ".so文件已复制到: $BUILD_DIR/$(basename $SO_FILE)"
        
        # 显示安装位置
        TORCH_LIB_PATH=$(python3 -c "import torch; import os; print(os.path.join(os.path.dirname(torch.__file__), 'lib'))" 2>/dev/null)
        
        if [ -n "$TORCH_LIB_PATH" ]; then
            log_info "要替换系统中的.so文件，请运行:"
            log_info "  sudo cp $BUILD_DIR/$(basename $SO_FILE) $TORCH_LIB_PATH/"
        fi
    else
        log_error "未找到编译的.so文件"
        exit 1
    fi
}

verify_build() {
    log_info "验证编译结果..."
    
    python3 << 'EOF'
import sys
try:
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
        print("⚠️  ROCm不可用")
        sys.exit(1)
        
except Exception as e:
    print(f"❌ 验证失败: {e}")
    sys.exit(1)
EOF
    
    if [ $? -eq 0 ]; then
        log_info "验证通过！"
    else
        log_error "验证失败！"
        exit 1
    fi
}

show_summary() {
    log_info "================================"
    log_info "编译完成摘要"
    log_info "================================"
    log_info "构建类型: $BUILD_TYPE"
    log_info "源码目录: $PYTORCH_SRC"
    log_info "构建目录: $BUILD_DIR"
    
    if [ "$BUILD_TYPE" == "wheel" ]; then
        WHEEL_FILE=$(ls -t "$BUILD_DIR"/torch-*.whl 2>/dev/null | head -1)
        if [ -n "$WHEEL_FILE" ]; then
            log_info "Wheel包: $WHEEL_FILE"
            log_info ""
            log_info "安装命令:"
            log_info "  pip install $WHEEL_FILE --force-reinstall"
        fi
    elif [ "$BUILD_TYPE" == "so_only" ]; then
        SO_FILE=$(ls -t "$BUILD_DIR"/*.so 2>/dev/null | head -1)
        if [ -n "$SO_FILE" ]; then
            log_info ".so文件: $SO_FILE"
            TORCH_LIB_PATH=$(python3 -c "import torch; import os; print(os.path.join(os.path.dirname(torch.__file__), 'lib'))" 2>/dev/null)
            if [ -n "$TORCH_LIB_PATH" ]; then
                log_info ""
                log_info "替换命令:"
                log_info "  sudo cp $SO_FILE $TORCH_LIB_PATH/"
            fi
        fi
    fi
    
    log_info "================================"
}

# ============================================================================
# 主流程
# ============================================================================

main() {
    log_info "PyTorch ROCm 编译脚本"
    log_info "构建类型: $BUILD_TYPE"
    log_info "================================"
    
    # 1. 环境检查
    check_rocm
    check_dependencies
    
    # 2. 设置环境
    setup_environment
    
    # 3. 备份源码
    backup_source
    
    # 4. 清理构建
    read -p "是否清理之前的构建？(y/n) " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        clean_build
    fi
    
    # 5. 开始编译
    case "$BUILD_TYPE" in
        develop)
            build_develop
            ;;
        wheel)
            build_wheel
            ;;
        so_only)
            build_so_only
            ;;
        *)
            log_error "未知的构建类型: $BUILD_TYPE"
            log_info "支持的类型: develop, wheel, so_only"
            exit 1
            ;;
    esac
    
    # 6. 验证
    if [ "$BUILD_TYPE" != "so_only" ]; then
        verify_build
    fi
    
    # 7. 显示摘要
    show_summary
    
    log_info "全部完成！"
}

# 显示使用说明
if [ "$1" == "-h" ] || [ "$1" == "--help" ]; then
    echo "使用方法: $0 [BUILD_TYPE]"
    echo ""
    echo "BUILD_TYPE:"
    echo "  develop   - 开发模式（默认，30-60分钟）"
    echo "  wheel     - 生成wheel包（2-4小时）"
    echo "  so_only   - 仅编译.so文件（10-20分钟）"
    echo ""
    echo "示例:"
    echo "  $0 develop    # 开发模式"
    echo "  $0 wheel      # 生成wheel"
    echo "  $0 so_only    # 仅编译.so"
    exit 0
fi

# 运行主流程
main

