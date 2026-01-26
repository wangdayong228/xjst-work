const ipsStr = process.argv[2];
const timeout = process.argv[3] || 3;

const DEBUG = process.env.DEBUG === '1' || process.env.DEBUG === 'true';

function log(msg) {
    console.log(`[${new Date().toISOString()}] ${msg}`);
}

function logErr(msg) {
    console.error(`[${new Date().toISOString()}] ${msg}`);
}

function logDbg(msg) {
    if (DEBUG) log(`[DBG] ${msg}`);
}

// input 格式为 "[44.252.111.46,44.247.52.12,54.245.12.147,44.249.51.138]"
function parseIps(input) {
    if (!input || typeof input !== 'string') return [];
    const s = input.trim();
    // 支持两种：
    // 1) "[ip1,ip2,...]"（不带引号）
    // 2) "ip1, ip2" 或 "ip1 ip2"
    const noBrackets = s.replace(/^\s*\[\s*/, '').replace(/\s*\]\s*$/, '');
    return noBrackets
        .split(/[,\s]+/g)
        .map((ip) => ip.trim())
        .filter(Boolean);
}

function sleep(ms) {
    return new Promise((resolve) => setTimeout(resolve, ms));
}

async function checkNodePeers(ips, retryTimes, minPeers = 3) {
    log(`启动：ipsStr=${ipsStr || ''} timeout=${timeout || ''} minPeers=${minPeers} DEBUG=${DEBUG ? '1' : '0'}`);
    if (!Array.isArray(ips) || ips.length === 0) {
        throw new Error('缺少 ips 参数：请传入逗号或空格分隔的 IP 列表');
    }

    const times = Number.isFinite(Number(retryTimes)) ? Number(retryTimes) : 0;
    const maxRetries = Math.max(0, Math.floor(times));
    log(`解析参数：ips=${ips.join(',')} maxRetries=${maxRetries} intervalMs=1000 rpcTimeoutMs=1000`);

    for (const ip of ips) {
        log(`开始检查：ip=${ip}`);
        let ok = false;
        let lastErr = null;

        for (let attempt = 0; attempt <= maxRetries; attempt++) {
            try {
                logDbg(`请求：ip=${ip} attempt=${attempt + 1}/${maxRetries + 1} method=cfx_getPeers`);
                const peerCount = await checkNodePeer(ip);
                if (peerCount >= minPeers) {
                    ok = true;
                    log(`达标：ip=${ip} peers=${peerCount} (>=${minPeers})`);
                    break;
                }

                log(`未达标：ip=${ip} peers=${peerCount} (<${minPeers}) attempt=${attempt + 1}/${maxRetries + 1}`);
            } catch (e) {
                lastErr = e;
                const msg = e && e.message ? e.message : String(e);
                log(`失败：ip=${ip} attempt=${attempt + 1}/${maxRetries + 1} err=${msg}`);
            }

            if (attempt < maxRetries) {
                logDbg(`等待重试：ip=${ip} sleepMs=1000 nextAttempt=${attempt + 2}/${maxRetries + 1}`);
                await sleep(1000);
            }
        }

        if (!ok) {
            const detail = lastErr && lastErr.message ? `，最后一次错误：${lastErr.message}` : '';
            logErr(`节点检查失败：ip=${ip} minPeers=${minPeers}${detail}`);
            throw new Error(`节点 ${ip} peers 未达标（需要 >=${minPeers}）${detail}`);
        }
        log(`完成：ip=${ip}`);
    }
}

async function jsonRpc(url, method, params, timeoutMs) {
    const start = Date.now();
    logDbg(`RPC开始：url=${url} method=${method} timeoutMs=${timeoutMs}`);
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), timeoutMs);

    try {
        const res = await fetch(url, {
            method: 'POST',
            headers: { 'content-type': 'application/json' },
            body: JSON.stringify({
                jsonrpc: '2.0',
                id: Date.now(),
                method,
                params: params ?? [],
            }),
            signal: controller.signal,
        });

        if (!res.ok) {
            throw new Error(`HTTP ${res.status} ${res.statusText}`);
        }

        const data = await res.json();
        if (data && data.error) {
            const msg = data.error.message ? data.error.message : JSON.stringify(data.error);
            throw new Error(msg);
        }
        logDbg(`RPC成功：url=${url} method=${method} costMs=${Date.now() - start}`);
        return data ? data.result : null;
    } catch (e) {
        if (e && (e.name === 'AbortError' || String(e).includes('AbortError'))) {
            throw new Error('请求超时');
        }
        throw e;
    } finally {
        logDbg(`RPC结束：url=${url} method=${method} costMs=${Date.now() - start}`);
        clearTimeout(timer);
    }
}

async function checkNodePeer(ip) {
    const url = `http://${ip}:30010`;
    const peers = await jsonRpc(url, 'cfx_getPeers', [], 1000);
    return Array.isArray(peers) ? peers.length : 0;
}

(async () => {
    const ips = parseIps(ipsStr);
    log(`解析IP：count=${ips.length}`);
    await checkNodePeers(ips, timeout, 3);
    log('全部节点检查通过');
})().catch((err) => {
    const msg = err && err.message ? err.message : String(err);
    logErr(msg);
    process.exitCode = 1;
});