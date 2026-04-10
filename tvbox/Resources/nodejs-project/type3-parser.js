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
                console.log('[Node] 完整请求体:', body);
                const { action, api, key, ext, tid, page, vod_id, wd, url, headers, spider } = request;

                // 通用解析
                if (url) {
                    console.log('[Node] 进入通用解析分支, url:', url);
                    parseGeneric(url, headers)
                        .then(data => sendSuccess(res, data))
                        .catch(err => sendError(res, err.message));
                    return;
                }

                // jar源请求
                if (api && api.startsWith('csp_') && spider) {
                    console.log('[Node] 进入 jar 解析分支, 原始 spider:', spider);
                    // 强力清洗：移除分号及之后内容，移除所有换行、回车、制表符，去除首尾空格
                    let cleanSpider = spider.split(';')[0];
                    cleanSpider = cleanSpider.replace(/[\n\r\t]/g, '').trim();
                    // 如果清洗后仍包含空格，则进行 URL 编码
                    if (cleanSpider.includes(' ')) {
                        cleanSpider = encodeURI(cleanSpider);
                    }
                    console.log('[Node] 清洗后 spider:', cleanSpider);
                    handleJarRequest(cleanSpider, action, key, ext, tid, page, vod_id, wd)
                        .then(data => sendSuccess(res, data))
                        .catch(err => sendError(res, err.message));
                    return;
                }

                console.log('[Node] 未匹配任何分支, api:', api, 'spider:', spider);
                sendError(res, '无效的请求参数');
            } catch (err) {
                console.error('[Node] 请求处理异常:', err.message);
                sendError(res, err.message);
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

function sendSuccess(res, data) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: true, data: data }));
}

function sendError(res, error) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: false, error: error }));
}

async function handleJarRequest(spiderUrl, action, key, ext, tid, page, vodId, keyword) {
    if (!spiderUrl) throw new Error('缺少spider地址');
    let scriptContent = jarCache.get(spiderUrl);
    if (!scriptContent) {
        console.log('[Node] 开始下载 jar 脚本:', spiderUrl);
        scriptContent = await fetchRemoteScript(spiderUrl, getDefaultHeaders(), 15000);
        jarCache.set(spiderUrl, scriptContent);
        console.log('[Node] jar 脚本下载完成，长度:', scriptContent.length);
    } else {
        console.log('[Node] 使用缓存的 jar 脚本');
    }
    return executeJarScript(scriptContent, action, key, ext, tid, page, vodId, keyword);
}

function executeJarScript(scriptContent, action, key, ext, tid, page, vodId, keyword) {
    const sandbox = {
        result: null,
        console: console,
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
            console.error('[Jar] 调用失败:', e.message);
        }
    }

    if (!data) throw new Error('jar脚本未返回有效数据');
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
    const sandbox = { result: {}, setResult: (data) => { sandbox.result = data; }, console };
    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, { filename: 'type3-remote.js', timeout: 10000 });
    return sandbox.result;
}

function fetchRemoteScript(url, headers, timeout) {
    return new Promise((resolve, reject) => {
        // 最终清洗：去除所有空白字符，然后编码空格
        let cleanUrl = url.replace(/[\n\r\t]/g, '').trim();
        if (cleanUrl.includes(' ')) {
            cleanUrl = encodeURI(cleanUrl);
        }
        console.log('[Node] fetchRemoteScript 最终 URL:', cleanUrl);
        
        let parsedUrl;
        try {
            parsedUrl = URL.parse(cleanUrl);
        } catch (e) {
            reject(new Error(`URL 解析失败: ${e.message}`));
            return;
        }

        const client = parsedUrl.protocol === 'https:' ? https : http;
        const req = client.get(cleanUrl, { headers }, (res) => {
            let data = '';
            res.on('data', chunk => data += chunk);
            res.on('end', () => resolve(data));
        });
        req.on('error', err => reject(new Error(`加载脚本失败: ${err.message}`)));
        req.setTimeout(timeout, () => { req.destroy(); reject(new Error('加载脚本超时')); });
        req.end();
    });
}

function getDefaultHeaders() {
    return {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
        'Referer': 'https://tvbox.example.com'
    };
}
