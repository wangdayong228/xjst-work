# 树图联盟链

# 地址及私钥

1. [L1_ADMIN_PRIVATE_KEY](./client/client_deploy.sh) 中 L1_ADMIN_PRIVATE_KEY : 
   - L1部署L1合约
   - 处理 L2 -> L1 的跨链交易

# 桥合约
桥合约分为发送合约和接受合约，而两条链都需要这两种合约
1. 发送桥合约为 state sender 合约
2. 接收桥合约为 unified bridge 合约

所以跨链交易涉及到 4 个合约： 源链 state sender, 源链 unified bridge, 目标链 state sender，源链 unified bridge

梓含的 l1_bridge_relay_contract 需要注册两个合约： l1_state_sender 和 l1_unified_bridge

# 附录
- 公开测试RPC： http://139.224.187.155:30009
- 默认 L2 RPC 端口：30010