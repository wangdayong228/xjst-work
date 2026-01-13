#!/bin/bash
# 清理联盟链部署脚本
# 用法: ./cleanup_chain.sh <链名称> [ssh_user] [ssh_password] [remove_images] [node1_ip] [node2_ip] [node3_ip] [node4_ip]

set -e

CHAIN_NAME="$1"
SSH_USER="${2:-ubuntu}"
SSH_PASSWORD="$3"
REMOVE_IMAGES="${4:-false}"  # 新增：是否删除镜像

# SSH执行函数
ssh_exec() {
    local host="$1"
    local command="$2"
    
    if [ -n "$SSH_PASSWORD" ]; then
        # 使用密码认证
        sshpass -p "$SSH_PASSWORD" ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$host" "$command"
    else
        # 使用免密登录
        ssh -o StrictHostKeyChecking=no -o ConnectTimeout=10 "$SSH_USER@$host" "$command"
    fi
}

if [ -z "$CHAIN_NAME" ]; then
    echo "🧹 联盟链清理脚本"
    echo ""
    echo "用法:"
    echo "  $0 <链名称> [ssh_user] [ssh_password] [remove_images] [node1_ip] [node2_ip] [node3_ip] [node4_ip]"
    echo ""
    echo "参数:"
    echo "  链名称       - 要清理的链名称"
    echo "  ssh_user     - SSH用户名 (默认: ubuntu)"
    echo "  ssh_password - SSH密码 (可选，不提供则使用免密登录)"
    echo "  remove_images - 是否删除镜像 (可选: true/false，默认false)"
    echo "  node*_ip     - 节点IP地址 (如果提供，将自动清理这些节点)"
    echo ""
    echo "示例:"
    echo "  # 使用免密登录，只清理容器"
    echo "  $0 testchain ubuntu"
    echo ""
    echo "  # 使用密码，清理容器和镜像"
    echo "  $0 testchain ubuntu mypassword true 192.168.1.10 192.168.1.11 192.168.1.12 192.168.1.13"
    echo ""
    echo "  # 仅提供密码，手动清理"
    echo "  $0 testchain ubuntu mypassword false"
    exit 1
fi

echo "🧹 清理联盟链: $CHAIN_NAME"
echo "📍 SSH用户: $SSH_USER"
echo "📍 SSH认证: $([ -n "$SSH_PASSWORD" ] && echo "密码认证" || echo "免密登录")"
echo "📍 删除镜像: $([ "$REMOVE_IMAGES" = "true" ] && echo "是" || echo "否")"

# 检查sshpass工具（如果使用密码）
if [ -n "$SSH_PASSWORD" ]; then
    if ! command -v sshpass >/dev/null 2>&1; then
        echo "❌ 错误: 使用密码认证需要安装sshpass工具"
        echo "安装命令:"
        echo "  Ubuntu/Debian: sudo apt-get install sshpass"
        echo "  CentOS/RHEL:   sudo yum install sshpass"
        echo "  macOS:         brew install hudochenkov/sshpass/sshpass"
        exit 1
    fi
fi

echo ""

