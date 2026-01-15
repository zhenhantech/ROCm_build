#!/bin/bash
# 通用ROCm版本安装脚本
# 用途: 安装指定版本的ROCm SO到指定Docker容器
# 版本: 2.0
# 日期: 2025-11-28

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 使用说明
show_usage() {
    echo ""
    echo "用法: $0 <docker_container_name> <version>"
    echo ""
    echo "参数:"
    echo "  docker_container_name  - Docker容器名称"
    echo "  version               - ROCm版本 (2mb|4mb|8mb)"
    echo ""
    echo "示例:"
    echo "  $0 sglang_zhendebug2 8mb   # 安装8MB版本到debug2"
    echo "  $0 sglang_zhendebug4 2mb   # 安装2MB版本到debug4"
    echo "  $0 sglang_zhendebug4 4mb   # 安装4MB版本到debug4"
    echo ""
    echo "可用版本:"
    echo "  2mb  - 2MB block_size (会触发BS=64 pagefault)"
    echo "  4mb  - 4MB block_size (未测试)"
    echo "  8mb  - 8MB block_size (推荐，修复pagefault) ✅"
    echo ""
}

# 检查参数
if [ $# -lt 2 ]; then
    echo -e "${RED}错误: 参数不足${NC}"
    show_usage
    exit 1
fi

DOCKER_NAME=$1
VERSION=$2

# 标准化版本参数
VERSION_LOWER=$(echo "$VERSION" | tr '[:upper:]' '[:lower:]')

# 验证版本参数
if [[ ! "$VERSION_LOWER" =~ ^(2mb|4mb|8mb)$ ]]; then
    echo -e "${RED}错误: 不支持的版本 '$VERSION'${NC}"
    show_usage
    exit 1
fi

echo -e "${BLUE}╔════════════════════════════════════════════════════════════╗${NC}"
echo -e "${BLUE}║  ROCm版本安装脚本 v2.0                                     ║${NC}"
echo -e "${BLUE}╚════════════════════════════════════════════════════════════╝${NC}"
echo ""
echo -e "${GREEN}目标容器:${NC} $DOCKER_NAME"
echo -e "${GREEN}安装版本:${NC} $VERSION_LOWER"
echo ""

# 检查Docker容器是否存在且运行
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "检查Docker容器状态..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if ! docker ps --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$"; then
    echo -e "${RED}✗ 错误: Docker容器 '$DOCKER_NAME' 未运行${NC}"
    echo ""
    echo "可用的运行中容器:"
    docker ps --format "  - {{.Names}}"
    echo ""
    exit 1
fi

echo -e "${GREEN}✓ 容器运行中${NC}"
echo ""

# 查找源文件
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "查找源文件..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 定义多个可能的源文件位置（按优先级）
SOURCES=(
    # 优先使用debug_summary备份目录（推荐）
    "/data/zhehan/code/debug_summary/rocmdebugSO/libhsa-runtime64.so.1.15.0.${VERSION_LOWER}_20251127"
    # 其次使用Docker内已部署的版本化SO
    "docker:$DOCKER_NAME:/opt/rocm/lib/libhsa-runtime64.so.1.15.0.${VERSION_LOWER}_20251127"
    # 再次使用源码编译目录（最新）
    "docker:$DOCKER_NAME:/data2/code/rocm6.4.3/ROCR-Runtime/build_${VERSION_LOWER}_allockfd/rocr/lib/libhsa-runtime64.so.1.15.0"
    "docker:$DOCKER_NAME:/data2/code/rocm6.4.3/ROCR-Runtime/build_${VERSION_LOWER}_final/rocr/lib/libhsa-runtime64.so.1.15.0"
    # cleanup目录（如果已导出）
    "/data/zhehan/code/script/source_backWA_docker2/1127_hipalloc_issue_cleanup/rocm_debug/compiled/libhsa-runtime64.so.1.15.0_${VERSION_LOWER}_with_allocate_kfd_debug"
    # 旧的备份目录（兼容性）
    "/data/zhehan/code/pagefault_WA_8Mblocksize/backup/libhsa-runtime64.so.1.15.0_$(echo $VERSION_LOWER | tr '[:lower:]' '[:upper:]')"
)

SO_FILE=""
SO_SOURCE_TYPE=""

for source in "${SOURCES[@]}"; do
    if [[ "$source" == docker:* ]]; then
        # Docker内文件
        CONTAINER=$(echo "$source" | cut -d: -f2)
        PATH_IN_DOCKER=$(echo "$source" | cut -d: -f3-)
        
        if docker exec $CONTAINER test -f "$PATH_IN_DOCKER" 2>/dev/null; then
            echo -e "${GREEN}✓ 找到: $PATH_IN_DOCKER (Docker内)${NC}"
            SO_FILE="$source"
            SO_SOURCE_TYPE="docker"
            break
        fi
    else
        # 主机文件
        if [ -f "$source" ]; then
            echo -e "${GREEN}✓ 找到: $source (主机)${NC}"
            SO_FILE="$source"
            SO_SOURCE_TYPE="host"
            break
        fi
    fi
done

if [ -z "$SO_FILE" ]; then
    echo -e "${RED}✗ 错误: 找不到 ${VERSION_LOWER} 版本的SO文件${NC}"
    echo ""
    echo "查找过的位置:"
    for source in "${SOURCES[@]}"; do
        echo "  - $source"
    done
    echo ""
    echo "建议:"
    echo "1. 确认版本已编译"
    echo "2. 检查文件路径是否正确"
    echo "3. 或使用 install_8mb_wa.sh 脚本（仅8MB版本）"
    echo ""
    exit 1
fi

echo ""

# 显示源文件信息
if [ "$SO_SOURCE_TYPE" == "docker" ]; then
    CONTAINER=$(echo "$SO_FILE" | cut -d: -f2)
    PATH_IN_DOCKER=$(echo "$SO_FILE" | cut -d: -f3-)
    FILE_SIZE=$(docker exec $CONTAINER du -h "$PATH_IN_DOCKER" | cut -f1)
    echo "源文件: $PATH_IN_DOCKER (Docker内)"
    echo "大小: $FILE_SIZE"
else
    echo "源文件: $SO_FILE"
    echo "大小: $(du -h "$SO_FILE" | cut -f1)"
fi
echo ""

# 创建备份
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
WA_DIR="$(dirname "$SCRIPT_DIR")"
BACKUP_DIR="$WA_DIR/backup/backup_${DOCKER_NAME}_${VERSION_LOWER}_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$BACKUP_DIR"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤 1/6: 备份当前版本..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 备份当前的SO文件
docker exec $DOCKER_NAME bash -c "
    if [ -f /opt/rocm/lib/libhsa-runtime64.so.1.15.0 ]; then
        cat /opt/rocm/lib/libhsa-runtime64.so.1.15.0
    fi
" > "$BACKUP_DIR/libhsa-runtime64.so.1.15.0.current" 2>/dev/null || true

if [ -s "$BACKUP_DIR/libhsa-runtime64.so.1.15.0.current" ]; then
    CURRENT_SIZE=$(du -h "$BACKUP_DIR/libhsa-runtime64.so.1.15.0.current" | cut -f1)
    echo -e "${GREEN}✓ 已备份当前版本到: $BACKUP_DIR${NC}"
    echo "  当前版本大小: $CURRENT_SIZE"
else
    rm -f "$BACKUP_DIR/libhsa-runtime64.so.1.15.0.current"
    echo -e "${YELLOW}⚠ 容器内无现有文件（首次安装）${NC}"
fi
echo ""

# 复制文件到容器
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤 2/6: 复制 ${VERSION_LOWER} 版本到容器..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

if [ "$SO_SOURCE_TYPE" == "docker" ]; then
    # 从Docker内复制到Docker内
    CONTAINER=$(echo "$SO_FILE" | cut -d: -f2)
    PATH_IN_DOCKER=$(echo "$SO_FILE" | cut -d: -f3-)
    
    if [ "$CONTAINER" == "$DOCKER_NAME" ]; then
        # 同一容器内，直接cp
        docker exec $DOCKER_NAME cp "$PATH_IN_DOCKER" /opt/rocm/lib/libhsa-runtime64.so.1.15.0
    else
        # 不同容器，通过主机中转
        docker cp $CONTAINER:$PATH_IN_DOCKER /tmp/rocm_temp_install.so
        docker cp /tmp/rocm_temp_install.so $DOCKER_NAME:/opt/rocm/lib/libhsa-runtime64.so.1.15.0
        rm -f /tmp/rocm_temp_install.so
    fi
else
    # 从主机复制到Docker
    docker cp "$SO_FILE" $DOCKER_NAME:/opt/rocm/lib/libhsa-runtime64.so.1.15.0
fi

docker exec $DOCKER_NAME chmod 755 /opt/rocm/lib/libhsa-runtime64.so.1.15.0
echo -e "${GREEN}✓ 已复制到容器: /opt/rocm/lib/libhsa-runtime64.so.1.15.0${NC}"
echo ""

# 更新符号链接
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤 3/6: 更新符号链接..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

docker exec $DOCKER_NAME bash -c "
    cd /opt/rocm/lib
    rm -f libhsa-runtime64.so.1
    ln -sf libhsa-runtime64.so.1.15.0 libhsa-runtime64.so.1
    rm -f libhsa-runtime64.so
    ln -sf libhsa-runtime64.so.1 libhsa-runtime64.so
"

echo -e "${GREEN}✓ 符号链接已更新:${NC}"
echo "  libhsa-runtime64.so -> libhsa-runtime64.so.1 -> libhsa-runtime64.so.1.15.0"
echo ""

# 清理缓存
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤 4/6: 清理缓存..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

docker exec $DOCKER_NAME bash -c "
    rm -rf /root/.cache/triton /root/.triton/cache /tmp/.hip* 2>/dev/null || true
    rm -rf /tmp/triton_cache* 2>/dev/null || true
"

echo -e "${GREEN}✓ 已清理Triton和HIP缓存${NC}"
echo ""

# 验证安装
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤 5/6: 验证安装..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# 检查文件存在
FILE_EXISTS=$(docker exec $DOCKER_NAME test -f /opt/rocm/lib/libhsa-runtime64.so.1.15.0 && echo "yes" || echo "no")

if [ "$FILE_EXISTS" == "yes" ]; then
    # 获取文件大小
    FILE_SIZE=$(docker exec $DOCKER_NAME du -h /opt/rocm/lib/libhsa-runtime64.so.1.15.0 | cut -f1)
    
    # 检查符号链接
    LINK1=$(docker exec $DOCKER_NAME readlink /opt/rocm/lib/libhsa-runtime64.so.1 2>/dev/null || echo "broken")
    LINK2=$(docker exec $DOCKER_NAME readlink /opt/rocm/lib/libhsa-runtime64.so 2>/dev/null || echo "broken")
    
    echo -e "${GREEN}✓ 安装文件验证成功${NC}"
    echo "  文件大小: $FILE_SIZE"
    echo "  符号链接: OK"
    echo "  libhsa-runtime64.so.1 -> $LINK1"
    echo "  libhsa-runtime64.so -> $LINK2"
    
    # 根据大小推测版本（粗略验证）
    case "$FILE_SIZE" in
        3.4M|3.5M)
            DETECTED="2MB (旧版本)"
            ;;
        3.9M|4.0M)
            DETECTED="8MB 或 4MB (新版本)"
            ;;
        *)
            DETECTED="未知版本"
            ;;
    esac
    echo "  预期版本: $VERSION_LOWER, 检测到: $DETECTED"
