const rn_bridge = require('rn-bridge');
const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

// 监听来自 Swift 的消息
rn_bridge.channel.on('message', (msg) => {
    try {
        const type3Data = JSON.parse(msg);
        const requestId = type3Data.id;
        
        if (!type3Data.url) {
            throw new Error('缺少源地址');
        }
        
        fetchRemoteScript(type3Data.url, type3Data.headers, 10000)
            .then(remoteScript => {
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
                
                rn_bridge.channel.send(JSON.stringify({
                    id: requestId,
                    success: true,
                    data: sandbox.result
                }));
            })
            .catch(error => {
                rn_bridge.channel.send(JSON.stringify({
                    id: type3Data.id,
                    success: false,
                    error: error.message
                }));
            });
    } catch (error) {
        rn_bridge.channel.send(JSON.stringify({
            id: type3Data?.id,
            success: false,
            error: error.message
        }));
    }
});

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
