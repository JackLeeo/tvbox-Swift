const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

const PORT = 3000;
const jarCache = new Map();
// 设置为 true 使用测试数据，false 使用真实 jar 解析
const USE_TEST_DATA = true;

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
                console.log('[Node] 解析后的请求:', JSON.stringify(request, null, 2));

                if (USE_TEST_DATA) {
                    // 返回测试数据
                    const testData = {
                        class: [
                            { type_id: "1", type_name: "电影" },
                            { type_id: "2", type_name: "电视剧" }
                        ],
                        list: [
                            {
                                vod_id: "test001",
                                vod_name: "✅ 文件替换成功",
                                vod_pic: "",
                                vod_remarks: "测试影片"
                            }
                        ]
                    };
                    sendJson(res, { success: true, data: testData });
                    return;
                }

                const { action, api, key, ext, tid, page, vod_id, wd, url, headers, spider } = request;

                if (url) {
                    parseGeneric(url, headers)
                        .then(data => sendJson(res, { success: true, data }))
                        .catch(err => sendJson(res, { success: false, error: err.message }));
                    return;
                }

                if (api && api.startsWith('csp_') && spider) {
                    handleJarRequest(spider, action, key, ext, tid, page, vod_id, wd)
                        .then(data => sendJson(res, { success: true, data }))
                        .catch(err => sendJson(res, { success: false, error: err.message }));
                    return;
                }

                sendJson(res, { success: false, error: '无效的请求参数' });

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

async function handleJarRequest(spiderUrl, action, key, ext, tid, page, vodId, keyword) {
    if (!spiderUrl) throw new Error('缺少spider地址');
    console.log(`[Node] 下载jar脚本: ${spiderUrl}`);
    let scriptContent = jarCache.get(spiderUrl);
    if (!scriptContent) {
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
    vm.runInContext(scriptContent, sandbox, { filename: 'jar-script.js', timeout: 15000 });
    let data = sandbox.result;
    if (!data) {
        try {
            if (action === 'home') {
                if (typeof sandbox.home === 'function') data = sandbox.home();
                else if (sandbox.rule && typeof sandbox.rule.home === 'function') data = sandbox.rule.home();
            }
        } catch (e) {
            console.error('[Jar] 调用函数失败:', e.message);
        }
    }
    if (!data) throw new Error('jar脚本未返回有效数据');
    return normalizeJarResponse(data, action);
}

function normalizeJarResponse(data, action) {
    if (action === 'home') {
        if (Array.isArray(data.class) || data.list) return data;
        if (Array.isArray(data)) return { class: [], list: data };
    }
    return data;
}

function parseGeneric(url, headers = {}) {
    return fetchRemoteScript(url, headers, 10000).then(remoteScript => executeScript(remoteScript));
}

function executeScript(scriptContent) {
    const sandbox = { result: {}, setResult: (data) => { sandbox.result = data; }, console };
    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, { filename: 'type3-remote.js', timeout: 10000 });
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
