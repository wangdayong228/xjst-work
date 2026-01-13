#!/bin/bash
# 服务器内部节点部署脚本 - 配合运维统一部署流程
# 环境变量输入:
#   CHAIN_NODE_IPS: IP数组字符串，如 "[192.168.4.45,192.168.4.46,192.168.4.47,192.168.4.48]"
#   NODE_ID: 当前节点编号，如 "node-1", "node-2", "node-3", "node-4"
#   CHAIN_NAME: 链名称（可选，默认为testchain）
#   IMAGE_NAME: 镜像名称（可选，默认为consortium-blockchain）
#   P2P_PORT: P2P端口（可选，默认为30005）
#   BASE_RPC_PORT: 基础RPC端口（可选，默认为30010）

set -e

# 全局错误标志
HAS_ANY_ERROR=false
ERROR_DETAILS=()

# 记录错误但继续执行，最后统一处理
record_error() {
    local error_msg="$1"
    HAS_ANY_ERROR=true
    ERROR_DETAILS+=("$error_msg")
    echo "❌ $error_msg"
}

# 检查是否有错误并退出
check_and_exit_on_error() {
    local phase="$1"
    if [ "$HAS_ANY_ERROR" = true ]; then
        echo ""
        echo "❌ $phase 阶段发现错误，部署终止:"
        for error in "${ERROR_DETAILS[@]}"; do
            echo "   - $error"
        done
        exit 1
    fi
}

# 显示帮助信息
show_help() {
    echo "🚀 联盟链节点服务器内部部署脚本"
    echo ""
    echo "环境变量:"
    echo "  CHAIN_NODE_IPS   - 必需，IP数组字符串，如 \"[192.168.4.45,192.168.4.46,192.168.4.47,192.168.4.48]\""
    echo "  NODE_ID          - 必需，当前节点编号，如 \"node-1\", \"node-2\", \"node-3\", \"node-4\""
    echo "  CHAIN_NAME       - 可选，链名称 (默认: testchain)"
    echo "  IMAGE_NAME       - 可选，镜像名称 (默认: consortium-blockchain)"
    echo "  P2P_PORT         - 可选，P2P端口 (默认: 30005)"
    echo "  BASE_RPC_PORT    - 可选，基础RPC端口 (默认: 30010)"
    echo "  AUTO_DEPLOY_L1_CONTRACTS / DEPLOY_L1_CONTRACTS - 可选，true 时容器内自动部署 L1 合约"
    echo "  L1_CHAIN_ID, L1_GAS_PRICE, L1_ADMIN_PRIVATE_KEY, L1_ADMIN_ADDRESS - 可选，透传 L1 部署参数"
    echo "  FETCH_L1_FROM_NODE1   - 可选，true 时从 node-1 获取 L1 合约结果"
    echo "  NODE_1_SSH_USER       - 可选，node-1 SSH 用户 (默认: ubuntu)"
    echo "  NODE_1_SSH_KEY_PATH   - 可选，node-1 SSH 私钥路径(宿主机路径，将映射到容器 /root/4node-test.pem)"
    echo "  NODE_1_SSH_HOST       - 可选，node-1 SSH 主机地址 (默认: NODE1_IP)"
    echo "  L1_FETCH_MAX_ATTEMPTS - 可选，拉取重试次数"
    echo "  L1_FETCH_INTERVAL     - 可选，拉取重试间隔(秒)"
    echo ""
    echo "示例用法:"
    echo "  export CHAIN_NODE_IPS=\"[192.168.4.45,192.168.4.46,192.168.4.47,192.168.4.48]\""
    echo "  export NODE_ID=\"node-1\""
    echo "  export CHAIN_NAME=\"prodchain\""
    echo "  ./deploy_node.sh"
    echo ""
    echo "端口配置:"
    echo "  P2P端口: \$P2P_PORT (默认30005)"
    echo "  RPC端口组 (基于\$BASE_RPC_PORT):"
    echo "    - HTTP JSON-RPC: \$BASE_RPC_PORT (默认30010)"
    echo "    - Local HTTP JSON-RPC: \$BASE_RPC_PORT+1 (默认30011)"
    echo "    - gRPC TCP: \$BASE_RPC_PORT+2 (默认30012)"
    echo "    - TCP JSON-RPC: \$BASE_RPC_PORT+3 (默认30013)"
}

