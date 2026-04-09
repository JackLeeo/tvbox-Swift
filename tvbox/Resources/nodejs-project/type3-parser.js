const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

process.on('message', (message) => {
    try {
        const type3Data = JSON.parse(message);
        const requestId = type3Data.id;

        if (!type3Data.url) {
            throw new Error('缺少源地址');
        }

        fetchRemoteScript(type3Data.url, type3Data.headers, 10000)
            .then(remoteScript => {
                const sandbox = {
                    result: {},
                    setResult: (data) => { sandbox.result = data; },
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

                process.send(JSON.stringify({
                    id: requestId,
                    success: true,
                    data: sandbox.result
                }));
            })
            .catch(error => {
                process.send(JSON.stringify({
                    id: type3Data.id,
                    success: false,
                    error: error.message
                }));
            });
    } catch (error) {
        process.send(JSON.stringify({
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
