const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

// 监听 Swift 传递的消息
process.on('message', async (message) => {
    try {
        const type3Data = JSON.parse(message);
        const requestId = type3Data.id;
        
        if (type3Data.type !== 3) {
            throw new Error('不是type=3源');
        }
        
        // 1. 加载远程脚本，带10秒超时
        const remoteScript = await fetchRemoteScript(type3Data.url, type3Data.headers, 10000);
        
        // 2. 沙箱执行，10秒超时，避免污染主环境
        const sandbox = {
            result: {},
            setResult: (data) => { sandbox.result = data; },
            log: (msg) => console.log(`[Type3] ${msg}`),
            console: console,
            require: require,
            module: module,
            exports: exports
        };
        vm.createContext(sandbox);
        vm.runInContext(remoteScript, sandbox, {
            filename: 'type3-remote.js',
            timeout: 10000
        });
        
        // 3. 返回结果，带上请求ID
        process.send(JSON.stringify({
            id: requestId,
            success: true,
            data: sandbox.result
        }));
        
    } catch (error) {
        // 错误返回
        process.send(JSON.stringify({
            id: type3Data?.id,
            success: false,
            error: error.message
        }));
    }
});

// 带超时的远程请求
function fetchRemoteScript(url, headers, timeout) {
    return new Promise((resolve, reject) => {
        const parsedUrl = URL.parse(url);
        const client = parsedUrl.protocol === 'https:' ? https : http;
        
        const req = client.get(url, { headers }, (res) => {
            let data = '';
            res.on('data', (chunk) => data += chunk);
            res.on('end', () => resolve(data));
        });
        
        req.on('error', (err) => reject(new Error(`加载脚本失败: ${err.message}`)));
        req.setTimeout(timeout, () => {
            req.destroy();
            reject(new Error('加载脚本超时'));
        });
        req.end();
    });
}

// 通知 Swift 已就绪，处理缓存的消息
process.send(JSON.stringify({ status: 'nodejs_ready' }));
