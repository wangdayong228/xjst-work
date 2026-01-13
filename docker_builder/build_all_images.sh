#!/bin/bash
# 联盟链节点镜像构建脚本
# 一键构建node-1到node-4的所有Docker镜像

set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD_DIR="$SCRIPT_DIR/build"
CONFIGS_DIR="$SCRIPT_DIR/configs"

# 镜像配置
IMAGE_NAME="consortium-blockchain"
IMAGE_TAG="latest"

echo "🏗️  开始构建联盟链节点镜像..."
echo "📍 构建目录: $BUILD_DIR"
echo "📍 配置目录: $CONFIGS_DIR"

# 检查必要文件
echo "🔍 检查必要文件..."

# 检查conflux二进制文件
if [ ! -f "$SCRIPT_DIR/conflux" ]; then
    echo "❌ 错误: conflux二进制文件不存在"
    echo "请将conflux二进制文件放置在: $SCRIPT_DIR/conflux"
    exit 1
fi
echo "✅ conflux二进制文件检查通过"

# 检查配置目录
if [ ! -d "$CONFIGS_DIR" ]; then
    echo "❌ 错误: 配置目录不存在: $CONFIGS_DIR"
    exit 1
fi

# 检查各节点配置
for node_id in {1..4}; do
    NODE_CONFIG_DIR="$CONFIGS_DIR/node-$node_id"
    if [ ! -d "$NODE_CONFIG_DIR" ]; then
        echo "❌ 错误: 节点$node_id配置目录不存在: $NODE_CONFIG_DIR"
        exit 1
    fi
    
    if [ ! -f "$NODE_CONFIG_DIR/config.toml" ]; then
        echo "❌ 错误: 节点$node_id配置文件不存在: $NODE_CONFIG_DIR/config.toml"
        exit 1
    fi
    echo "✅ 节点$node_id配置检查通过"
done

# 清理并创建构建目录
echo "🧹 清理构建目录..."
rm -rf "$BUILD_DIR"
mkdir -p "$BUILD_DIR"

# 为每个节点构建镜像
for node_id in {1..4}; do
    NODE_BUILD_DIR="$BUILD_DIR/node-$node_id"
    NODE_CONFIG_DIR="$CONFIGS_DIR/node-$node_id"
    
    echo "🔨 构建节点$node_id镜像..."
    
    # 创建节点构建目录
    mkdir -p "$NODE_BUILD_DIR/node-configs"
    
    # 复制通用文件
    cp "$SCRIPT_DIR/config_processor_compat.py" "$NODE_BUILD_DIR/"
    cp "$SCRIPT_DIR/deploy_l1_contracts.py" "$NODE_BUILD_DIR/"
    cp "$SCRIPT_DIR/entrypoint.sh" "$NODE_BUILD_DIR/"
    cp "$SCRIPT_DIR/conflux" "$NODE_BUILD_DIR/"
    cp "$SCRIPT_DIR/Dockerfile.template" "$NODE_BUILD_DIR/Dockerfile"
    
    # 复制节点特定配置
    cp "$NODE_CONFIG_DIR"/*.toml "$NODE_BUILD_DIR/node-configs/" 2>/dev/null || true
    
    # 如果有其他节点特定文件，也复制过去
    if [ -d "$NODE_CONFIG_DIR/keys" ]; then
        cp -r "$NODE_CONFIG_DIR/keys" "$NODE_BUILD_DIR/node-configs/"
    fi
    
    # 给脚本执行权限
    chmod +x "$NODE_BUILD_DIR/config_processor_compat.py"
    chmod +x "$NODE_BUILD_DIR/deploy_l1_contracts.py"
    chmod +x "$NODE_BUILD_DIR/entrypoint.sh"
    chmod +x "$NODE_BUILD_DIR/conflux"
    
    # 构建Docker镜像
    echo "📦 构建Docker镜像: ${IMAGE_NAME}:node-${node_id}"
    cd "$NODE_BUILD_DIR"
    
    docker build \
        -t "${IMAGE_NAME}:node-${node_id}" \
        -t "${IMAGE_NAME}:node-${node_id}-${IMAGE_TAG}" \
        .
    
    if [ $? -eq 0 ]; then
        echo "✅ 节点$node_id镜像构建成功: ${IMAGE_NAME}:node-${node_id}"
    else
        echo "❌ 节点$node_id镜像构建失败"
        exit 1
    fi
    
    cd "$SCRIPT_DIR"
done

# 显示构建结果
echo ""
echo "🎉 所有节点镜像构建完成！"
echo ""
echo "📦 构建的镜像:"
for node_id in {1..4}; do
    echo "   ${IMAGE_NAME}:node-${node_id}"
done
echo ""

# 显示镜像信息
echo "📊 镜像信息:"
docker images "${IMAGE_NAME}" --format "table {{.Repository}}\t{{.Tag}}\t{{.Size}}\t{{.CreatedAt}}"

echo ""
echo "🚀 使用方法:"
echo "   docker run -d \\"
echo "     --name testchain_node1 \\"
echo "     -p 8545:8545 -p 30005:30005 \\"
echo "     -e NODE_ID=1 \\"
echo "     -e NODE1_IP=192.168.1.10 \\"
echo "     -e NODE2_IP=192.168.1.11 \\"
echo "     -e NODE3_IP=192.168.1.12 \\"
echo "     -e NODE4_IP=192.168.1.13 \\"
echo "     -e CHAIN_NAME=testchain \\"
echo "     ${IMAGE_NAME}:node-1"

echo ""
echo "✨ 镜像构建完成！"