# 检查帮助参数
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# 检查必需的环境变量
if [ -z "$CHAIN_NODE_IPS" ]; then
    echo "❌ 错误: 环境变量 CHAIN_NODE_IPS 未设置"
    echo ""
    show_help
    exit 1
fi

if [ -z "$NODE_ID" ]; then
    echo "❌ 错误: 环境变量 NODE_ID 未设置"
    echo ""
    show_help
    exit 1
fi

# 设置默认值
CHAIN_NAME="${CHAIN_NAME:-testchain}"
IMAGE_NAME="${IMAGE_NAME:-consortium-blockchain}"
P2P_PORT="${P2P_PORT:-30005}"
BASE_RPC_PORT="${BASE_RPC_PORT:-30010}"
L1_ESPACE_RPC_URL="${L1_ESPACE_RPC_URL:-}"
L1_CORESPACE_RPC_URL="${L1_CORESPACE_RPC_URL:-}"
AUTO_DEPLOY_L1_CONTRACTS="${AUTO_DEPLOY_L1_CONTRACTS:-${DEPLOY_L1_CONTRACTS:-}}"
L1_CHAIN_ID="${L1_CHAIN_ID:-}"
L1_GAS_PRICE="${L1_GAS_PRICE:-}"
L1_ADMIN_PRIVATE_KEY="${L1_ADMIN_PRIVATE_KEY:-}"
L1_ADMIN_ADDRESS="${L1_ADMIN_ADDRESS:-}"
L1_STATE_SENDER_ADDR="${L1_STATE_SENDER_ADDR:-}"
L1_UNIFIED_BRIDGE_ADDR="${L1_UNIFIED_BRIDGE_ADDR:-}"
L1_SIMPLE_CALCULATOR_ADDR="${L1_SIMPLE_CALCULATOR_ADDR:-}"
L1_START_EPOCH="${L1_START_EPOCH:-}"
FETCH_L1_FROM_NODE1="${FETCH_L1_FROM_NODE1:-}"
NODE_1_SSH_USER="${NODE_1_SSH_USER:-}"
NODE_1_SSH_KEY_PATH="${NODE_1_SSH_KEY_PATH:-}"
NODE_1_SSH_HOST="${NODE_1_SSH_HOST:-}"
L1_FETCH_MAX_ATTEMPTS="${L1_FETCH_MAX_ATTEMPTS:-}"
L1_FETCH_INTERVAL="${L1_FETCH_INTERVAL:-}"
NODE_1_SSH_KEY_HOST_PATH="${NODE_1_SSH_KEY_PATH:-/home/ubuntu/.ssh/4node-test.pem}"
NODE_1_SSH_KEY_PATH="/root/4node-test.pem"

# 计算RPC端口
JSONRPC_HTTP_PORT=$BASE_RPC_PORT           # 30010
JSONRPC_LOCAL_HTTP_PORT=$((BASE_RPC_PORT + 1))  # 30011
GRPC_TCP_PORT=$((BASE_RPC_PORT + 2))       # 30012
JSONRPC_TCP_PORT=$((BASE_RPC_PORT + 3))    # 30013

# 验证NODE_ID格式
if [[ ! $NODE_ID =~ ^node-[1-4]$ ]]; then
    echo "❌ 错误: NODE_ID 格式无效: $NODE_ID"
    echo "正确格式: node-1, node-2, node-3, node-4"
    exit 1
fi

# 提取节点编号 (node-1 -> 1)
NODE_NUM=$(echo $NODE_ID | sed 's/node-//')

