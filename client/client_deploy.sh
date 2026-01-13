#!/bin/bash
# 联盟链客户端部署脚本 - 模仿op-stack部署模式
# 通过SSH连接到4个服务器并执行deploy_node.sh完成链部署
#
# 使用方法:
#   export IPS="192.168.4.45 192.168.4.46 192.168.4.47 192.168.4.48"
#   export CHAIN_NAME="testchain"
#   ./client_deploy.sh

set -e

# 默认配置
DEFAULT_CHAIN_NAME="testchain"
DEFAULT_IMAGE_NAME="consortium-blockchain"
DEFAULT_P2P_PORT="30005"
DEFAULT_BASE_RPC_PORT="30010"
DEFAULT_RUN_DURATION="120"   # 默认运行时长(分钟)，参考op-stack脚本
DEFAULT_RPC_CHECK_MAX_ATTEMPTS=5
DEFAULT_RPC_CHECK_INTERVAL=3
DEFAULT_AUTO_DEPLOY_NODE_ID=1
RPC_CHECK_INITIAL_DELAY=30  # 固定的RPC健康检查延时（秒）

# 从环境变量获取配置，如果未设置则使用默认值
CHAIN_NAME="${CHAIN_NAME:-$DEFAULT_CHAIN_NAME}"
IMAGE_NAME="${IMAGE_NAME:-$DEFAULT_IMAGE_NAME}"
P2P_PORT="${P2P_PORT:-$DEFAULT_P2P_PORT}"
BASE_RPC_PORT="${BASE_RPC_PORT:-$DEFAULT_BASE_RPC_PORT}"
RUN_DURATION="${RUN_DURATION:-$DEFAULT_RUN_DURATION}"
RPC_CHECK_MAX_ATTEMPTS="${RPC_CHECK_MAX_ATTEMPTS:-$DEFAULT_RPC_CHECK_MAX_ATTEMPTS}"
RPC_CHECK_INTERVAL="${RPC_CHECK_INTERVAL:-$DEFAULT_RPC_CHECK_INTERVAL}"
AUTO_DEPLOY_L1_CONTRACTS="${AUTO_DEPLOY_L1_CONTRACTS:-${DEPLOY_L1_CONTRACTS:-}}"
AUTO_DEPLOY_NODE_ID="${AUTO_DEPLOY_NODE_ID:-$DEFAULT_AUTO_DEPLOY_NODE_ID}"
SSH_USER="${SSH_USER:-ubuntu}"
SSH_KEY_PATH="${SSH_KEY_PATH:-}"
FETCH_L1_FROM_NODE1="${FETCH_L1_FROM_NODE1:-}"
NODE_1_SSH_USER="${NODE_1_SSH_USER:-}"
NODE_1_SSH_KEY_PATH="${NODE_1_SSH_KEY_PATH:-}"
NODE_1_SSH_HOST="${NODE_1_SSH_HOST:-}"
L1_FETCH_MAX_ATTEMPTS="${L1_FETCH_MAX_ATTEMPTS:-}"
L1_FETCH_INTERVAL="${L1_FETCH_INTERVAL:-}"
if [ -z "$SSH_KEY_PATH" ] && [ -n "${KEY_NAME:-}" ]; then
    SSH_KEY_PATH="$HOME/.ssh/${KEY_NAME}.pem"
fi