# 如果提供了IP参数，则自动清理
if [ $# -ge 8 ]; then
    NODE1_IP="$5"
    NODE2_IP="$6" 
    NODE3_IP="$7"
    NODE4_IP="$8"
    
    IPS=($NODE1_IP $NODE2_IP $NODE3_IP $NODE4_IP)
    
    echo "🛑 停止并删除容器..."
    for i in {1..4}; do
        ip=${IPS[$((i-1))]}
        # 支持两种命名格式：新格式(node1)和旧格式(node-1)
        container_name1="${CHAIN_NAME}_node${i}"
        container_name2="${CHAIN_NAME}_node-${i}"
        
        echo "   清理节点$i: $ip"
        ssh_exec "$ip" "
            found=0
            matched_name=""
            for cname in '$container_name1' '$container_name2'; do
                if [ -z "\$cname" ]; then
                    continue
                fi
                if docker ps -a --format '{{.Names}}' | grep -qx "\$cname"; then
                    echo \"停止容器: \$cname\"
                    docker stop "\$cname" 2>/dev/null || true
                    echo \"删除容器: \$cname\"
                    docker rm "\$cname" 2>/dev/null || true
                    found=1
                    matched_name="\$cname"
                    break
                fi
            done
            if [ \$found -eq 1 ]; then
                echo \"✅ 节点$i容器清理完成 (匹配: \$matched_name)\"
            else
                matched_list=\$(docker ps -a --format '{{.Names}}' | grep -E '^${CHAIN_NAME}_node-?[0-9]+$' || true)
                if [ -n "\$matched_list" ]; then
                    echo \"⚠️ 未找到节点$i对应容器，当前同链容器:\"
                    echo \"\$matched_list\"
                else
                    echo \"容器不存在: $container_name1 (或旧格式: $container_name2)\"
                fi
            fi
        " &
    done
    wait
    
    # 如果需要删除镜像
    if [ "$REMOVE_IMAGES" = "true" ]; then
        echo ""
        echo "🗑️  删除镜像..."
        for i in {1..4}; do
            ip=${IPS[$((i-1))]}
            image_name="consortium-blockchain:node-${i}"
            
            echo "   删除节点$i镜像: $ip"
            ssh_exec "$ip" "
                if docker images --format '{{.Repository}}:{{.Tag}}' | grep -q '^${image_name}$'; then
                    echo '删除镜像: $image_name'
                    docker rmi $image_name 2>/dev/null || true
                    echo '✅ 节点$i镜像删除完成'
                else
                    echo '镜像不存在: $image_name'
                fi
            " &
        done
        wait
        echo "✅ 所有镜像清理完成"
    fi
    
    echo "🎉 联盟链 '$CHAIN_NAME' 清理完成！"
else
    # 显示手动清理提示
    echo "❗ 请手动清理或提供节点IP参数进行自动清理"
    echo ""
    echo "手动清理命令:"
    if [ -n "$SSH_PASSWORD" ]; then
        echo "  # 清理容器 (新格式: node1)"
        echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node1 && docker rm ${CHAIN_NAME}_node1'"
        echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node2 && docker rm ${CHAIN_NAME}_node2'"  
        echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node3 && docker rm ${CHAIN_NAME}_node3'"
        echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node4 && docker rm ${CHAIN_NAME}_node4'"
        echo ""
        echo "  # 或清理容器 (旧格式: node-1，向后兼容)"
        echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node-1 && docker rm ${CHAIN_NAME}_node-1'"
        echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node-2 && docker rm ${CHAIN_NAME}_node-2'"  
        echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node-3 && docker rm ${CHAIN_NAME}_node-3'"
        echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node-4 && docker rm ${CHAIN_NAME}_node-4'"
        
        if [ "$REMOVE_IMAGES" = "true" ]; then
            echo ""
            echo "  # 删除镜像"
            echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker rmi consortium-blockchain:node-1'"
            echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker rmi consortium-blockchain:node-2'"
            echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker rmi consortium-blockchain:node-3'"
            echo "  sshpass -p '$SSH_PASSWORD' ssh $SSH_USER@node_ip 'docker rmi consortium-blockchain:node-4'"
        fi
    else
        echo "  # 清理容器 (新格式: node1)"
        echo "  ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node1 && docker rm ${CHAIN_NAME}_node1'"
        echo "  ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node2 && docker rm ${CHAIN_NAME}_node2'"  
        echo "  ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node3 && docker rm ${CHAIN_NAME}_node3'"
        echo "  ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node4 && docker rm ${CHAIN_NAME}_node4'"
        echo ""
        echo "  # 或清理容器 (旧格式: node-1，向后兼容)"
        echo "  ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node-1 && docker rm ${CHAIN_NAME}_node-1'"
        echo "  ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node-2 && docker rm ${CHAIN_NAME}_node-2'"  
        echo "  ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node-3 && docker rm ${CHAIN_NAME}_node-3'"
        echo "  ssh $SSH_USER@node_ip 'docker stop ${CHAIN_NAME}_node-4 && docker rm ${CHAIN_NAME}_node-4'"
        
        if [ "$REMOVE_IMAGES" = "true" ]; then
            echo ""
            echo "  # 删除镜像"
            echo "  ssh $SSH_USER@node_ip 'docker rmi consortium-blockchain:node-1'"
            echo "  ssh $SSH_USER@node_ip 'docker rmi consortium-blockchain:node-2'"
            echo "  ssh $SSH_USER@node_ip 'docker rmi consortium-blockchain:node-3'"
            echo "  ssh $SSH_USER@node_ip 'docker rmi consortium-blockchain:node-4'"
        fi
    fi
    echo ""
    echo "或者提供IP参数进行自动清理:"
    echo "  $0 $CHAIN_NAME $SSH_USER $([ -n "$SSH_PASSWORD" ] && echo "\"$SSH_PASSWORD\"" || echo "\"\"") $REMOVE_IMAGES 192.168.1.10 192.168.1.11 192.168.1.12 192.168.1.13"
fi
