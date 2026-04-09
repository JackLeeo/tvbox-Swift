const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

const PORT = 3000;

const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200, { 'Content-Type': 'text/plain' });
        res.end('OK');
        return;
    }

    if (req.method === 'POST' && req.url === '/parse') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', () => {
            try {
                const request = JSON.parse(body);
                const { action, api, key, ext, jar, tid, page, filters, vod_id, wd, url, headers } = request;

                // 通用解析
                if (url) {
                    parseGeneric(url, headers)
                        .then(data => sendJson(res, { success: true, data }))
                        .catch(err => sendJson(res, { success: false, error: err.message }));
                    return;
                }

                let promise;
                switch (action) {
                    case 'home':
                        promise = parseHome(api, key, ext, jar);
                        break;
                    case 'list':
                        promise = parseList(api, key, ext, jar, tid, page, filters);
                        break;
                    case 'detail':
                        promise = parseDetail(api, key, ext, jar, vod_id);
                        break;
                    case 'search':
                        promise = parseSearch(api, key, ext, jar, wd);
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

// ---------- 核心：构建 jar 源的真实请求 URL ----------
function buildJarRequestUrl(api, ext, jar, params) {
    // 1. 优先使用 ext 作为脚本地址（如果 ext 是 http 开头）
    if (ext && (ext.startsWith('http://') || ext.startsWith('https://'))) {
        const urlObj = new URL(ext);
        Object.entries(params).forEach(([k, v]) => {
            if (v !== undefined && v !== null && v !== '') {
                urlObj.searchParams.set(k, String(v));
            }
        });
        return urlObj.toString();
    }

    // 2. 其次使用 api 作为脚本地址（如果 api 是 http 开头）
    if (api && (api.startsWith('http://') || api.startsWith('https://'))) {
        const urlObj = new URL(api);
        Object.entries(params).forEach(([k, v]) => {
            if (v !== undefined && v !== null && v !== '') {
                urlObj.searchParams.set(k, String(v));
            }
        });
        return urlObj.toString();
    }

    // 3. 如果 api 是特殊标识符（如 csp_XXX），则需要根据 jar 源规范拼接
    // 常见的 jar 源格式：将标识符映射到固定域名
    const knownJarHosts = {
        'csp_': 'https://csp.xxx.com',   // 示例，请根据实际 jar 源文档替换
        'NewZhiZhen': 'http://你的jar服务器地址:端口'
    };

    for (const [prefix, host] of Object.knownJarHosts) {
        if (api.startsWith(prefix)) {
            const urlObj = new URL(host + '/path/to/spider'); // 具体路径需参考 jar 文档
            Object.entries(params).forEach(([k, v]) => {
                if (v !== undefined && v !== null && v !== '') {
                    urlObj.searchParams.set(k, String(v));
                }
            });
            return urlObj.toString();
        }
    }

    // 4. 如果都失败了，抛出明确错误
    throw new Error(`无法构建 jar 请求 URL。api: ${api}, ext: ${ext}`);
}

// ---------- 解析函数 ----------
function parseGeneric(url, headers = {}) {
    return fetchRemoteScript(url, headers, 10000)
        .then(remoteScript => executeScript(remoteScript));
}

function parseHome(api, key, ext, jar) {
    const url = buildJarRequestUrl(api, ext, jar, { action: 'home', key });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

function parseList(api, key, ext, jar, tid, page = 1, filters = {}) {
    const url = buildJarRequestUrl(api, ext, jar, {
        action: 'list',
        key, tid, page,
        filters: JSON.stringify(filters)
    });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

function parseDetail(api, key, ext, jar, vodId) {
    const url = buildJarRequestUrl(api, ext, jar, { action: 'detail', key, ids: vodId });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

function parseSearch(api, key, ext, jar, wd) {
    const url = buildJarRequestUrl(api, ext, jar, { action: 'search', key, wd });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
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
