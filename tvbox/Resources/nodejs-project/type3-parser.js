const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

const PORT = 3000;
const jarCache = new Map();

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
                const { action, api, key, ext, tid, page, vod_id, wd, url, headers, spider } = request;

                if (url) {
                    parseGeneric(url, headers)
                        .then(data => sendSuccess(res, data))
                        .catch(err => sendError(res, err.message));
                    return;
                }

                if (api && api.startsWith('csp_') && spider) {
                    let cleanSpider = spider.split(';')[0];
                    cleanSpider = cleanSpider.replace(/[\n\r\t]/g, '').trim();
                    
                    // 直接在这里尝试处理，并将任何错误以详细消息返回
                    handleJarRequest(cleanSpider, action, key, ext, tid, page, vod_id, wd)
                        .then(data => sendSuccess(res, data))
                        .catch(err => {
                            sendError(res, err.message);
                        });
                    return;
                }

                sendError(res, '无效的请求参数：api不是csp_开头或缺少spider');
            } catch (err) {
                sendError(res, `[ParseError] ${err.message}`);
            }
        });
        return;
    }

    res.writeHead(404);
    res.end();
});

server.listen(PORT, '127.0.0.1', () => {});

function sendSuccess(res, data) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, data: data }));
}

function sendError(res, error) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: false, error: error }));
}

async function handleJarRequest(spiderUrl, action, key, ext, tid, page, vodId, keyword) {
    if (!spiderUrl) throw new Error('[JarError] 缺少spider地址');
    
    let scriptContent = jarCache.get(spiderUrl);
    if (!scriptContent) {
        try {
            scriptContent = await fetchRemoteScript(spiderUrl, getDefaultHeaders(), 15000);
            jarCache.set(spiderUrl, scriptContent);
        } catch (e) {
            throw new Error(`[DownloadError] ${e.message}`);
        }
    }
    
    try {
        return executeJarScript(scriptContent, action, key, ext, tid, page, vodId, keyword);
    } catch (e) {
        throw new Error(`[ExecError] ${e.message}`);
    }
}

function executeJarScript(scriptContent, action, key, ext, tid, page, vodId, keyword) {
    const sandbox = {
        result: null,
        console: { log: () => {}, error: () => {} },
        setResult: (data) => { sandbox.result = data; },
        ACTION: action,
        KEY: key,
        EXT: ext,
        TID: tid,
        PAGE: page,
        VOD_ID: vodId,
        KEYWORD: keyword,
    };

    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, { filename: 'jar-script.js', timeout: 15000 });

    let data = sandbox.result;
    if (!data) {
        try {
            if (action === 'home') {
                if (typeof sandbox.home === 'function') data = sandbox.home();
                else if (sandbox.rule && typeof sandbox.rule.home === 'function') data = sandbox.rule.home();
            } else if (action === 'list') {
                if (typeof sandbox.list === 'function') data = sandbox.list(tid, page);
                else if (sandbox.rule && typeof sandbox.rule.list === 'function') data = sandbox.rule.list(tid, page);
            } else if (action === 'detail') {
                if (typeof sandbox.detail === 'function') data = sandbox.detail(vodId);
                else if (sandbox.rule && typeof sandbox.rule.detail === 'function') data = sandbox.rule.detail(vodId);
            } else if (action === 'search') {
                if (typeof sandbox.search === 'function') data = sandbox.search(keyword);
                else if (sandbox.rule && typeof sandbox.rule.search === 'function') data = sandbox.rule.search(keyword);
            }
        } catch (e) {
            throw new Error(`[JarCallError] ${e.message}`);
        }
    }

    if (!data) throw new Error('[JarNoData] jar脚本未返回有效数据');
    return normalizeJarResponse(data, action);
}

function normalizeJarResponse(data, action) {
    if (action === 'home') {
        if (Array.isArray(data.class) || data.list) return data;
        if (Array.isArray(data)) return { class: [], list: data };
    } else if (action === 'list' || action === 'search') {
        if (Array.isArray(data)) return { list: data };
        if (data.list) return data;
    } else if (action === 'detail') {
        if (!Array.isArray(data) && data.vod_id) return { list: [data] };
        if (data.list) return data;
    }
    return data;
}

function parseGeneric(url, headers = {}) {
    return fetchRemoteScript(url, headers, 10000).then(script => executeScript(script));
}

function executeScript(scriptContent) {
    const sandbox = { result: {}, setResult: (data) => { sandbox.result = data; }, console: { log: () => {} } };
    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, { filename: 'type3-remote.js', timeout: 10000 });
    return sandbox.result;
}

function fetchRemoteScript(url, headers, timeout) {
    return new Promise((resolve, reject) => {
        const cleanUrl = url.replace(/[\n\r\t]/g, '').trim();
        
        // 直接将即将请求的 URL 包含在错误信息中
        let parsedUrl;
        try {
            parsedUrl = URL.parse(cleanUrl);
        } catch (e) {
            reject(new Error(`[URLParseError] 无法解析URL: "${cleanUrl}" | 原始错误: ${e.message}`));
            return;
        }

        const client = parsedUrl.protocol === 'https:' ? https : http;
        const req = client.get(cleanUrl, { headers }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(data));
        });
        req.on('error', err => reject(new Error(`[NetworkError] URL: ${cleanUrl} | ${err.message}`)));
        req.setTimeout(timeout, () => { req.destroy(); reject(new Error(`[TimeoutError] URL: ${cleanUrl}`)); });
        req.end();
    });
}

function getDefaultHeaders() {
    return {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
        'Referer': 'https://tvbox.example.com'
    };
}
