#!/usr/bin/env python3
"""
兼容性配置处理脚本 - 在现有配置基础上进行IP替换，并可选自动部署L1合约
"""
import os
import sys
from pathlib import Path
from typing import Any, Dict, Optional, Tuple

# 默认L1部署参数（与deploy_l1_contracts.py保持一致）
DEFAULT_L1_ADMIN_PRIVATE_KEY = "148ab921959d9064168f84e801729806612d7ec1685f6dd5ea1fb3940b69a001"
DEFAULT_L1_RPC_URL = "ws://8.217.148.141/rpc/ws"
DEFAULT_L1_CHAIN_ID = 3151908

def _parse_bool_env(key: str) -> bool:
    val = os.environ.get(key, "")
    return val.lower() in ("1", "true", "yes", "on")


def _normalize_hex_key(raw_key: str) -> str:
    if raw_key.startswith("0x") or raw_key.startswith("0X"):
        return raw_key[2:]
    return raw_key


def _strip_hex_prefix(raw: str) -> str:
    if raw.startswith("0x") or raw.startswith("0X"):
        return raw[2:]
    return raw


def _apply_kv_updates(
    content: str, updates: Dict[str, Any], unquoted_keys: Optional[set] = None
) -> Tuple[str, Dict[str, Any]]:
    """在配置内容中更新/追加键值对，返回新的内容和实际写入的键。

    unquoted_keys 中的键按原样写入（不带引号），用于数值等非字符串。
    """
    unquoted_keys = unquoted_keys or set()
    lines = content.splitlines()
    remaining = dict(updates)
    applied: Dict[str, Any] = {}

    for idx, line in enumerate(lines):
        stripped = line.strip()
        for key in list(remaining.keys()):
            if stripped.startswith(f"{key} "):
                if key in unquoted_keys:
                    lines[idx] = f"{key} = {remaining[key]}"
                else:
                    lines[idx] = f'{key} = "{remaining[key]}"'
                applied[key] = remaining.pop(key)
                break

    if remaining:
        if not lines or lines[-1].strip() != "":
            lines.append("")
        for key, value in remaining.items():
            if key in unquoted_keys:
                lines.append(f"{key} = {value}")
            else:
                lines.append(f'{key} = "{value}"')
            applied[key] = value

    updated_content = "\n".join(lines)
    if not updated_content.endswith("\n"):
        updated_content += "\n"
    return updated_content, applied


def make_web3(rpc_url: str):
    try:
        from web3 import Web3, HTTPProvider
        from web3.providers.websocket import WebsocketProvider
    except ImportError as exc:
        print(f"❌ 缺少web3依赖: {exc}")
        sys.exit(1)

    if rpc_url.startswith("ws"):
        provider = WebsocketProvider(rpc_url)
    else:
        provider = HTTPProvider(rpc_url)
    w3 = Web3(provider)
    is_connected = w3.is_connected() if hasattr(w3, "is_connected") else w3.isConnected()
    if not is_connected:
        raise RuntimeError(f"无法连接到RPC: {rpc_url}")
    return w3


def deploy_contract(
    w3: Any, account: Any, bytecode: str, nonce: int, chain_id: int, gas_price: Optional[int] = None
) -> Tuple[str, str]:
    tx: Dict[str, Any] = {
        "from": account.address,
        "value": 0,
        "data": bytecode,
        "nonce": nonce,
        "chainId": chain_id,
    }
    tx["gasPrice"] = gas_price if gas_price is not None else w3.eth.gas_price
    tx["gas"] = w3.eth.estimate_gas(tx)

    signed = account.sign_transaction(tx)
    tx_hash = w3.eth.send_raw_transaction(signed.rawTransaction)
    receipt = w3.eth.wait_for_transaction_receipt(tx_hash, timeout=600, poll_latency=3)

    status = receipt.get("status", 0)
    if status != 1:
        raise RuntimeError(f"部署失败, tx={tx_hash.hex()}, receipt={receipt}")

    contract_address = receipt.get("contractAddress")
    if not contract_address:
        raise RuntimeError(f"交易 {tx_hash.hex()} 的回执中缺少合约地址")

    return tx_hash.hex(), contract_address


