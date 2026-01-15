#!/bin/bash

# ROCm .so 版本识别脚本
# 用途: 快速识别2MB、8MB、16MB版本

set -e

# 颜色定义
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# 已知版本的MD5哈希值
MD5_16MB="cebd78255ab93f6b07bb0f958a31255e"
MD5_8MB="2cf3ff968a46d99064080ef052ece6fb"
MD5_8MB_DEBUG="cea62cc27afd709aa180258b659c6f20"
MD5_8MB_NEW="c1e6741fab9fb8b351a7f595f535ec1f"  # 8MB compiled 2025-11-27
MD5_4MB_NEW="8d0bcf473327a6c5865680fc9b53ec7d"  # 4MB compiled 2025-11-27
MD5_2MB_ORIGINAL="17f381b0fd61d7e8e9e425b593dc1cfa"
MD5_2MB_DEBUG="b7db14c5f45f688d92e06c55db2526be"
MD5_2MB_GUARD_PAGES="bd5d6f367a568e2f6a8a971d3b96dc7f"  # 2MB with Guard Pages patch (2025-12-01)

# 使用说明
usage() {
    cat << EOF
╔════════════════════════════════════════════════════════════╗
║  ROCm .so 版本识别脚本                                     ║
╚════════════════════════════════════════════════════════════╝

用法:
  $(basename $0) <文件路径>                    # 识别host上的文件
  $(basename $0) <容器名> [文件路径]           # 识别容器内的文件

示例:
  # 识别host文件
  $(basename $0) backup/libhsa-runtime64.so.1.15.0_8MB
  
  # 识别容器内文件 (默认路径)
  $(basename $0) sglang_zhendebug3
  
  # 识别容器内文件 (指定路径)
  $(basename $0) sglang_zhendebug3 /opt/rocm/lib/libhsa-runtime64.so.1.15.0

EOF
    exit 1
}

# 识别版本
identify_version() {
    local md5=$1
    local size=$2
    
    if [ "$md5" == "$MD5_16MB" ]; then
        echo -e "${BLUE}16MB 版本${NC}"
        echo "   block_size: 16 * 1024 * 1024"
        echo "   支持splits: ≤ 8"
        echo "   状态: ✅ 已测试确认"
        echo "   推荐: ⚠️  实验环境"
        return 0
    elif [ "$md5" == "$MD5_8MB" ]; then
        echo -e "${GREEN}8MB 版本 (推荐)${NC}"
        echo "   block_size: 8 * 1024 * 1024"
        echo "   支持splits: ≤ 8"
        echo "   状态: ✅ 已测试确认"
        echo "   推荐: ✅ 生产环境"
        return 0
    elif [ "$md5" == "$MD5_8MB_DEBUG" ]; then
        echo -e "${GREEN}8MB 版本 (with debug symbols)${NC}"
        echo "   block_size: 8 * 1024 * 1024"
        echo "   支持splits: ≤ 8"
        echo "   状态: ✅ 已测试确认"
        echo "   推荐: ⚠️  Debug用途"
        return 0
    elif [ "$md5" == "$MD5_8MB_NEW" ]; then
        echo -e "${GREEN}8MB 版本 (推荐) 🆕${NC}"
        echo "   block_size: 8 * 1024 * 1024"
        echo "   支持splits: ≤ 8"
        echo "   状态: ✅ 已测试确认"
        echo "   编译日期: 2025-11-27"
        echo "   推荐: ✅ 生产环境 (修复BS=64 pagefault)"
        return 0
    elif [ "$md5" == "$MD5_4MB_NEW" ]; then
        echo -e "${BLUE}4MB 版本 🆕${NC}"
        echo "   block_size: 4 * 1024 * 1024"
        echo "   支持splits: ≤ 7 (估计)"
        echo "   状态: ⚠️  BS=64 行为需测试"
        echo "   编译日期: 2025-11-27"
        echo "   推荐: ⚠️  实验用途"
        return 0
    elif [ "$md5" == "$MD5_2MB_ORIGINAL" ]; then
        echo -e "${YELLOW}2MB 版本 (原始)${NC}"
        echo "   block_size: 2 * 1024 * 1024"
        echo "   支持splits: ≤ 6"
        echo "   状态: ✅ 已识别"
        echo "   推荐: ❌ 不推荐 (BS=64会触发pagefault)"
        return 0
    elif [ "$md5" == "$MD5_2MB_DEBUG" ]; then
        echo -e "${YELLOW}2MB 版本 (with AllocateKfdMemory debug)${NC}"
        echo "   block_size: 2 * 1024 * 1024"
        echo "   支持splits: ≤ 6"
        echo "   状态: ✅ 已识别"
        echo "   特性: ✅ 包含version-block_size等debug输出"
        echo "   推荐: ⚠️  Debug/分析用途 (BS=64会触发pagefault)"
        echo "   注意: ⚠️  需要配合HSA_DISABLE_FRAGMENT_ALLOCATOR=1"
        return 0
    elif [ "$md5" == "$MD5_2MB_GUARD_PAGES" ]; then
        echo -e "${GREEN}2MB 版本 (with Guard Pages) 🆕${NC}"
        echo "   block_size: 2 * 1024 * 1024"
        echo "   支持splits: ≤ 6"
        echo "   状态: ✅ 已测试确认"
        echo "   特性: ✅ Guard Pages保护，更安全的内存分配"
        echo "   特性: ✅ 包含debug输出和完整符号表"
        echo "   编译日期: 2025-12-01"
        echo "   推荐: ⚠️  Debug/测试用途 (BS=64会触发pagefault)"
        echo "   注意: ⚠️  需要配合HSA_DISABLE_FRAGMENT_ALLOCATOR=1"
        return 0
    else
        # 根据大小猜测
        if [[ "$size" =~ "3.4M" ]] || [[ "$size" =~ "3.5M" ]]; then
            echo -e "${YELLOW}可能是 2MB 版本 (原始)${NC}"
            echo "   block_size: 2 * 1024 * 1024 (推测)"
            echo "   支持splits: ≤ 6"
            echo "   状态: ⚠️  MD5未记录，基于大小推测"
            echo "   推荐: ❌ 不推荐使用"
            return 0
        else
            echo -e "${RED}未知版本${NC}"
            echo "   MD5: $md5"
            echo "   大小: $size"
            echo "   状态: ⚠️  无法识别"
            return 1
        fi
    fi
}

