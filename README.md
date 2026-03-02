# 树图联盟链

# 地址及私钥

1. [L1_ADMIN_PRIVATE_KEY](./client/client_deploy.sh) 中 L1_ADMIN_PRIVATE_KEY : 
   - L1部署L1合约
   - 处理 L2 -> L1 的跨链交易
   > **xjst_pipe.sh 中为 L1_VAULT_PRIVATE_KEY**

# 桥合约
桥合约分为发送合约和接受合约，而两条链都需要这两种合约
1. 发送桥合约为 state sender 合约
2. 接收桥合约为 unified bridge 合约

所以跨链交易涉及到 4 个合约： 源链 state sender, 源链 unified bridge, 目标链 state sender，源链 unified bridge

梓含的 l1_bridge_relay_contract 需要注册两个合约： l1_state_sender 和 l1_unified_bridge

## L2 桥合约地址是固定的
1. l2_state_sender: 0x8e63912845b8785797e3c6680767da4a4a0f3c5a
2. l2_unified_bridge: 0x8226ed70c17e6c544b0d602f5cbddcb9f84d1314

# 附录
- 公开测试RPC： http://139.224.187.155:30009
- 默认 L2 RPC 端口：30010