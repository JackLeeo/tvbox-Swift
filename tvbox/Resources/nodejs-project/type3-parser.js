const rn_bridge = require('rn-bridge');
const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

// 是否启用 HTTP 服务器（兼容旧版）
const ENABLE_HTTP_SERVER = true;
const PORT = 3000;

// 监听来自 Swift 的消息（通过 rn-bridge）
rn_bridge.channel.on('message', handleMessage);

// 可选：同时启动 HTTP 服务器（用于兼容旧版或调试）
if (ENABLE_HTTP_SERVER) {
    const server = http.createServer(httpRequestHandler);
    server.listen(PORT, () => {
        console.log(`Type3 parser HTTP server listening on port ${PORT}`);
    });
}

/**
 * 处理来自 rn-bridge 的消息
 */
function handleMessage(msg) {
    try {
        const request = JSON.parse(msg);
        const { action, api, key, ext, tid, page, filters, vod_id, wd, url, headers } = request;

        // 如果有 url 字段，则视为通用解析请求（兼容旧版）
        if (url) {
            parseGeneric(url, headers)
                .then(data => sendSuccess(data))
                .catch(err => sendError(err.message));
            return;
        }

        // 根据 action 执行不同操作
        switch (action) {
            case 'home':
                parseHome(api, key, ext)
                    .then(data => sendSuccess(data))
                    .catch(err => sendError(err.message));
                break;
            case 'list':
                parseList(api, key, ext, tid, page, filters)
                    .then(data => sendSuccess(data))
                    .catch(err => sendError(err.message));
                break;
            case 'detail':
                parseDetail(api, key, ext, vod_id)
                    .then(data => sendSuccess(data))
                    .catch(err => sendError(err.message));
                break;
            case 'search':
                parseSearch(api, key, ext, wd)
                    .then(data => sendSuccess(data))
                    .catch(err => sendError(err.message));
                break;
            default:
                sendError(`未知的 action: ${action}`);
        }
    } catch (e) {
        sendError(e.message);
    }
}

function sendSuccess(data) {
    rn_bridge.channel.send(JSON.stringify({ success: true, data }));
}

function sendError(error) {
    rn_bridge.channel.send(JSON.stringify({ success: false, error }));
}

/**
 * HTTP 请求处理器（兼容旧版 /parse 接口）
 */
function httpRequestHandler(req, res) {
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

            parseGeneric(url, headers)
                .then(data => {
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: true, data }));
                })
                .catch(error => {
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: false, error: error.message }));
                });
        } catch (error) {
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({ success: false, error: error.message }));
        }
    });
}

/**
 * 通用解析：直接执行远程脚本，返回脚本中通过 setResult 设置的结果
 */
function parseGeneric(url, headers = {}) {
    return fetchRemoteScript(url, headers, 10000)
        .then(remoteScript => executeScript(remoteScript));
}

/**
 * 首页解析：需要返回 { class: [...], list: [...] } 格式
 * 实际调用 jar 脚本，脚本应通过 setResult({ class: [...], list: [...] }) 返回数据
 */
function parseHome(api, key, ext) {
    // 构建请求 jar 脚本的 URL 和参数
    const url = buildJarRequestUrl(api, {
        action: 'home',
        key: key,
        ext: ext
    });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

/**
 * 分类列表解析：需要返回 { list: [...] } 格式
 */
function parseList(api, key, ext, tid, page = 1, filters = {}) {
    const url = buildJarRequestUrl(api, {
        action: 'list',
        key: key,
        ext: ext,
        tid: tid,
        page: page,
        filters: JSON.stringify(filters)
    });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

/**
 * 详情解析：需要返回 { list: [{ vod_id, vod_name, vod_play_from, vod_play_url, ... }] } 格式
 */
function parseDetail(api, key, ext, vodId) {
    const url = buildJarRequestUrl(api, {
        action: 'detail',
        key: key,
        ext: ext,
        ids: vodId
    });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

/**
 * 搜索解析：需要返回 { list: [...] } 格式
 */
function parseSearch(api, key, ext, wd) {
    const url = buildJarRequestUrl(api, {
        action: 'search',
        key: key,
        ext: ext,
        wd: wd
    });
    return fetchRemoteScript(url, getDefaultHeaders(), 15000)
        .then(remoteScript => executeScript(remoteScript));
}

/**
 * 构建调用 jar 脚本的 URL（根据 action 和参数拼接）
 * 不同 jar 源的调用方式可能不同，这里提供一个通用模板
 */
function buildJarRequestUrl(baseApi, params) {
    // 如果 baseApi 已经是完整的 jar 脚本 URL，则直接返回
    if (baseApi.startsWith('http://') || baseApi.startsWith('https://')) {
        const urlObj = new URL(baseApi);
        // 将参数添加到 query string
        Object.entries(params).forEach(([k, v]) => {
            if (v !== undefined && v !== null) {
                urlObj.searchParams.set(k, String(v));
            }
        });
        return urlObj.toString();
    }
    // 否则视为 jar 脚本内容，但这种情况通常不会发生，这里仅作占位
    throw new Error('无效的 jar 源 API 地址');
}

/**
 * 获取默认请求头
 */
function getDefaultHeaders() {
    return {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
        'Referer': 'https://tvbox.example.com'
    };
}

/**
 * 执行远程脚本并返回 sandbox.result
 */
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

/**
 * 带超时的远程请求
 */
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