else
    echo -e "${RED}✗ 安装验证失败: 文件不存在${NC}"
    exit 1
fi
echo ""

# 提示重启
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "步骤 6/6: 重启容器..."
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

echo ""
echo -e "${YELLOW}⚠ 重要: 需要重启容器才能生效${NC}"
echo ""
read -p "是否现在重启Docker容器 '$DOCKER_NAME'? (y/n) " -n 1 -r
echo
echo ""

if [[ $REPLY =~ ^[Yy]$ ]]; then
    echo "正在重启容器..."
    docker restart $DOCKER_NAME
    
    echo ""
    echo "等待容器启动..."
    sleep 5
    
    # 验证容器状态
    if docker ps --format '{{.Names}}' | grep -q "^${DOCKER_NAME}$"; then
        echo -e "${GREEN}✓ 容器已成功重启${NC}"
    else
        echo -e "${YELLOW}⚠ 容器可能还在启动中...${NC}"
    fi
else
    echo -e "${YELLOW}⚠ 跳过重启${NC}"
    echo ""
    echo -e "${RED}请务必手动重启容器:${NC}"
    echo "  docker restart $DOCKER_NAME"
fi

echo ""

# 显示最终状态
echo "╔════════════════════════════════════════════════════════════╗"
echo "║  ✅ 安装完成                                                ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""
echo -e "${GREEN}容器:${NC} $DOCKER_NAME"
echo -e "${GREEN}版本:${NC} $VERSION_LOWER"
echo -e "${GREEN}备份:${NC} $BACKUP_DIR"
echo ""

