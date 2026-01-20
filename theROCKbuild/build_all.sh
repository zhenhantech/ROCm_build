#!/bin/bash
#
# build_all.sh - 编译全部 ROCm 组件
#
# 使用方法:
#   ./build_all.sh [选项]
#
# 选项:
#   -j, --jobs N          并行编译任务数 (默认: $(nproc))
#   -k, --keep-going       遇到错误时继续编译 (使用 ninja -k)
#   -c, --clean            清理之前的构建
#   -v, --verbose          显示详细输出
#   -h, --help             显示帮助信息
#

set -e

# 默认配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROCK_DIR="${ROCK_DIR:-/data/TheRock}"
BUILD_DIR="${ROCK_DIR}/build"
JOBS="${JOBS:-$(nproc)}"
KEEP_GOING=false
CLEAN=false
VERBOSE=false

# GPU 配置 (gfx942 for MI300A/MI300X)
AMDGPU_TARGETS="${AMDGPU_TARGETS:-gfx942}"
AMDGPU_FAMILIES="${AMDGPU_FAMILIES:-gfx94X-dcgpu}"
AMDGPU_DIST_BUNDLE="${AMDGPU_DIST_BUNDLE:-gfx94X-dcgpu}"

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# 日志函数
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# 显示帮助信息
show_help() {
    cat << EOF
编译全部 ROCm 组件

使用方法:
    $0 [选项]

选项:
    -j, --jobs N          并行编译任务数 (默认: $(nproc))
    -k, --keep-going       遇到错误时继续编译 (使用 ninja -k)
    -c, --clean            清理之前的构建
    -v, --verbose          显示详细输出
    -h, --help             显示帮助信息

环境变量:
    ROCK_DIR                TheRock 源码目录 (默认: /data/TheRock)
    AMDGPU_TARGETS          GPU 目标架构 (默认: gfx942)
    AMDGPU_FAMILIES         GPU 架构族 (默认: gfx94X-dcgpu)
    AMDGPU_DIST_BUNDLE      分发包名称 (默认: gfx94X-dcgpu)

示例:
    # 使用默认配置编译
    $0

    # 使用 32 个并行任务编译
    $0 -j 32

    # 清理后重新编译
    $0 -c

    # 遇到错误时继续编译
    $0 -k

EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -j|--jobs)
            JOBS="$2"
            shift 2
            ;;
        -k|--keep-going)
            KEEP_GOING=true
            shift
            ;;
        -c|--clean)
            CLEAN=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_help
            exit 0
            ;;
        *)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
    esac
done

# 检查目录
if [[ ! -d "$ROCK_DIR" ]]; then
    log_error "TheRock 目录不存在: $ROCK_DIR"
    log_info "请设置 ROCK_DIR 环境变量或确保目录存在"
    exit 1
fi

cd "$ROCK_DIR"

# 检查虚拟环境
if [[ ! -d ".venv" ]]; then
    log_error "虚拟环境不存在，请先运行: python3 -m venv .venv && source .venv/bin/activate && pip install -r requirements.txt"
    exit 1
fi

# 激活虚拟环境
source .venv/bin/activate

# 设置 ccache
if command -v ccache &> /dev/null; then
    log_info "设置 ccache..."
    eval "$(./build_tools/setup_ccache.py)"
    ccache --version
else
    log_warn "ccache 未安装，建议安装以加速编译: sudo apt install ccache"
fi

# 清理构建目录
if [[ "$CLEAN" == "true" ]]; then
    log_info "清理构建目录..."
    rm -rf "$BUILD_DIR"
fi

# CMake 配置
log_info "配置 CMake..."
log_info "GPU 目标: $AMDGPU_TARGETS"
log_info "GPU 架构族: $AMDGPU_FAMILIES"
log_info "分发包名称: $AMDGPU_DIST_BUNDLE"
log_info "并行任务数: $JOBS"

CMAKE_ARGS=(
    -B "$BUILD_DIR"
    -GNinja
    "."
    -DTHEROCK_AMDGPU_TARGETS="$AMDGPU_TARGETS"
    -DTHEROCK_AMDGPU_FAMILIES="$AMDGPU_FAMILIES"
    -DTHEROCK_AMDGPU_DIST_BUNDLE_NAME="$AMDGPU_DIST_BUNDLE"
    -DTHEROCK_ENABLE_ROCGDB=OFF
    -DCMAKE_C_COMPILER_LAUNCHER=ccache
    -DCMAKE_CXX_COMPILER_LAUNCHER=ccache
)

if [[ "$VERBOSE" == "true" ]]; then
    CMAKE_ARGS+=(-v)
fi

if ! cmake "${CMAKE_ARGS[@]}"; then
    log_error "CMake 配置失败"
    exit 1
fi

log_info "CMake 配置完成"

# 构建
log_info "开始构建所有组件..."
log_info "这可能需要数小时，请耐心等待..."

BUILD_ARGS=(
    --build "$BUILD_DIR"
    -j "$JOBS"
)

if [[ "$KEEP_GOING" == "true" ]]; then
    log_info "启用 --keep-going 模式（遇到错误时继续）"
    BUILD_ARGS+=(-- -k 0)
fi

if [[ "$VERBOSE" == "true" ]]; then
    BUILD_ARGS+=(-v)
fi

if cmake "${BUILD_ARGS[@]}"; then
    log_info "构建完成！"
    log_info "构建产物位置: $BUILD_DIR/dist/rocm"
    
    # 显示构建统计
    if command -v ccache &> /dev/null; then
        log_info "ccache 统计:"
        ccache -s
    fi
    
    exit 0
else
    log_error "构建失败"
    exit 1
fi