# 显示帮助信息
show_help() {
    echo "🚀 联盟链客户端部署脚本 (SSH密钥认证版本)"
    echo ""
    echo "环境变量:"
    echo "  IPS              - 必需，4个节点IP，空格分隔，如：\"192.168.4.45 192.168.4.46 192.168.4.47 192.168.4.48\""
    echo "  SSH_KEY_PATH     - 必需，SSH私钥路径 (或通过 KEY_NAME 自动推导)"
    echo "  KEY_NAME         - 可选，若设置则默认使用 \$HOME/.ssh/{KEY_NAME}.pem"
    echo "  CHAIN_NAME       - 可选，链名称 (默认: $DEFAULT_CHAIN_NAME)"
    echo "  IMAGE_NAME       - 可选，镜像名称 (默认: $DEFAULT_IMAGE_NAME)"
    echo "  P2P_PORT         - 可选，P2P端口 (默认: $DEFAULT_P2P_PORT)"
    echo "  BASE_RPC_PORT    - 可选，基础RPC端口 (默认: $DEFAULT_BASE_RPC_PORT)"
    echo "  RUN_DURATION     - 可选，服务器运行时长分钟数 (默认: $DEFAULT_RUN_DURATION)"
    echo "  SSH_USER         - 可选，SSH登录用户 (默认: ubuntu)"
    echo "  REMOTE_CMD       - 可选，自定义远程执行命令"
    echo "  L1_ESPACE_RPC_URL    - 可选，透传至自定义配置的 L1 eSpace RPC 地址"
    echo "  L1_CORESPACE_RPC_URL - 可选，透传至自定义配置的 L1 CoreSpace RPC 地址"
    echo "  AUTO_DEPLOY_L1_CONTRACTS / DEPLOY_L1_CONTRACTS - 可选，true 时容器内自动部署 L1 合约并写回地址"
    echo "  L1_CHAIN_ID, L1_GAS_PRICE, L1_ADMIN_PRIVATE_KEY, L1_ADMIN_ADDRESS - 可选，透传合约部署参数"
    echo "  FETCH_L1_FROM_NODE1  - 可选，node-2/3/4 是否通过SSH从node-1获取L1信息"
    echo "  NODE_1_SSH_USER      - 可选，node-1 SSH用户 (默认: ubuntu)"
    echo "  NODE_1_SSH_KEY_PATH  - 可选，node-1 SSH私钥路径(宿主机路径，会映射到容器 /root/4node-test.pem)"
    echo "  NODE_1_SSH_HOST      - 可选，node-1 SSH主机地址 (默认: NODE1_IP)"
    echo "  L1_FETCH_MAX_ATTEMPTS - 可选，L1信息拉取最大重试次数"
    echo "  L1_FETCH_INTERVAL    - 可选，L1信息拉取重试间隔(秒)"
    echo ""
    echo "示例用法:"
    echo "  export IPS=\"192.168.4.45 192.168.4.46 192.168.4.47 192.168.4.48\""
    echo "  export SSH_KEY_PATH=\"\$HOME/.ssh/4node-test.pem\""
    echo "  export CHAIN_NAME=\"prodchain\""
    echo "  ./client_deploy.sh"
    echo ""
    echo "前置要求:"
    echo "  - 确保deploy_node.sh脚本在当前目录"
    echo "  - 确保SSH密钥认证可用"
    echo "  - 目标服务器需要预置Docker镜像: consortium-blockchain:node-X"
}

# 检查帮助参数
if [ "$1" = "-h" ] || [ "$1" = "--help" ]; then
    show_help
    exit 0
fi

# 检查必需的环境变量
if [ -z "$IPS" ]; then
    echo "❌ 错误: 环境变量 IPS 未设置"
    echo ""
    show_help
    exit 1
fi

if [ -z "$SSH_KEY_PATH" ]; then
    echo "❌ 错误: 未提供 SSH_KEY_PATH 或 KEY_NAME"
    echo ""
    show_help
    exit 1
fi

if [ ! -f "$SSH_KEY_PATH" ]; then
    echo "❌ 错误: SSH私钥不存在: $SSH_KEY_PATH"
    exit 1
fi