echo "🚀 开始部署联盟链节点: $NODE_ID"
echo "📍 链名称: $CHAIN_NAME"
echo "📍 节点编号: $NODE_NUM"
echo "📍 原始IP数组: $CHAIN_NODE_IPS"
echo "📍 镜像名称: $IMAGE_NAME:$NODE_ID"
echo "📍 P2P端口: $P2P_PORT"
echo "📍 RPC端口: $JSONRPC_HTTP_PORT(HTTP), $JSONRPC_LOCAL_HTTP_PORT(Local), $GRPC_TCP_PORT(gRPC), $JSONRPC_TCP_PORT(TCP)"
if [ -n "$L1_ESPACE_RPC_URL" ]; then
    echo "📍 L1 eSpace RPC: $L1_ESPACE_RPC_URL"
fi
if [ -n "$L1_CORESPACE_RPC_URL" ]; then
    echo "📍 L1 CoreSpace RPC: $L1_CORESPACE_RPC_URL"
fi
if [ -n "$AUTO_DEPLOY_L1_CONTRACTS" ]; then
    echo "📍 自动部署 L1 合约: $AUTO_DEPLOY_L1_CONTRACTS"
fi
if [ -n "$L1_CHAIN_ID" ]; then
    echo "📍 L1 Chain ID: $L1_CHAIN_ID"
fi
if [ -n "$L1_GAS_PRICE" ]; then
    echo "📍 L1 Gas Price: $L1_GAS_PRICE"
fi
if [ -n "$L1_ADMIN_ADDRESS" ]; then
    echo "📍 L1 Admin Address: $L1_ADMIN_ADDRESS"
fi
if [ -n "$L1_ADMIN_PRIVATE_KEY" ]; then
    echo "📍 L1 Admin Private Key: 已提供"
fi
if [ -n "$L1_STATE_SENDER_ADDR" ] || [ -n "$L1_UNIFIED_BRIDGE_ADDR" ] || [ -n "$L1_SIMPLE_CALCULATOR_ADDR" ]; then
    echo "📍 L1 地址覆盖: state_sender=${L1_STATE_SENDER_ADDR:-空}, unified_bridge=${L1_UNIFIED_BRIDGE_ADDR:-空}, simple_calculator=${L1_SIMPLE_CALCULATOR_ADDR:-空}"
fi
if [ -n "$L1_START_EPOCH" ]; then
    echo "📍 L1 Start Epoch: $L1_START_EPOCH"
fi
if [ -n "$FETCH_L1_FROM_NODE1" ]; then
    echo "📍 从 node-1 拉取 L1 部署结果: $FETCH_L1_FROM_NODE1"
fi
echo ""

# 解析IP数组字符串
echo "🔍 解析IP数组..."

# 移除方括号和空格，分割为数组
IPS_STRING=$(echo "$CHAIN_NODE_IPS" | sed 's/\[//g' | sed 's/\]//g' | sed 's/ //g')
IFS=',' read -ra IP_ARRAY <<< "$IPS_STRING"