# 主程序
main() {
    if [ $# -eq 0 ]; then
        usage
    fi
    
    echo -e "${BLUE}╔════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║  ROCm .so 版本识别结果                 ║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════╝${NC}"
    echo ""
    
    # 判断是host文件还是容器文件
    if [ $# -eq 1 ]; then
        # 单个参数 - 可能是host文件或容器名
        if [ -f "$1" ]; then
            # Host文件
            FILE_PATH="$1"
            echo "文件: $FILE_PATH"
            SIZE=$(ls -lh "$FILE_PATH" | awk '{print $5}')
            echo "大小: $SIZE"
            MD5=$(md5sum "$FILE_PATH" | awk '{print $1}')
            echo "MD5:  $MD5"
            echo ""
            identify_version "$MD5" "$SIZE"
        else
            # 假设是容器名，使用默认路径
            CONTAINER=$1
            FILE_PATH="/opt/rocm/lib/libhsa-runtime64.so.1.15.0"
            
            # 检查容器是否存在
            if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
                echo -e "${RED}错误: 容器 '$CONTAINER' 不存在${NC}"
                exit 1
            fi
            
            # 检查容器是否运行
            if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
                echo -e "${YELLOW}警告: 容器 '$CONTAINER' 未运行，启动中...${NC}"
                docker start "$CONTAINER" > /dev/null
                sleep 2
            fi
            
            echo "容器: $CONTAINER"
            echo "文件: $FILE_PATH"
            
            # 获取文件信息
            SIZE=$(docker exec "$CONTAINER" ls -lh "$FILE_PATH" 2>/dev/null | awk '{print $5}')
            if [ -z "$SIZE" ]; then
                echo -e "${RED}错误: 文件不存在${NC}"
                exit 1
            fi
            echo "大小: $SIZE"
            
            MD5=$(docker exec "$CONTAINER" md5sum "$FILE_PATH" 2>/dev/null | awk '{print $1}')
            echo "MD5:  $MD5"
            echo ""
            
            identify_version "$MD5" "$SIZE"
        fi
    elif [ $# -eq 2 ]; then
        # 两个参数 - 容器名和文件路径
        CONTAINER=$1
        FILE_PATH=$2
        
        # 检查容器是否存在
        if ! docker ps -a --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
            echo -e "${RED}错误: 容器 '$CONTAINER' 不存在${NC}"
            exit 1
        fi
        
        # 检查容器是否运行
        if ! docker ps --format "{{.Names}}" | grep -q "^${CONTAINER}$"; then
            echo -e "${YELLOW}警告: 容器 '$CONTAINER' 未运行，启动中...${NC}"
            docker start "$CONTAINER" > /dev/null
            sleep 2
        fi
        
        echo "容器: $CONTAINER"
        echo "文件: $FILE_PATH"
        
        # 获取文件信息
        SIZE=$(docker exec "$CONTAINER" ls -lh "$FILE_PATH" 2>/dev/null | awk '{print $5}')
        if [ -z "$SIZE" ]; then
            echo -e "${RED}错误: 文件不存在${NC}"
            exit 1
        fi
        echo "大小: $SIZE"
        
        MD5=$(docker exec "$CONTAINER" md5sum "$FILE_PATH" 2>/dev/null | awk '{print $1}')
        echo "MD5:  $MD5"
        echo ""
        
        identify_version "$MD5" "$SIZE"
    else
        usage
    fi
}

main "$@"

