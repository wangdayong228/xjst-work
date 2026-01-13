export SSH_KEY_PATH="$HOME/.ssh/4node-test.pem"
export IPS="16.52.84.122 3.98.164.64 16.52.149.43 3.97.182.183"
export L1_ESPACE_RPC_URL="ws://47.243.70.39/ws"
# 用于L1发送交易的管理员地址私钥
export L1_ADMIN_PRIVATE_KEY=0xd01fd3d7fdcc808840d676f4cbff81af45b2641d414d7a00e25c7bf8cc6c7e97
# 用于L1发送交易的管理员地址
export L1_ADMIN_ADDRESS=0x92f7c5C26c3AD9f46FB38593952248d66Daa374C
# 设置true启用, 开启自动部署合约，否则用程序硬编码的配置。
export AUTO_DEPLOY_L1_CONTRACTS=true
./client_undeploy.sh
