#!/bin/bash
#
# package_rpm.sh - 将 ROCm 构建产物打包为 RedHat/CentOS .rpm 包
#
# 使用方法:
#   ./package_rpm.sh [选项]
#
# 选项:
#   -o, --output DIR      输出目录 (默认: ./packages/rpm)
#   -v, --version VER     版本号 (默认: 从构建产物检测)
#   -r, --release REL     发布版本 (默认: 1)
#   -a, --arch ARCH       架构 (默认: x86_64)
#   -s, --spec FILE       自定义 spec 文件
#   -h, --help            显示帮助信息
#

set -e

# 默认配置
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROCK_DIR="${ROCK_DIR:-/data/TheRock}"
BUILD_DIR="${ROCK_DIR}/build"
DIST_DIR="${BUILD_DIR}/dist/rocm"
OUTPUT_DIR="${SCRIPT_DIR}/packages/rpm"
VERSION="${VERSION:-}"
RELEASE="${RELEASE:-1}"
ARCH="${ARCH:-x86_64}"
SPEC_FILE=""

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
将 ROCm 构建产物打包为 RedHat/CentOS .rpm 包

使用方法:
    $0 [选项]

选项:
    -o, --output DIR      输出目录 (默认: ./packages/rpm)
    -v, --version VER     版本号 (默认: 从构建产物检测)
    -r, --release REL     发布版本 (默认: 1)
    -a, --arch ARCH       架构 (默认: x86_64)
    -s, --spec FILE       自定义 spec 文件
    -h, --help            显示帮助信息

环境变量:
    ROCK_DIR                TheRock 源码目录 (默认: /data/TheRock)

示例:
    # 使用默认配置打包
    $0

    # 指定版本号和发布版本
    $0 -v 7.2.0 -r 2

    # 指定架构
    $0 -a aarch64

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
        -r|--release)
            RELEASE="$2"
            shift 2
            ;;
        -a|--arch)
            ARCH="$2"
            shift 2
            ;;
        -s|--spec)
            SPEC_FILE="$2"
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
if ! command -v rpmbuild &> /dev/null; then
    log_error "需要 rpmbuild 工具，请安装: sudo yum install rpm-build 或 sudo dnf install rpm-build"
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
log_info "  发布: $RELEASE"
log_info "  架构: $ARCH"
log_info "  源目录: $DIST_DIR"
log_info "  输出目录: $OUTPUT_DIR"

# 创建输出目录
mkdir -p "$OUTPUT_DIR"

# 创建临时目录
TEMP_DIR=$(mktemp -d)
trap "rm -rf $TEMP_DIR" EXIT

RPMBUILD_DIR="$TEMP_DIR/rpmbuild"
mkdir -p "$RPMBUILD_DIR"/{BUILD,BUILDROOT,RPMS,SOURCES,SPECS,SRPMS}

PACKAGE_NAME="rocm"

# 创建源代码压缩包
log_info "创建源代码压缩包..."
tar -czf "$RPMBUILD_DIR/SOURCES/${PACKAGE_NAME}-${VERSION}.tar.gz" -C "$(dirname "$DIST_DIR")" "$(basename "$DIST_DIR")"

# 创建 spec 文件
if [[ -n "$SPEC_FILE" && -f "$SPEC_FILE" ]]; then
    log_info "使用自定义 spec 文件: $SPEC_FILE"
    cp "$SPEC_FILE" "$RPMBUILD_DIR/SPECS/${PACKAGE_NAME}.spec"
else
    log_info "创建默认 spec 文件..."
    
    # 计算安装大小（KB）
    INSTALLED_SIZE=$(du -sk "$DIST_DIR" | cut -f1)
    
    cat > "$RPMBUILD_DIR/SPECS/${PACKAGE_NAME}.spec" << EOF
%define _topdir %(pwd)
%define name ${PACKAGE_NAME}
%define version ${VERSION}
%define release ${RELEASE}
%define arch ${ARCH}

Summary: ROCm Platform for GPU Computing
Name: %{name}
Version: %{version}
Release: %{release}
License: MIT and BSD
Group: Development/Tools
Source0: %{name}-%{version}.tar.gz
BuildArch: %{arch}
Requires: glibc >= 2.17, libstdc++ >= 4.9, libgcc >= 4.0

%description
ROCm is an open-source platform for GPU computing. This package contains
the complete ROCm stack including:
- HIP runtime and compiler
- Math libraries (rocBLAS, rocSPARSE, rocSOLVER, rocFFT, rocRAND)
- Deep learning library (MIOpen)
- Communication library (RCCL)
- Profiling and debugging tools
- GPU architecture: gfx942 (MI300A/MI300X)

%prep
%setup -q -n rocm

%build
# No build step needed, files are pre-built

%install
rm -rf %{buildroot}
mkdir -p %{buildroot}/opt/rocm
cp -r * %{buildroot}/opt/rocm/

%post
if [ -x /sbin/ldconfig ]; then
    /sbin/ldconfig /opt/rocm/lib 2>/dev/null || true
fi

%postun
if [ -x /sbin/ldconfig ]; then
    /sbin/ldconfig 2>/dev/null || true
fi

%files
%defattr(-,root,root,-)
/opt/rocm

%changelog
* $(date '+%a %b %d %Y') ROCm Build <rocm-build@example.com> - ${VERSION}-${RELEASE}
- Initial package for ROCm ${VERSION}
EOF
fi

# 构建 RPM 包
log_info "构建 .rpm 包..."

cd "$RPMBUILD_DIR"

if rpmbuild -bb --define "_topdir $RPMBUILD_DIR" SPECS/${PACKAGE_NAME}.spec; then
    # 查找生成的 RPM 文件
    RPM_FILE=$(find RPMS -name "*.rpm" | head -1)
    
    if [[ -n "$RPM_FILE" ]]; then
        OUTPUT_RPM="${OUTPUT_DIR}/$(basename "$RPM_FILE")"
        cp "$RPM_FILE" "$OUTPUT_RPM"
        log_info "打包完成: $OUTPUT_RPM"
        
        # 显示包信息
        log_info "包信息:"
        rpm -qip "$OUTPUT_RPM" | head -20
        
        # 显示包大小
        PACKAGE_SIZE=$(du -h "$OUTPUT_RPM" | cut -f1)
        log_info "包大小: $PACKAGE_SIZE"
        
        exit 0
    else
        log_error "未找到生成的 RPM 文件"
        exit 1
    fi
else
    log_error "RPM 构建失败"
    exit 1
fi