def auto_deploy_l1_contracts(
    rpc_url: str, chain_id: Optional[int], private_key: str, gas_price: Optional[int]
) -> Dict[str, str]:
    """使用内置逻辑部署L1合约，并返回需要写入配置的键值。

    部署前会从RPC获取链ID和当前高度（作为l1_start_epoch），无需额外传参。
    """
    try:
        from eth_account import Account
    except ImportError as exc:
        print(f"❌ 缺少eth_account依赖: {exc}")
        sys.exit(1)

    # 合约字节码与deploy_l1_contracts.py保持一致
    from deploy_l1_contracts import (  # type: ignore
        L1_SIMPLE_CALCULATOR_BYTECODE,
        L1_STATE_SENDER_BYTECODE,
        L1_UNIFIED_BRIDGE_BYTECODE,
    )

    bytecodes = {
        "state_sender": L1_STATE_SENDER_BYTECODE,
        "unified_bridge": L1_UNIFIED_BRIDGE_BYTECODE,
        "simple_calculator": L1_SIMPLE_CALCULATOR_BYTECODE,
    }

    w3 = make_web3(rpc_url)
    account = Account.from_key(private_key)

    detected_chain_id = chain_id
    if detected_chain_id is None:
        try:
            detected_chain_id = w3.eth.chain_id
        except Exception:
            detected_chain_id = DEFAULT_L1_CHAIN_ID

    try:
        start_epoch = int(w3.eth.block_number)
    except Exception:
        start_epoch = None

    print(f"🚀 自动部署L1合约: rpc={rpc_url}, chain_id={detected_chain_id}")
    print(f"👤 部署账户: {account.address}")

    current_nonce = w3.eth.get_transaction_count(account.address)
    deployments: Dict[str, str] = {}

    for name in ["state_sender", "unified_bridge", "simple_calculator"]:
        print(f"🔧 部署 {name} ...")
        tx_hash, contract_address = deploy_contract(
            w3, account, bytecodes[name], current_nonce, detected_chain_id, gas_price=gas_price
        )
        print(f"   tx: {tx_hash}")
        print(f"   合约地址: {contract_address}")
        deployments[name] = contract_address
        current_nonce += 1

    print("✅ L1合约部署完成")

    results = {
        "l1_state_sender_addr": _strip_hex_prefix(deployments["state_sender"]),
        "l1_unified_bridge_addr": _strip_hex_prefix(deployments["unified_bridge"]),
        "l1_simple_calculator_addr": _strip_hex_prefix(deployments["simple_calculator"]),
        "l1_admin_private_key": _normalize_hex_key(private_key),
        "l1_admin_address": _strip_hex_prefix(account.address),
        "l1_chain_id": int(detected_chain_id),
    }
    if start_epoch is not None:
        results["l1_start_epoch"] = int(start_epoch)
    return results


