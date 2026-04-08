const http = require('http');
const https = require('https');
const vm = require('vm');

// 监听 Swift 传递的消息（来自 node_post_message）
process.on('message', async (message) => {
    try {
        const type3Data = JSON.parse(message);
        if (type3Data.type !== 3) throw new Error('Not a type=3 source');
        
        // 1. 加载 type=3 源的远程 JS 脚本
        const remoteScript = await fetchRemoteScript(type3Data.url, type3Data.headers);
        
        // 2. 在沙箱环境中执行远程 JS（避免污染 Node 环境）
        const sandbox = {
            // tvbox 协议约定的全局变量（远程 JS 会使用这些变量输出结果）
            result: {},
            setResult: (data) => { sandbox.result = data; },
            log: (msg) => console.log(`[Type3 Log]: ${msg}`)
        };
        vm.createContext(sandbox);
        vm.runInContext(remoteScript, sandbox, {
            filename: 'type3-remote-script.js',
            timeout: 10000 // 10秒超时，避免死循环
        });
        
        // 3. 将解析结果回传给 Swift
        process.send(JSON.stringify({
            success: true,
            data: sandbox.result,
            sourceUrl: type3Data.url
        }));
    } catch (error) {
        // 错误处理
        process.send(JSON.stringify({
            success: false,
            error: error.message,
            stack: error.stack
        }));
    }
});

/**
 * 加载远程 JS 脚本
 * @param {string} url - 远程脚本 URL
 * @param {object} headers - 请求头
 */
function fetchRemoteScript(url, headers) {
    return new Promise((resolve, reject) => {
        const protocol = url.startsWith('https') ? https : http;
        const req = protocol.get(url, { headers }, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => resolve(data));
        });
        
        req.on('error', (err) => reject(new Error(`Fetch failed: ${err.message}`)));
        req.end();
    });
}

// 初始化完成通知（可选）
process.send(JSON.stringify({ status: 'nodejs_ready' }));
