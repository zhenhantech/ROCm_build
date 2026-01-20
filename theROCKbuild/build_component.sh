#!/bin/bash
#
# build_component.sh - 编译指定的 ROCm 组件
#
# 使用方法:
#   ./build_component.sh <component_name> [选项]
#
# 组件名称示例:
#   rocBLAS, hipBLAS, rocSPARSE, hipSPARSE, rocSOLVER, hipSOLVER
#   MIOpen, hipDNN, rccl, rocFFT, hipFFT, rocRAND, hipRAND
#
# 选项:
#   -j, --jobs N          并行编译任务数 (默认: $(nproc))
#   -k, --keep-going       遇到错误时继续编译
#   -c, --clean            清理组件构建目录
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

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
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

log_component() {
    echo -e "${BLUE}[COMPONENT]${NC} $*"
}

# 显示帮助信息
show_help() {
    cat << EOF
编译指定的 ROCm 组件

使用方法:
    $0 <component_name> [选项]

组件名称:
    数学库:
        rocBLAS, hipBLAS, hipBLASLt
        rocSPARSE, hipSPARSE, hipSPARSELt
        rocSOLVER, hipSOLVER
        rocFFT, hipFFT
        rocRAND, hipRAND
    
    深度学习:
        MIOpen, hipDNN
    
    通信:
        rccl
    
    其他:
        rocprofiler, roctracer, rocm-smi

选项:
    -j, --jobs N          并行编译任务数 (默认: $(nproc))
    -k, --keep-going       遇到错误时继续编译
    -c, --clean            清理组件构建目录
    -v, --verbose          显示详细输出
    -h, --help             显示帮助信息

环境变量:
    ROCK_DIR                TheRock 源码目录 (默认: /data/TheRock)

示例:
    # 编译 rocBLAS
    $0 rocBLAS

    # 编译 hipBLAS，使用 32 个并行任务
    $0 hipBLAS -j 32

    # 清理后重新编译 rocSPARSE
    $0 rocSPARSE -c

    # 编译 MIOpen，遇到错误时继续
    $0 MIOpen -k

EOF
}

# 解析命令行参数
COMPONENT=""
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
        -*)
            log_error "未知选项: $1"
            show_help
            exit 1
            ;;
        *)
            if [[ -z "$COMPONENT" ]]; then
                COMPONENT="$1"
            else
                log_error "只能指定一个组件名称"
                show_help
                exit 1
            fi
            shift
            ;;
    esac
done

# 检查组件名称
if [[ -z "$COMPONENT" ]]; then
    log_error "请指定要编译的组件名称"
    show_help
    exit 1
fi

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
    eval "$(./build_tools/setup_ccache.py)" 2>/dev/null || true
else
    log_warn "ccache 未安装，建议安装以加速编译"
fi

# 检查构建目录是否存在
if [[ ! -d "$BUILD_DIR" ]]; then
    log_warn "构建目录不存在，需要先运行完整配置"
    log_info "运行: ./build_all.sh 或先运行 CMake 配置"
    exit 1
fi

# 清理组件构建目录
if [[ "$CLEAN" == "true" ]]; then
    log_info "清理组件构建目录..."
    # 查找组件相关的构建目录
    COMPONENT_BUILD_DIRS=$(find "$BUILD_DIR" -type d -name "*${COMPONENT}*" -o -name "*$(echo $COMPONENT | tr '[:upper:]' '[:lower:]')*" 2>/dev/null || true)
    if [[ -n "$COMPONENT_BUILD_DIRS" ]]; then
        echo "$COMPONENT_BUILD_DIRS" | while read dir; do
            if [[ -d "$dir" ]]; then
                log_info "删除: $dir"
                rm -rf "$dir"
            fi
        done
    else
        log_warn "未找到组件构建目录，可能组件名称不正确或尚未配置"
    fi
fi

# 构建指定组件
log_component "编译组件: $COMPONENT"
log_info "并行任务数: $JOBS"

BUILD_ARGS=(
    --build "$BUILD_DIR"
    --target "$COMPONENT"
    -j "$JOBS"
)

if [[ "$KEEP_GOING" == "true" ]]; then
    log_info "启用 --keep-going 模式"
    BUILD_ARGS+=(-- -k 0)
fi

if [[ "$VERBOSE" == "true" ]]; then
    BUILD_ARGS+=(-v)
fi

if cmake "${BUILD_ARGS[@]}"; then
    log_info "组件 $COMPONENT 构建完成！"
    
    # 显示构建产物位置
    COMPONENT_DIST=$(find "$BUILD_DIR/dist" -type d -name "*${COMPONENT}*" -o -name "*$(echo $COMPONENT | tr '[:upper:]' '[:lower:]')*" 2>/dev/null | head -1)
    if [[ -n "$COMPONENT_DIST" ]]; then
        log_info "构建产物位置: $COMPONENT_DIST"
    fi
    
    # 显示 ccache 统计
    if command -v ccache &> /dev/null; then
        log_info "ccache 统计:"
        ccache -s | head -10
    fi
    
    exit 0
else
    log_error "组件 $COMPONENT 构建失败"
    exit 1
fi

