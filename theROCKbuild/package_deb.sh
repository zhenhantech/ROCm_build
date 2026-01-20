#!/bin/bash
#
# package_deb.sh - 将 ROCm 构建产物打包为 Debian/Ubuntu .deb 包
#
# 使用方法:
#   ./package_deb.sh [选项]
#
# 选项:
#   -o, --output DIR      输出目录 (默认: ./packages/deb)
#   -v, --version VER     版本号 (默认: 从构建产物检测)
#   -a, --arch ARCH       架构 (默认: amd64)
#   -c, --control DIR     自定义 control 文件目录
#   -h, --help            显示帮助信息
#

set -e

# 默认配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROCK_DIR="${ROCK_DIR:-/data/TheRock}"
BUILD_DIR="${ROCK_DIR}/build"
DIST_DIR="${BUILD_DIR}/dist/rocm"
OUTPUT_DIR="${SCRIPT_DIR}/packages/deb"
VERSION="${VERSION:-}"
ARCH="${ARCH:-amd64}"
CONTROL_DIR=""

# 颜色输出
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

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
将 ROCm 构建产物打包为 Debian/Ubuntu .deb 包

使用方法:
    $0 [选项]

选项:
    -o, --output DIR      输出目录 (默认: ./packages/deb)
    -v, --version VER     版本号 (默认: 从构建产物检测)
    -a, --arch ARCH       架构 (默认: amd64)
    -c, --control DIR     自定义 control 文件目录
    -h, --help            显示帮助信息

环境变量:
    ROCK_DIR                TheRock 源码目录 (默认: /data/TheRock)

示例:
    # 使用默认配置打包
    $0

    # 指定版本号和输出目录
    $0 -v 7.2.0 -o /tmp/rocm-deb

    # 指定架构
    $0 -a arm64

EOF
}

# 解析命令行参数
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -v|--version)
            VERSION="$2"
            shift 2
            ;;
        -a|--arch)
            ARCH="$2"
            shift 2
            ;;
        -c|--control)
            CONTROL_DIR="$2"
            shift 2
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

# 检查依赖
if ! command -v dpkg-deb &> /dev/null; then
    log_error "需要 dpkg-deb 工具，请安装: sudo apt install dpkg-dev"
    exit 1
fi

# 检查构建产物
if [[ ! -d "$DIST_DIR" ]]; then
    log_error "构建产物目录不存在: $DIST_DIR"
    log_info "请先运行构建: ./build_all.sh"
    exit 1
fi

# 检测版本号
if [[ -z "$VERSION" ]]; then
    # 尝试从构建产物中检测版本
    if [[ -f "$DIST_DIR/include/hip/hip_version.h" ]]; then
        VERSION=$(grep -E "HIP_VERSION_MAJOR|HIP_VERSION_MINOR|HIP_VERSION_PATCH" "$DIST_DIR/include/hip/hip_version.h" | \
                  awk '{print $3}' | tr '\n' '.' | sed 's/\.$//' || echo "7.2.0")
    else
        VERSION="7.2.0"
        log_warn "无法检测版本号，使用默认版本: $VERSION"
    fi
fi

log_info "打包配置:"
log_info "  版本: $VERSION"
log_info "  架构: $ARCH"
log_info "  源目录: $DIST_DIR"
log_info "  输出目录: $OUTPUT_DIR"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 创建临时打包目录
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

PACKAGE_NAME="rocm"
PACKAGE_DIR="$TEMP_DIR/${PACKAGE_NAME}_${VERSION}_${ARCH}"

mkdir -p "$PACKAGE_DIR/DEBIAN"
mkdir -p "$PACKAGE_DIR/opt/rocm"

# 复制构建产物
log_info "复制构建产物..."
cp -r "$DIST_DIR"/* "$PACKAGE_DIR/opt/rocm/"

# 创建 control 文件
log_info "创建 DEBIAN/control 文件..."

# 计算安装大小（KB）
INSTALLED_SIZE=$(du -sk "$PACKAGE_DIR/opt" | cut -f1)

cat > "$PACKAGE_DIR/DEBIAN/control" << EOF
Package: ${PACKAGE_NAME}
Version: ${VERSION}
Architecture: ${ARCH}
Maintainer: ROCm Build <rocm-build@example.com>
Installed-Size: ${INSTALLED_SIZE}
Depends: libc6 (>= 2.17), libstdc++6 (>= 4.9), libgcc-s1 (>= 4.0)
Section: devel
Priority: optional
Description: ROCm Platform for GPU Computing
 ROCm is an open-source platform for GPU computing. This package contains
 the complete ROCm stack including:
 - HIP runtime and compiler
 - Math libraries (rocBLAS, rocSPARSE, rocSOLVER, rocFFT, rocRAND)
 - Deep learning library (MIOpen)
 - Communication library (RCCL)
 - Profiling and debugging tools
 - GPU architecture: gfx942 (MI300A/MI300X)
EOF

# 创建 postinst 脚本
cat > "$PACKAGE_DIR/DEBIAN/postinst" << 'EOF'
#!/bin/bash
set -e

# 更新动态链接库缓存
if command -v ldconfig &> /dev/null; then
    ldconfig /opt/rocm/lib 2>/dev/null || true
fi

# 设置环境变量（可选）
# echo 'export ROCM_PATH=/opt/rocm' >> /etc/environment
# echo 'export PATH=$ROCM_PATH/bin:$PATH' >> /etc/environment
# echo 'export LD_LIBRARY_PATH=$ROCM_PATH/lib:$LD_LIBRARY_PATH' >> /etc/environment

exit 0
EOF

chmod +x "$PACKAGE_DIR/DEBIAN/postinst"

# 创建 prerm 脚本
cat > "$PACKAGE_DIR/DEBIAN/prerm" << 'EOF'
#!/bin/bash
set -e

# 更新动态链接库缓存
if command -v ldconfig &> /dev/null; then
    ldconfig 2>/dev/null || true
fi

exit 0
EOF

chmod +x "$PACKAGE_DIR/DEBIAN/prerm"

# 创建 postrm 脚本
cat > "$PACKAGE_DIR/DEBIAN/postrm" << 'EOF'
#!/bin/bash
set -e

# 更新动态链接库缓存
if command -v ldconfig &> /dev/null; then
    ldconfig 2>/dev/null || true
fi

exit 0
EOF

chmod +x "$PACKAGE_DIR/DEBIAN/postrm"

# 如果提供了自定义 control 目录，复制文件
if [[ -n "$CONTROL_DIR" && -d "$CONTROL_DIR" ]]; then
    log_info "使用自定义 control 文件..."
    cp -r "$CONTROL_DIR"/* "$PACKAGE_DIR/DEBIAN/" 2>/dev/null || true
fi

# 构建 deb 包
log_info "构建 .deb 包..."
DEB_FILE="${OUTPUT_DIR}/${PACKAGE_NAME}_${VERSION}_${ARCH}.deb"

if dpkg-deb --build "$PACKAGE_DIR" "$DEB_FILE"; then
    log_info "打包完成: $DEB_FILE"
    
    # 显示包信息
    log_info "包信息:"
    dpkg-deb -I "$DEB_FILE" | head -20
    
    # 显示包大小
    PACKAGE_SIZE=$(du -h "$DEB_FILE" | cut -f1)
    log_info "包大小: $PACKAGE_SIZE"
    
    exit 0
else
    log_error "打包失败"
    exit 1
fi