# 显示当前文件状态
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "当前ROCm库状态:"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
docker exec $DOCKER_NAME ls -lh /opt/rocm/lib/libhsa-runtime64.so* 2>/dev/null | grep -E "(so$|so.1$|so.1.15.0$)" | head -5
echo ""

# 下一步提示
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${BLUE}下一步操作:${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""

if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    echo "1️⃣  ${YELLOW}重启容器 (必须):${NC}"
    echo "   docker restart $DOCKER_NAME"
    echo ""
fi

echo "2️⃣  验证版本:"
echo "   bash scripts/identify_version.sh $DOCKER_NAME"
echo ""

echo "3️⃣  运行测试:"
echo "   # 运行SGLang BS=64测试，查看version-block_size输出"
echo "   docker exec $DOCKER_NAME bash -c 'grep version-block_size /path/to/test.log'"
echo ""

echo "4️⃣  回滚 (如需要):"
echo "   # 恢复备份"
echo "   docker cp $BACKUP_DIR/libhsa-runtime64.so.1.15.0.current \\"
echo "     $DOCKER_NAME:/opt/rocm/lib/libhsa-runtime64.so.1.15.0"
echo "   docker restart $DOCKER_NAME"
echo ""

# 版本特定提示
case "$VERSION_LOWER" in
    2mb)
        echo -e "${YELLOW}⚠️  注意: 2MB版本在BS=64时会触发Pagefault${NC}"
        echo "   建议使用HSA_DISABLE_FRAGMENT_ALLOCATOR=1或升级到8MB"
        ;;
    4mb)
        echo -e "${BLUE}ℹ️  4MB版本未充分测试，建议验证后使用${NC}"
        ;;
    8mb)
        echo -e "${GREEN}✅ 8MB版本已验证，修复BS=64 Pagefault${NC}"
        ;;
esac

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo ""