def process_existing_config():
    """处理现有配置文件，替换硬编码IP并可选写入L1合约配置"""

    # 从环境变量获取参数
    node_id = os.environ.get('NODE_ID')
    node1_ip = os.environ.get('NODE1_IP')
    node2_ip = os.environ.get('NODE2_IP')
    node3_ip = os.environ.get('NODE3_IP')
    node4_ip = os.environ.get('NODE4_IP')
    chain_name = os.environ.get('CHAIN_NAME', 'testchain')
    p2p_port = os.environ.get('P2P_PORT', '30005')  # 新增P2P端口参数
    l1_espace_rpc_url = os.environ.get('L1_ESPACE_RPC_URL')
    l1_corespace_rpc_url = os.environ.get('L1_CORESPACE_RPC_URL')
    l1_chain_id_env = os.environ.get('L1_CHAIN_ID')
    l1_admin_pk_env = os.environ.get('L1_ADMIN_PRIVATE_KEY')
    l1_admin_address_env = os.environ.get('L1_ADMIN_ADDRESS')
    l1_gas_price_env = os.environ.get('L1_GAS_PRICE')
    l1_start_epoch_env = os.environ.get('L1_START_EPOCH')

    auto_deploy = _parse_bool_env('AUTO_DEPLOY_L1_CONTRACTS') or _parse_bool_env('DEPLOY_L1_CONTRACTS')
    print(f"🔧 auto_deploy={auto_deploy} node_id={node_id}")

    # 参数验证
    if not node_id or node_id not in ['1', '2', '3', '4']:
        print(f"❌ 错误: NODE_ID必须是1-4，当前: {node_id}")
        sys.exit(1)

    if not all([node1_ip, node2_ip, node3_ip, node4_ip]):
        print("❌ 错误: 必须提供所有节点IP")
        sys.exit(1)

    # 现有硬编码IP映射分析：
    # 由于现在所有节点都使用统一的P2P端口，需要更新映射逻辑
    # 原来的端口mapping：30006->node2, 30007->node4, 30008->node3, 30005->node1
    # 现在统一使用p2p_port

    # 正确的IP映射（按照consortium_nodes中的顺序，但端口统一）
    old_ip_mappings = {
        f'139.224.187.155:30006': f'{node2_ip}:{p2p_port}',  # consortium_nodes[0] -> node-2
        f'47.116.165.80:30007': f'{node4_ip}:{p2p_port}',    # consortium_nodes[1] -> node-4
        f'47.116.165.80:30008': f'{node3_ip}:{p2p_port}',    # consortium_nodes[2] -> node-3
        f'139.224.187.155:30005': f'{node1_ip}:{p2p_port}'   # consortium_nodes[3] -> node-1
    }

    # 读取现有配置
    config_path = '/opt/blockchain/config.toml'
    if not Path(config_path).exists():
        print(f"❌ 错误: 配置文件不存在: {config_path}")
        sys.exit(1)

    with open(config_path, 'r') as f:
        config_content = f.read()

    # 替换IP地址
    for old_addr, new_addr in old_ip_mappings.items():
        config_content = config_content.replace(old_addr, new_addr)
        print(f"🔄 替换: {old_addr} -> {new_addr}")

    # 写回配置文件
    with open(config_path, 'w') as f:
        f.write(config_content)

    # 处理customized_config.toml (如果存在)
    custom_config_path = '/opt/blockchain/customized_config.toml'
    if Path(custom_config_path).exists():
        with open(custom_config_path, 'r') as f:
            custom_content = f.read()

        for old_addr, new_addr in old_ip_mappings.items():
            custom_content = custom_content.replace(old_addr, new_addr)

        config_updates: Dict[str, str] = {}
        if l1_espace_rpc_url:
            config_updates['l1_espace_rpc_url'] = l1_espace_rpc_url
        if l1_corespace_rpc_url:
            config_updates['l1_corespace_rpc_url'] = l1_corespace_rpc_url

        manual_overrides = {
            "l1_state_sender_addr": _strip_hex_prefix(os.environ.get("L1_STATE_SENDER_ADDR")) if os.environ.get("L1_STATE_SENDER_ADDR") else None,
            "l1_unified_bridge_addr": _strip_hex_prefix(os.environ.get("L1_UNIFIED_BRIDGE_ADDR")) if os.environ.get("L1_UNIFIED_BRIDGE_ADDR") else None,
            "l1_simple_calculator_addr": _strip_hex_prefix(os.environ.get("L1_SIMPLE_CALCULATOR_ADDR")) if os.environ.get("L1_SIMPLE_CALCULATOR_ADDR") else None,
            "l1_admin_private_key": _normalize_hex_key(l1_admin_pk_env) if l1_admin_pk_env else None,
            "l1_admin_address": _strip_hex_prefix(l1_admin_address_env) if l1_admin_address_env else None,
        }
        if l1_start_epoch_env:
            try:
                manual_overrides["l1_start_epoch"] = int(l1_start_epoch_env)
            except ValueError:
                print(f"❌ L1_START_EPOCH 非法: {l1_start_epoch_env}")
                sys.exit(1)
        manual_overrides = {k: v for k, v in manual_overrides.items() if v}
        if manual_overrides:
            print(f"🔧 手动覆盖项: {manual_overrides}")

        if auto_deploy:
            rpc_for_deploy = l1_espace_rpc_url or DEFAULT_L1_RPC_URL
            chain_id: Optional[int] = None
            if l1_chain_id_env:
                try:
                    chain_id = int(l1_chain_id_env)
                except ValueError:
                    print(f"❌ L1_CHAIN_ID 非法: {l1_chain_id_env}")
                    sys.exit(1)

            gas_price = None
            if l1_gas_price_env:
                try:
                    gas_price = int(l1_gas_price_env)
                except ValueError:
                    print(f"❌ L1_GAS_PRICE 非法: {l1_gas_price_env}")
                    sys.exit(1)

            private_key_for_deploy = _normalize_hex_key(l1_admin_pk_env) if l1_admin_pk_env else DEFAULT_L1_ADMIN_PRIVATE_KEY
            deploy_results = auto_deploy_l1_contracts(
                rpc_for_deploy, chain_id, private_key_for_deploy, gas_price
            )
            config_updates.update(deploy_results)
        elif manual_overrides:
            if "l1_admin_private_key" in manual_overrides and "l1_admin_address" not in manual_overrides:
                try:
                    from eth_account import Account
                except ImportError as exc:
                    print(f"❌ 缺少eth_account依赖以计算地址: {exc}")
                    sys.exit(1)
                derived = Account.from_key(manual_overrides["l1_admin_private_key"]).address
                derived = _strip_hex_prefix(derived)
                manual_overrides["l1_admin_address"] = derived
            config_updates.update(manual_overrides)
        if l1_chain_id_env:
            try:
                config_updates["l1_chain_id"] = int(l1_chain_id_env)
            except ValueError:
                print(f"❌ L1_CHAIN_ID 非法: {l1_chain_id_env}")
                sys.exit(1)

        if config_updates:
            custom_content, applied = _apply_kv_updates(
                custom_content, config_updates, unquoted_keys={"l1_chain_id", "l1_start_epoch"}
            )
            for key, value in applied.items():
                print(f"🔧 写入 {key} -> {value}")
        else:
            print("⚠️ 未发现需要写入的 L1 相关配置（可能缺少环境变量或自动部署未开启）")

        with open(custom_config_path, 'w') as f:
            f.write(custom_content)
        print(f"✅ 处理自定义配置: {custom_config_path}")
    else:
        if auto_deploy:
            print("❌ 找不到customized_config.toml，无法写入自动部署结果")
            sys.exit(1)

    print(f"🎉 节点{node_id}配置处理完成!")
    print(f"📍 链名称: {chain_name}")
    print(f"📍 P2P端口: {p2p_port} (统一)")
    if l1_espace_rpc_url:
        print(f"📍 L1 eSpace RPC: {l1_espace_rpc_url}")
    if l1_corespace_rpc_url:
        print(f"📍 L1 CoreSpace RPC: {l1_corespace_rpc_url}")
    if auto_deploy:
        print("📍 已执行L1合约自动部署并写入配置")
    elif Path('/opt/blockchain/customized_config.toml').exists():
        env_overrides = [
            key for key in ["L1_STATE_SENDER_ADDR", "L1_UNIFIED_BRIDGE_ADDR", "L1_SIMPLE_CALCULATOR_ADDR", "L1_ADMIN_PRIVATE_KEY", "L1_ADMIN_ADDRESS"]
            if os.environ.get(key)
        ]
        if env_overrides:
            print(f"📍 已使用环境变量覆盖: {', '.join(env_overrides)}")
    print(f"📍 IP映射完成:")
    for old, new in old_ip_mappings.items():
        print(f"   {old} -> {new}")


if __name__ == "__main__":
    process_existing_config()
