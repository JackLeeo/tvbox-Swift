const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

const PORT = 3000;

// 启动 HTTP 服务器
const server = http.createServer((req, res) => {
    // 健康检查端点（供 Swift 端测试服务器是否启动）
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('OK');
        return;
    }

    // 主解析端点
    if (req.method === 'POST' && req.url === '/parse') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            try {
                const request = JSON.parse(body);
                const { action, api, key, ext, tid, page, filters, vod_id, wd, url, headers } = request;

                // 如果有 url 字段，执行通用解析（兼容旧版）
                if (url) {
                    parseGeneric(url, headers)
                        .then(data => sendJson(res, { success: true, data }))
                        .catch(err => sendJson(res, { success: false, error: err.message }));
                    return;
                }

                // 根据 action 调用对应的解析函数
                let promise;
                switch (action) {
                    case 'home':
                        promise = parseHome(api, key, ext);
                        break;
                    case 'list':
                        promise = parseList(api, key, ext, tid, page, filters);
                        break;
                    case 'detail':
                        promise = parseDetail(api, key, ext, vod_id);
                        break;
                    case 'search':
                        promise = parseSearch(api, key, ext, wd);
                        break;
                    default:
                        throw new Error(`未知的 action: ${action}`);
                }

                promise
                    .then(data => sendJson(res, { success: true, data }))
                    .catch(err => sendJson(res, { success: false, error: err.message }));

            } catch (err) {
                sendJson(res, { success: false, error: err.message });
            }
        });
        return;
    }

    // 其他请求返回 404
    res.writeHead(404);
    res.end();
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`[Node] HTTP server running on http://127.0.0.1:${PORT}`);
});

function sendJson(res, obj) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(obj));
}

// ---------- 以下为解析函数，与之前保持一致 ----------

function parseGeneric(url, headers = {}) {
    return fetchRemoteScript(url, headers, 10000)
        .then(remoteScript => executeScript(remoteScript));
}

function parseHome(api, key, ext) {
    const url = buildJarRequestUrl(api, { action: 'home', key, ext });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

function parseList(api, key, ext, tid, page = 1, filters = {}) {
    const url = buildJarRequestUrl(api, {
        action: 'list',
        key, ext, tid, page,
        filters: JSON.stringify(filters)
    });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

function parseDetail(api, key, ext, vodId) {
    const url = buildJarRequestUrl(api, { action: 'detail', key, ext, ids: vodId });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

function parseSearch(api, key, ext, wd) {
    const url = buildJarRequestUrl(api, { action: 'search', key, ext, wd });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

function buildJarRequestUrl(baseApi, params) {
    if (baseApi.startsWith('http://') || baseApi.startsWith('https://')) {
        const urlObj = new URL(baseApi);
        Object.entries(params).forEach(([k, v]) => {
            if (v !== undefined && v !== null && v !== '') {
                urlObj.searchParams.set(k, String(v));
            }
        });
        return urlObj.toString();
    }
    throw new Error('无效的 jar 源 API 地址');
}

function getDefaultHeaders() {
    return {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
        'Referer': 'https://tvbox.example.com'
    };
}

function executeScript(scriptContent) {
    const sandbox = {
        result: {},
        setResult: (data) => { sandbox.result = data; },
        console: console,
        require: require,
        module: module,
        exports: exports
    };
    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, {
        filename: 'type3-remote.js',
        timeout: 10000
    });
    return sandbox.result;
}

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
