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

所以跨链交易涉及到 4 个合约： 源链A l1 state sender, 源链A l1 unified bridge, 目标链B l1 state sender，目标链B l2 unified bridge

梓含的 l1_bridge_relay_contract 需要注册两个合约： l1_state_sender 和 l1_unified_bridge

## L2 桥合约地址是固定的
1. l2_state_sender: 0x8e63912845b8785797e3c6680767da4a4a0f3c5a
2. l2_unified_bridge: 0x8226ed70c17e6c544b0d602f5cbddcb9f84d1314

## RPC

- 获取合约信息 `cast rpc layer2_getBridgeInfo --rpc-url http://35.95.146.7:30010`

## 查看跨链状态
- `http://139.224.187.155:30000/` 配置 l1 l2 url 即可使用

# 附录
- 公开测试RPC： http://139.224.187.155:30009
- 默认 L2 RPC 端口：30010
- 创始有cfx的账户： 0xc28da5b949956922986bab322e320acf159ea5da3a5f97dbd643a6b049bc89ed: 0x16132f425a796019f8a011bfa10f43113ca91b45