# 验证IP数量
if [ ${#IP_ARRAY[@]} -ne 4 ]; then
    record_error "IP数组必须包含4个IP地址，当前: ${#IP_ARRAY[@]}"
    check_and_exit_on_error "IP数组解析"
fi

# 验证IP格式并分配
NODE1_IP="${IP_ARRAY[0]}"
NODE2_IP="${IP_ARRAY[1]}"
NODE3_IP="${IP_ARRAY[2]}"
NODE4_IP="${IP_ARRAY[3]}"

echo "📍 解析后的IP分配:"
for i in {1..4}; do
    ip_var="NODE${i}_IP"
    ip_val="${!ip_var}"
    if [[ ! $ip_val =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; then
        record_error "节点$i IP格式无效: $ip_val"
    else
        echo "   节点$i: $ip_val"
    fi
done

check_and_exit_on_error "IP格式验证"

# 检查IP唯一性
if [ $(printf '%s\n' "${IP_ARRAY[@]}" | sort -u | wc -l) -ne 4 ]; then
    record_error "节点IP必须唯一"
    check_and_exit_on_error "IP唯一性检查"
fi

echo "✅ IP数组解析和验证完成"
echo ""

# 检查Docker环境
echo "🔍 检查Docker环境..."
if ! docker --version >/dev/null 2>&1; then
    record_error "Docker未安装或无法运行"
    check_and_exit_on_error "Docker环境检查"
fi
echo "✅ Docker环境检查通过"

# 检查镜像是否存在
echo "🔍 检查Docker镜像..."
IMAGE_TAG="${IMAGE_NAME}:${NODE_ID}"
if ! docker image inspect "$IMAGE_TAG" >/dev/null 2>&1; then
    record_error "镜像不存在: $IMAGE_TAG"
    check_and_exit_on_error "镜像检查"
fi
echo "✅ 镜像检查通过: $IMAGE_TAG"

# 停止现有容器
echo "🚫 停止现有容器..."
CONTAINER_NAME="${CHAIN_NAME}_node${NODE_NUM}"

if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "   发现现有容器: $CONTAINER_NAME"
    docker stop "$CONTAINER_NAME" 2>/dev/null || true
    docker rm "$CONTAINER_NAME" 2>/dev/null || true
    echo "   ✅ 现有容器已清理"
else
    echo "   无现有容器需要清理"
fi

# 启动容器
echo "🚀 启动节点容器..."

docker_args=(
    -d
    --name "$CONTAINER_NAME"
    --restart unless-stopped
    -p "$JSONRPC_HTTP_PORT:30010"
    -p "$JSONRPC_LOCAL_HTTP_PORT:30011"
    -p "$GRPC_TCP_PORT:30012"
    -p "$JSONRPC_TCP_PORT:30013"
    -p "$P2P_PORT:$P2P_PORT"
    -e "NODE_ID=$NODE_NUM"
    -e "NODE1_IP=$NODE1_IP"
    -e "NODE2_IP=$NODE2_IP"
    -e "NODE3_IP=$NODE3_IP"
    -e "NODE4_IP=$NODE4_IP"
    -e "CHAIN_NAME=$CHAIN_NAME"
    -e "P2P_PORT=$P2P_PORT"
)

if [ -n "$L1_ESPACE_RPC_URL" ]; then
    docker_args+=(-e "L1_ESPACE_RPC_URL=$L1_ESPACE_RPC_URL")
fi

if [ -n "$L1_CORESPACE_RPC_URL" ]; then
    docker_args+=(-e "L1_CORESPACE_RPC_URL=$L1_CORESPACE_RPC_URL")
fi
if [ -n "$AUTO_DEPLOY_L1_CONTRACTS" ]; then
    docker_args+=(-e "AUTO_DEPLOY_L1_CONTRACTS=$AUTO_DEPLOY_L1_CONTRACTS")
fi
if [ -n "$L1_CHAIN_ID" ]; then
    docker_args+=(-e "L1_CHAIN_ID=$L1_CHAIN_ID")
fi
if [ -n "$L1_GAS_PRICE" ]; then
    docker_args+=(-e "L1_GAS_PRICE=$L1_GAS_PRICE")
fi
if [ -n "$L1_ADMIN_PRIVATE_KEY" ]; then
    docker_args+=(-e "L1_ADMIN_PRIVATE_KEY=$L1_ADMIN_PRIVATE_KEY")
fi
if [ -n "$L1_ADMIN_ADDRESS" ]; then
    docker_args+=(-e "L1_ADMIN_ADDRESS=$L1_ADMIN_ADDRESS")
fi
if [ -n "$L1_STATE_SENDER_ADDR" ]; then
    docker_args+=(-e "L1_STATE_SENDER_ADDR=$L1_STATE_SENDER_ADDR")
fi
if [ -n "$L1_UNIFIED_BRIDGE_ADDR" ]; then
    docker_args+=(-e "L1_UNIFIED_BRIDGE_ADDR=$L1_UNIFIED_BRIDGE_ADDR")
fi
if [ -n "$L1_SIMPLE_CALCULATOR_ADDR" ]; then
    docker_args+=(-e "L1_SIMPLE_CALCULATOR_ADDR=$L1_SIMPLE_CALCULATOR_ADDR")
fi
if [ -n "$L1_START_EPOCH" ]; then
    docker_args+=(-e "L1_START_EPOCH=$L1_START_EPOCH")
fi
if [ -n "$FETCH_L1_FROM_NODE1" ]; then
    docker_args+=(-e "FETCH_L1_FROM_NODE1=$FETCH_L1_FROM_NODE1")
fi
if [ -n "$NODE_1_SSH_USER" ]; then
    docker_args+=(-e "NODE_1_SSH_USER=$NODE_1_SSH_USER")
fi
if [ -n "$NODE_1_SSH_KEY_PATH" ]; then
    docker_args+=(-e "NODE_1_SSH_KEY_PATH=$NODE_1_SSH_KEY_PATH")
fi
if [ -n "$NODE_1_SSH_HOST" ]; then
    docker_args+=(-e "NODE_1_SSH_HOST=$NODE_1_SSH_HOST")
fi
if [ -n "$L1_FETCH_MAX_ATTEMPTS" ]; then
    docker_args+=(-e "L1_FETCH_MAX_ATTEMPTS=$L1_FETCH_MAX_ATTEMPTS")
fi
if [ -n "$L1_FETCH_INTERVAL" ]; then
    docker_args+=(-e "L1_FETCH_INTERVAL=$L1_FETCH_INTERVAL")
fi

if [ -n "$FETCH_L1_FROM_NODE1" ]; then
    if [ ! -f "$NODE_1_SSH_KEY_HOST_PATH" ]; then
        record_error "node-1 SSH私钥不存在: $NODE_1_SSH_KEY_HOST_PATH"
    else
        docker_args+=(-v "$NODE_1_SSH_KEY_HOST_PATH:/root/4node-test.pem:ro")
    fi
    check_and_exit_on_error "SSH密钥检查"
fi

docker_args+=("$IMAGE_TAG")

if ! docker run "${docker_args[@]}"; then
    record_error "容器启动失败"
    check_and_exit_on_error "容器启动"
fi

echo "✅ 容器启动成功: $CONTAINER_NAME"

# 等待容器启动
echo "⏳ 等待容器完全启动..."
sleep 10

# 检查容器状态
echo "🔍 检查容器状态..."
CONTAINER_STATUS=$(docker inspect -f "{{.State.Status}}" "$CONTAINER_NAME" 2>/dev/null || echo "not_found")

if [ "$CONTAINER_STATUS" = "running" ]; then
    echo "✅ 节点$NODE_ID 运行正常"
else
    record_error "容器状态异常: $CONTAINER_STATUS"

    # 显示容器日志
    echo "   容器日志:"
    docker logs --tail 20 "$CONTAINER_NAME" 2>&1 | sed 's/^/      /'

    check_and_exit_on_error "容器状态检查"
fi

echo ""
echo "🎉 节点 '$NODE_ID' 部署成功！"
echo ""
echo "📡 RPC服务地址:"
echo "   HTTP JSON-RPC: http://$(hostname -I | awk '{print $1}'):$JSONRPC_HTTP_PORT"
echo "   Local HTTP JSON-RPC: http://$(hostname -I | awk '{print $1}'):$JSONRPC_LOCAL_HTTP_PORT"
echo "   gRPC TCP: $(hostname -I | awk '{print $1}'):$GRPC_TCP_PORT"
echo "   TCP JSON-RPC: $(hostname -I | awk '{print $1}'):$JSONRPC_TCP_PORT"
echo ""
echo "🔧 管理命令:"
echo "   查看日志: docker logs $CONTAINER_NAME"
echo "   停止节点: docker stop $CONTAINER_NAME"
echo "   启动节点: docker start $CONTAINER_NAME"
echo "   删除节点: docker stop $CONTAINER_NAME && docker rm $CONTAINER_NAME"
