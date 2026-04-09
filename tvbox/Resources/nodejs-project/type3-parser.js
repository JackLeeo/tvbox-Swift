const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

const PORT = 3000;

const server = http.createServer((req, res) => {
    if (req.method !== 'POST' || req.url !== '/parse') {
        res.writeHead(404);
        return res.end();
    }

    let body = '';
    req.on('data', chunk => body += chunk);
    req.on('end', () => {
        try {
            const { url, headers = {} } = JSON.parse(body);
            if (!url) throw new Error('缺少源地址');

            fetchRemoteScript(url, headers, 10000)
                .then(remoteScript => {
                    const sandbox = {
                        result: {},
                        setResult: (data) => { sandbox.result = data; },
                        console: console
                    };
                    vm.createContext(sandbox);
                    vm.runInContext(remoteScript, sandbox, {
                        filename: 'type3-remote.js',
                        timeout: 10000
                    });

                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({
                        success: true,
                        data: sandbox.result
                    }));
                })
                .catch(error => {
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({
                        success: false,
                        error: error.message
                    }));
                });
        } catch (error) {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                success: false,
                error: error.message
            }));
        }
    });
});

server.listen(PORT, () => {
    console.log(`Type3 parser HTTP server listening on port ${PORT}`);
});

function fetchRemoteScript(url, headers, timeout) {
    return new Promise((resolve, reject) => {
        const parsedUrl = URL.parse(url);
        const client = parsedUrl.protocol === 'https:' ? https : http;

        const req = client.get(url, { headers }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(data));
        });

        req.on('error', err => reject(new Error(`加载脚本失败: ${err.message}`)));
        req.setTimeout(timeout, () => {
            req.destroy();
            reject(new Error('加载脚本超时'));
        });
        req.end();
    });
}
