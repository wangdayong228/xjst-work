#!/bin/bash
# 联盟链客户端卸载脚本 - 停止并删除四个节点的容器，可选删除镜像
#
# 用法示例：
#   export IPS="10.0.0.1 10.0.0.2 10.0.0.3 10.0.0.4"
#   export SSH_KEY_PATH="$HOME/.ssh/4node-test.pem"
#   export CHAIN_NAME="testchain"
#   ./client_undeploy.sh
#
# 可选：REMOVE_IMAGES=true 同时删除 consortium-blockchain:node-X 和 node-X-latest 镜像。

set -euo pipefail

# 默认配置
DEFAULT_CHAIN_NAME="testchain"
DEFAULT_SSH_USER="ubuntu"

# 读取配置
CHAIN_NAME="${CHAIN_NAME:-$DEFAULT_CHAIN_NAME}"
SSH_USER="${SSH_USER:-$DEFAULT_SSH_USER}"
REMOVE_IMAGES="${REMOVE_IMAGES:-false}"
IPS="${IPS:-}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
if [ -z "$SSH_KEY_PATH" ] && [ -n "${KEY_NAME:-}" ]; then
    SSH_KEY_PATH="$HOME/.ssh/${KEY_NAME}.pem"
fi

show_help() {
    echo "🧹 联盟链客户端卸载脚本"
    echo ""
    echo "必需环境变量:"
    echo "  IPS           - 四个节点IP，空格分隔，如 \"192.168.4.45 192.168.4.46 192.168.4.47 192.168.4.48\""
    echo ""
    echo "可选环境变量:"
    echo "  CHAIN_NAME    - 链名称 (默认: $DEFAULT_CHAIN_NAME)"
    echo "  SSH_USER      - SSH 用户名 (默认: $DEFAULT_SSH_USER)"
    echo "  SSH_KEY_PATH  - SSH 私钥路径 (或设置 KEY_NAME 自动推导 ~/.ssh/KEY_NAME.pem)"
    echo "  REMOVE_IMAGES - 是否删除镜像 (默认: false, 设置为 true 删除 consortium-blockchain:node-X 与 node-X-latest)"
    echo ""
    echo "示例:"
    echo "  export IPS=\"10.0.0.1 10.0.0.2 10.0.0.3 10.0.0.4\""
    echo "  export SSH_KEY_PATH=\"\$HOME/.ssh/4node-test.pem\""
    echo "  export CHAIN_NAME=\"testchain\""
    echo "  ./client_undeploy.sh"
}

if [ "${1:-}" = "-h" ] || [ "${1:-}" = "--help" ]; then
    show_help
    exit 0
fi

if [ -z "$IPS" ]; then
    echo "❌ 错误: 必需环境变量 IPS 未设置"
    echo ""
    show_help
    exit 1
fi

if [ -z "$SSH_KEY_PATH" ]; then
    echo "❌ 错误: 未提供 SSH_KEY_PATH 或 KEY_NAME"
    exit 1
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "❌ 错误: SSH 私钥不存在: $SSH_KEY_PATH"
    exit 1
fi

IPS_ARRAY=($IPS)
if [ ${#IPS_ARRAY[@]} -ne 4 ]; then
    echo "❌ 错误: 必须提供 4 个节点 IP，当前: ${#IPS_ARRAY[@]}"
    exit 1
fi

SSH_OPTS=(-o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -o ConnectTimeout=30 -i "$SSH_KEY_PATH")

echo "🧹 开始卸载联盟链: $CHAIN_NAME"
echo "📍 节点IP列表: $IPS"
echo "📍 SSH用户: $SSH_USER"
echo "📍 SSH认证: 密钥 ($SSH_KEY_PATH)"
echo "📍 删除镜像: $REMOVE_IMAGES"
echo ""

undeploy_node() {
    local ip="$1"
    local node_idx="$2"
    local name_new="${CHAIN_NAME}_node${node_idx}"
    local name_old="${CHAIN_NAME}_node-${node_idx}"

    echo "🔧 处理节点${node_idx} ($ip)..."
    ssh "${SSH_OPTS[@]}" "$SSH_USER@$ip" bash -s <<EOF
set -e
name_new="$name_new"
name_old="$name_old"
remove_images="$REMOVE_IMAGES"
found=0
for cname in "\$name_new" "\$name_old"; do
    if docker ps -a --format '{{.Names}}' | grep -qx "\$cname"; then
        echo "   停止容器: \$cname"
        docker stop "\$cname" 2>/dev/null || true
        echo "   删除容器: \$cname"
        docker rm "\$cname" 2>/dev/null || true
        found=1
        break
    fi
done
if [ \$found -eq 0 ]; then
    echo "   未发现容器: \$name_new / \$name_old"
fi
if [ "\$remove_images" = "true" ]; then
    for img in consortium-blockchain:node-${node_idx} consortium-blockchain:node-${node_idx}-latest; do
        if docker images --format '{{.Repository}}:{{.Tag}}' | grep -qx "\$img"; then
            echo "   删除镜像: \$img"
            docker rmi "\$img" 2>/dev/null || true
        fi
    done
fi
EOF
}

i=1
for ip in "${IPS_ARRAY[@]}"; do
    undeploy_node "$ip" "$i" &
    i=$((i+1))
done

wait

echo ""
echo "✅ 联盟链 '$CHAIN_NAME' 卸载完成（容器已停止/删除，REMOVE_IMAGES=$REMOVE_IMAGES）"
