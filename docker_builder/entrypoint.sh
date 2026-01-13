#!/bin/bash
# 联盟链节点容器启动脚本
set -e

echo "🚀 启动联盟链节点容器..."
echo "📍 节点ID: ${NODE_ID:-未设置}"
echo "📍 链名称: ${CHAIN_NAME:-未设置}"

is_truthy() {
    case "$(echo "${1:-}" | tr '[:upper:]' '[:lower:]')" in
        1|true|yes|on) return 0 ;;
        *) return 1 ;;
    esac
}

# 验证必要的环境变量
if [ -z "$NODE_ID" ]; then
    echo "❌ 错误: NODE_ID环境变量未设置"
    exit 1
fi

if [ -z "$NODE1_IP" ] || [ -z "$NODE2_IP" ] || [ -z "$NODE3_IP" ] || [ -z "$NODE4_IP" ]; then
    echo "❌ 错误: 节点IP环境变量未完整设置"
    echo "   需要: NODE1_IP, NODE2_IP, NODE3_IP, NODE4_IP"
    exit 1
fi

echo "🔧 处理配置文件..."
echo "📍 节点IP映射:"
echo "   Node-1: $NODE1_IP:30005"
echo "   Node-2: $NODE2_IP:30006"
echo "   Node-3: $NODE3_IP:30008"
echo "   Node-4: $NODE4_IP:30007"

NODE_1_SSH_USER="${NODE_1_SSH_USER:-ubuntu}"
NODE_1_SSH_KEY_PATH="${NODE_1_SSH_KEY_PATH:-/root/4node-test.pem}"
NODE_1_SSH_HOST="${NODE_1_SSH_HOST:-$NODE1_IP}"
L1_FETCH_MAX_ATTEMPTS="${L1_FETCH_MAX_ATTEMPTS:-60}"
L1_FETCH_INTERVAL="${L1_FETCH_INTERVAL:-5}"

fetch_l1_from_node1() {
    local host="$1"
    local user="$2"
    local key_path="$3"
    local max_attempts="$4"
    local interval="$5"
    local container="${CHAIN_NAME}_node1"
    local ssh_opts=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -o ConnectTimeout=10 -i "$key_path")

    if [ -z "$host" ]; then
        echo "❌ 未配置 NODE_1_SSH_HOST，无法连接 node-1"
        exit 1
    fi
    if [ ! -f "$key_path" ]; then
        echo "❌ SSH私钥不存在: $key_path"
        exit 1
    fi

    for ((i=1; i<=max_attempts; i++)); do
        addr_output=$(ssh "${ssh_opts[@]}" "$user@$host" \
            "docker exec $container sh -c \"grep '^l1_' /opt/blockchain/customized_config.toml | sed 's/[[:space:]]//g' | sed 's/\\\"//g'\"" \
            2>/dev/null || true)

        if [ -n "$addr_output" ]; then
            while IFS='=' read -r k v; do
                case "$k" in
                    l1_state_sender_addr) L1_STATE_SENDER_ADDR="$v" ;;
                    l1_unified_bridge_addr) L1_UNIFIED_BRIDGE_ADDR="$v" ;;
                    l1_simple_calculator_addr) L1_SIMPLE_CALCULATOR_ADDR="$v" ;;
                    l1_chain_id) L1_CHAIN_ID="$v" ;;
                    l1_start_epoch) L1_START_EPOCH="$v" ;;
                    l1_admin_private_key) L1_ADMIN_PRIVATE_KEY="$v" ;;
                    l1_admin_address) L1_ADMIN_ADDRESS="$v" ;;
                esac
            done <<< "$addr_output"

            if [ -n "$L1_STATE_SENDER_ADDR" ] && [ -n "$L1_UNIFIED_BRIDGE_ADDR" ] && [ -n "$L1_SIMPLE_CALCULATOR_ADDR" ]; then
                export L1_STATE_SENDER_ADDR L1_UNIFIED_BRIDGE_ADDR L1_SIMPLE_CALCULATOR_ADDR
                export L1_CHAIN_ID L1_START_EPOCH L1_ADMIN_PRIVATE_KEY L1_ADMIN_ADDRESS
                echo "✅ 已获取 node-1 L1 部署结果"
                return 0
            fi
        fi

        echo "⏳ 等待 node-1 L1 部署结果 (${i}/${max_attempts})..."
        sleep "$interval"
    done

    echo "❌ 获取 node-1 L1 部署结果超时"
    exit 1
}

# node-2/3/4 从 node-1 读取 L1 合约部署结果
if is_truthy "$FETCH_L1_FROM_NODE1"; then
    echo "🔍 通过 SSH 从 node-1 拉取 L1 合约部署结果..."
    fetch_l1_from_node1 "$NODE_1_SSH_HOST" "$NODE_1_SSH_USER" "$NODE_1_SSH_KEY_PATH" \
        "$L1_FETCH_MAX_ATTEMPTS" "$L1_FETCH_INTERVAL"
fi

# 调用Python脚本处理配置
python3 ./config_processor_compat.py

if [ $? -ne 0 ]; then
    echo "❌ 配置处理失败"
    exit 1
fi

echo "✅ 配置处理完成"

# 显示最终配置摘要
echo "📄 配置文件摘要:"
if [ -f "config.toml" ]; then
    echo "   - config.toml: $(wc -l < config.toml) 行"
fi
if [ -f "customized_config.toml" ]; then
    echo "   - customized_config.toml: $(wc -l < customized_config.toml) 行"
fi

echo "🚀 启动区块链节点..."

# 启动conflux节点
if [ -f "customized_config.toml" ]; then
    echo "📄 使用自定义配置启动: customized_config.toml"
    exec ./conflux -c customized_config.toml
else
    echo "❌ 缺少customized_config.toml配置文件"
fi
