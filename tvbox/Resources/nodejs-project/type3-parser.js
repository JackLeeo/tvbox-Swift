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
                console.log('[Node] 收到请求，body长度:', body.length);
                const request = JSON.parse(body);
                console.log('[Node] 解析后的请求:', JSON.stringify(request).slice(0, 500));

                const { action, api, key, ext, tid, page, vod_id, wd, url, headers, spider } = request;

                // 通用解析（直接执行远程脚本）
                if (url) {
                    console.log('[Node] 进入通用解析分支, url:', url);
                    parseGeneric(url, headers)
                        .then(data => sendJson(res, { success: true, data }))
                        .catch(err => sendJson(res, { success: false, error: err.message }));
                    return;
                }

                // jar源请求：api以csp_开头，且有spider地址
                if (api && api.startsWith('csp_') && spider) {
                    console.log('[Node] 进入jar解析分支, spider:', spider);
                    handleJarRequest(spider, action, key, ext, tid, page, vod_id, wd)
                        .then(data => sendJson(res, { success: true, data }))
                        .catch(err => sendJson(res, { success: false, error: err.message }));
                    return;
                }

                console.log('[Node] 不支持的请求类型, api:', api, 'spider:', spider);
                sendJson(res, { success: false, error: '无效的请求参数：缺少spider或api不是jar源' });

            } catch (err) {
                console.error('[Node] 请求处理异常:', err.message);
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

// ---------- 处理jar源请求 ----------
async function handleJarRequest(spiderUrl, action, key, ext, tid, page, vodId, keyword) {
    if (!spiderUrl) {
        throw new Error('缺少spider地址');
    }

    console.log('[Node] 开始处理jar请求, spiderUrl:', spiderUrl);
    let scriptContent = jarCache.get(spiderUrl);
    if (!scriptContent) {
        console.log('[Node] 下载jar脚本:', spiderUrl);
        scriptContent = await fetchRemoteScript(spiderUrl, getDefaultHeaders(), 15000);
        jarCache.set(spiderUrl, scriptContent);
    }

    return executeJarScript(scriptContent, action, key, ext, tid, page, vodId, keyword);
}

function executeJarScript(scriptContent, action, key, ext, tid, page, vodId, keyword) {
    const sandbox = {
        result: null,
        console: console,
        log: (msg) => console.log(`[Jar] ${msg}`),
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
    vm.runInContext(scriptContent, sandbox, {
        filename: 'jar-script.js',
        timeout: 15000
    });

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
            console.error('[Jar] 调用函数失败:', e.message);
        }
    }

    if (!data) {
        throw new Error('jar脚本未返回有效数据');
    }

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

// ---------- 通用解析 ----------
function parseGeneric(url, headers = {}) {
    console.log('[Node] parseGeneric, url:', url);
    return fetchRemoteScript(url, headers, 10000)
        .then(remoteScript => executeScript(remoteScript));
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
    console.log('[Node] fetchRemoteScript, url:', url);
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

function getDefaultHeaders() {
    return {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
        'Referer': 'https://tvbox.example.com'
    };
}