# 验证IP数量
IPS_ARRAY=($IPS)
if [ ${#IPS_ARRAY[@]} -ne 4 ]; then
    echo "❌ 错误: 必须提供4个IP地址，当前: ${#IPS_ARRAY[@]}"
    echo "提供的IP: $IPS"
    exit 1
fi

# 检查本地deploy_node.sh脚本是否存在
if [ ! -f "./deploy_node.sh" ]; then
    echo "❌ 错误: 本地deploy_node.sh脚本不存在"
    echo "请确保deploy_node.sh文件在当前目录"
    exit 1
fi

# 检查脚本执行权限
if [ ! -x "./deploy_node.sh" ]; then
    echo "⚠️  deploy_node.sh没有执行权限，正在添加执行权限..."
    chmod +x ./deploy_node.sh
fi
SSH_COMMON_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -o ConnectTimeout=180 -i "$SSH_KEY_PATH")
SCP_COMMON_OPTS=(-o BatchMode=yes -o StrictHostKeyChecking=accept-new -o IdentitiesOnly=yes -o ConnectTimeout=180 -i "$SSH_KEY_PATH")

CHAIN_NODE_IPS_STR="[$(echo "$IPS" | sed 's/ /,/g')]"

# 创建日志目录
LOG_DIR="./deployment_logs_$(date +%Y%m%d_%H%M%S)"
mkdir -p "$LOG_DIR"

echo "🚀 开始部署联盟链: $CHAIN_NAME"
echo "📍 节点IP列表: $IPS"
echo "📍 IP数组格式: $CHAIN_NODE_IPS_STR"
echo "📍 镜像名称: $IMAGE_NAME"
echo "📍 P2P端口: $P2P_PORT"
echo "📍 RPC端口组: $BASE_RPC_PORT-$((BASE_RPC_PORT + 3))"
echo "📍 SSH用户: $SSH_USER"
echo "📍 SSH认证: 密钥认证 ($SSH_KEY_PATH)"
if [ -n "$AUTO_DEPLOY_L1_CONTRACTS" ]; then
    echo "📍 L1 自动部署节点: node-$AUTO_DEPLOY_NODE_ID"
fi
echo "📍 服务器运行时长: ${RUN_DURATION}分钟"
echo "📍 日志目录: $LOG_DIR"
echo ""

TAG="$CHAIN_NAME"

echo "📦 上传 deploy_node.sh 脚本到所有服务器..."
LOCAL_DEPLOY_SCRIPT="./deploy_node.sh"
LOCAL_DEPLOY_HASH=$(sha256sum "$LOCAL_DEPLOY_SCRIPT" | cut -d' ' -f1)

upload_and_prep() {
    local ip="$1"
    echo "   检查 $ip..."

    remote_hash=$(ssh "${SSH_COMMON_OPTS[@]}" "$SSH_USER@$ip" "if [ -f ~/deploy_node.sh ]; then sha256sum ~/deploy_node.sh | cut -d' ' -f1; fi" 2>/dev/null || true)

    if [ -n "$remote_hash" ] && [ "$remote_hash" = "$LOCAL_DEPLOY_HASH" ]; then
        echo "      ✅ 远端脚本已存在且一致，跳过上传"
    else
        echo "      📤 上传脚本到 $ip..."
        if ! scp "${SCP_COMMON_OPTS[@]}" "$LOCAL_DEPLOY_SCRIPT" "$SSH_USER@$ip:~/"; then
            echo "❌ 无法上传脚本到 $ip"
            exit 1
        fi
    fi

    if ! ssh "${SSH_COMMON_OPTS[@]}" "$SSH_USER@$ip" "chmod +x ~/deploy_node.sh"; then
        echo "❌ 无法设置脚本执行权限在 $ip"
        exit 1
    fi
}

for ip in $IPS; do
    upload_and_prep "$ip"
done
echo "✅ 所有脚本上传完成"
echo ""

DEPLOY_PIDS=()
DEPLOY_IPS=()
DEPLOY_NODE_IDS=()
DEPLOY_LOG_FILES=()

launch_deploy() {
    local ip="$1"
    local node_idx="$2"
    local auto_flag="$3"
    local extra_env="$4"
    local fetch_flag="$5"

    local name="${TAG}-node-${node_idx}"
    local node_id="node-${node_idx}"

    echo "🔄 启动节点${node_idx}部署任务 (服务器: $ip, 节点: $node_id)"

    {
        if [ -z "${REMOTE_CMD:-}" ]; then
            cmd="set -e && \
                 export CHAIN_NODE_IPS='$CHAIN_NODE_IPS_STR' && \
                 export NODE_ID='$node_id' && \
                 export CHAIN_NAME='$CHAIN_NAME' && \
                 export IMAGE_NAME='$IMAGE_NAME' && \
                 export P2P_PORT='$P2P_PORT' && \
                 export BASE_RPC_PORT='$BASE_RPC_PORT' && \
                 export L1_ESPACE_RPC_URL='${L1_ESPACE_RPC_URL:-}' && \
                 export L1_CORESPACE_RPC_URL='${L1_CORESPACE_RPC_URL:-}' && \
                 export AUTO_DEPLOY_L1_CONTRACTS='$auto_flag' && \
                 export FETCH_L1_FROM_NODE1='$fetch_flag' && \
                 export NODE_1_SSH_USER='${NODE_1_SSH_USER:-}' && \
                 export NODE_1_SSH_KEY_PATH='${NODE_1_SSH_KEY_PATH:-}' && \
                 export NODE_1_SSH_HOST='${NODE_1_SSH_HOST:-}' && \
                 export L1_FETCH_MAX_ATTEMPTS='${L1_FETCH_MAX_ATTEMPTS:-}' && \
                 export L1_FETCH_INTERVAL='${L1_FETCH_INTERVAL:-}' && \
                 export DEPLOY_L1_CONTRACTS='' && \
                 export L1_CHAIN_ID='${L1_CHAIN_ID:-}' && \
                 export L1_GAS_PRICE='${L1_GAS_PRICE:-}' && \
                 export L1_ADMIN_PRIVATE_KEY='${L1_ADMIN_PRIVATE_KEY:-}' && \
                 export L1_ADMIN_ADDRESS='${L1_ADMIN_ADDRESS:-}' && \
                 $extra_env \
                 cd ~ && \
                 if [ ! -f './deploy_node.sh' ]; then echo 'ERROR: deploy_node.sh not found'; exit 1; fi && \
                ./deploy_node.sh && \
                 echo 'DEPLOY_SUCCESS: Node deployment completed successfully'"
        else
            cmd="set -e && $REMOTE_CMD"
        fi

        if [ "$RUN_DURATION" != "0" ]; then
            cmd="sudo -n shutdown -h +${RUN_DURATION} 2>/dev/null || echo 'Note: Auto-shutdown not set (no sudo or shutdown permission)' && $cmd"
        fi

        echo "[$ip] 执行命令: $cmd"
        echo ""

        ssh "${SSH_COMMON_OPTS[@]}" \
            "$SSH_USER@$ip" \
            "$cmd" \
            2>&1 | sed "s/^/[$ip][$node_id] /"
    } | tee -a "$LOG_DIR/${ip}-${name}.log" &

    DEPLOY_PIDS+=($!)
    DEPLOY_IPS+=("$ip")
    DEPLOY_NODE_IDS+=("$node_id")
    DEPLOY_LOG_FILES+=("$LOG_DIR/${ip}-${name}.log")
}

wait_for_deploys() {
    local pids=("${DEPLOY_PIDS[@]}")
    local ips=("${DEPLOY_IPS[@]}")
    local node_ids=("${DEPLOY_NODE_IDS[@]}")
    local logs=("${DEPLOY_LOG_FILES[@]}")

    DEPLOY_PIDS=()
    DEPLOY_IPS=()
    DEPLOY_NODE_IDS=()
    DEPLOY_LOG_FILES=()

    echo "⏳ 等待节点部署完成..."
    echo "📊 后台进程数量: ${#pids[@]}"
    echo ""

    failed=false
    failed_ips=()

    for ((idx=0; idx<${#pids[@]}; idx++)); do
        pid=${pids[$idx]}
        ip=${ips[$idx]}
        node_id=${node_ids[$idx]}
        log_file=${logs[$idx]}

        wait $pid
        exit_code=$?
        if [ $exit_code -ne 0 ]; then
            failed=true
            failed_ips+=("$ip($node_id)")
            echo "❌ [$ip][$node_id] 部署脚本退出码: $exit_code"
            if [ -f "$log_file" ]; then
                echo "   错误详情:"
                grep "ERROR:\|❌\|Failed\|failed" "$log_file" | tail -3 | sed 's/^/     /'
            fi
        else
            echo "✅ [$ip][$node_id] 部署脚本完成"
        fi
    done

    if [ "$failed" = true ]; then
        echo ""
        echo "❌ 部分节点部署失败，失败列表:"
        for failed_ip in "${failed_ips[@]}"; do
            echo "   - $failed_ip"
        done
        exit 1
    fi
}

rpc_health_check_all() {
    local failed=false
    local failed_ips=()
    local success_count=0
    local total=0
    echo "⏳ 开始RPC健康检查（全部节点）..."
    if [ "$RPC_CHECK_INITIAL_DELAY" -gt 0 ]; then
        echo "⏱  等待 ${RPC_CHECK_INITIAL_DELAY}s 后开始RPC健康检查..."
        sleep "$RPC_CHECK_INITIAL_DELAY"
    fi
    local idx=1
    for ip in $IPS; do
        total=$((total+1))
        rpc_url="http://$ip:$BASE_RPC_PORT"
        rpc_payload='{"jsonrpc":"2.0","method":"cfx_getPeers","params":[],"id":1}'
        echo "   节点 node-$idx: $rpc_url (最多重试 ${RPC_CHECK_MAX_ATTEMPTS} 次)"
        rpc_success=false
        rpc_response=""
        for attempt in $(seq 1 "$RPC_CHECK_MAX_ATTEMPTS"); do
            echo "     -> 尝试 ${attempt}/${RPC_CHECK_MAX_ATTEMPTS}..."
            set +e
            rpc_response=$(curl --silent --show-error --connect-timeout 3 --max-time 10 \
                -H 'Content-Type: application/json' \
                -X POST \
                -d "$rpc_payload" \
                "$rpc_url" 2>&1)
            rpc_status=$?
            set -e

            echo "     响应: ${rpc_response}"

            if [ $rpc_status -eq 0 ] && echo "$rpc_response" | grep -q '"result"'; then
                echo "     ✅ RPC响应正常"
                rpc_success=true
                break
            fi

            if [ "$attempt" -lt "$RPC_CHECK_MAX_ATTEMPTS" ]; then
                echo "     ⚠️  无响应或异常，等待 ${RPC_CHECK_INTERVAL}s 后重试"
                sleep "$RPC_CHECK_INTERVAL"
            fi
        done

        if [ "$rpc_success" != true ]; then
            echo "❌ [$ip][node-$idx] RPC检查失败"
            failed=true
            failed_ips+=("$ip(node-$idx)")
        else
            success_count=$((success_count+1))
        fi
        idx=$((idx+1))
    done

    echo ""
    echo "📊 部署结果统计:"
    echo "   成功: $success_count/$total"
    echo "   失败: $((total-success_count))/$total"

    if [ "$failed" = true ]; then
        echo ""
        echo "❌ 部分节点RPC检查失败，失败列表:"
        for failed_ip in "${failed_ips[@]}"; do
            echo "   - $failed_ip"
        done
        exit 1
    fi
    echo "✅ 所有节点RPC检查通过"
}

# 部署全部节点
idx=1
for ip in $IPS; do
    extra_env=""
    if [ -n "${L1_STATE_SENDER_ADDR:-}" ]; then
        extra_env+="export L1_STATE_SENDER_ADDR='${L1_STATE_SENDER_ADDR}'; "
    fi
    if [ -n "${L1_UNIFIED_BRIDGE_ADDR:-}" ]; then
        extra_env+="export L1_UNIFIED_BRIDGE_ADDR='${L1_UNIFIED_BRIDGE_ADDR}'; "
    fi
    if [ -n "${L1_SIMPLE_CALCULATOR_ADDR:-}" ]; then
        extra_env+="export L1_SIMPLE_CALCULATOR_ADDR='${L1_SIMPLE_CALCULATOR_ADDR}'; "
    fi
    if [ -n "${L1_CHAIN_ID:-}" ]; then
        extra_env+="export L1_CHAIN_ID='${L1_CHAIN_ID}'; "
    fi
    if [ -n "${L1_START_EPOCH:-}" ]; then
        extra_env+="export L1_START_EPOCH='${L1_START_EPOCH}'; "
    fi
    if [ -n "${L1_ADMIN_PRIVATE_KEY:-}" ]; then
        extra_env+="export L1_ADMIN_PRIVATE_KEY='${L1_ADMIN_PRIVATE_KEY}'; "
    fi
    if [ -n "${L1_ADMIN_ADDRESS:-}" ]; then
        extra_env+="export L1_ADMIN_ADDRESS='${L1_ADMIN_ADDRESS}'; "
    fi
    auto_flag=""
    fetch_flag="$FETCH_L1_FROM_NODE1"
    if [ -n "$AUTO_DEPLOY_L1_CONTRACTS" ]; then
        if [ "$idx" -eq "$AUTO_DEPLOY_NODE_ID" ]; then
            auto_flag="$AUTO_DEPLOY_L1_CONTRACTS"
            fetch_flag=""
        else
            if [ -z "$fetch_flag" ]; then
                fetch_flag="true"
            fi
        fi
    fi
    launch_deploy "$ip" "$idx" "$auto_flag" "$extra_env" "$fetch_flag"
    idx=$((idx+1))
done

if [ ${#DEPLOY_PIDS[@]} -gt 0 ]; then
    wait_for_deploys
fi

rpc_health_check_all

echo ""
echo "🎉 联盟链 '$CHAIN_NAME' 所有节点部署成功！"
echo ""
echo "📡 链服务信息:"
echo "   链名称: $CHAIN_NAME"
echo "   P2P端口: $P2P_PORT"
echo "   RPC端口组: $BASE_RPC_PORT-$((BASE_RPC_PORT + 3))"
echo ""
echo "📋 节点服务地址:"

i=1
for ip in $IPS; do
    node_id="node-$i"
    echo "   $node_id ($ip):"
    echo "      HTTP JSON-RPC: http://$ip:$BASE_RPC_PORT"
    echo "      Local HTTP JSON-RPC: http://$ip:$((BASE_RPC_PORT + 1))"
    echo "      gRPC TCP: $ip:$((BASE_RPC_PORT + 2))"
    echo "      TCP JSON-RPC: $ip:$((BASE_RPC_PORT + 3))"
    i=$((i+1))
done

echo ""
echo "🔧 管理命令示例:"
echo "   # 查看节点日志"
i=1
for ip in $IPS; do
    node_name="${CHAIN_NAME}_node-$i"
    printf "   ssh -i \"%s\" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new %s@%s 'docker logs %s'\n" "$SSH_KEY_PATH" "$SSH_USER" "$ip" "$node_name"
    i=$((i+1))
done

echo ""
echo "   # 停止整条链"
i=1
for ip in $IPS; do
    node_name="${CHAIN_NAME}_node-$i"
    printf "   ssh -i \"%s\" -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new %s@%s 'docker stop %s'\n" "$SSH_KEY_PATH" "$SSH_USER" "$ip" "$node_name"
    i=$((i+1))
done

echo ""
echo "📁 详细日志位置: $LOG_DIR/"
