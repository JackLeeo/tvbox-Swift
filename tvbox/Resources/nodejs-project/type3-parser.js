const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');

const PORT = 3000;

// 存储已下载的 jar 脚本内容，避免重复下载
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
                const { action, api, key, ext, tid, page, vod_id, wd, url, headers } = request;

                // 如果有 url 字段，执行通用解析
                if (url) {
                    parseGeneric(url, headers)
                        .then(data => sendJson(res, { success: true, data }))
                        .catch(err => sendJson(res, { success: false, error: err.message }));
                    return;
                }

                // 处理 jar 源请求（api 以 csp_ 开头）
                if (api && api.startsWith('csp_')) {
                    handleJarRequest(api, action, key, ext, tid, page, vod_id, wd)
                        .then(data => sendJson(res, { success: true, data }))
                        .catch(err => sendJson(res, { success: false, error: err.message }));
                    return;
                }

                // 其他情况：默认作为普通 HTTP API 处理
                sendJson(res, { success: false, error: '不支持的 API 类型' });

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

// ---------- 处理 jar 源请求 ----------
async function handleJarRequest(api, action, key, ext, tid, page, vodId, keyword) {
    // 1. 下载 jar 脚本（spider 地址来自全局配置，这里我们通过请求 Swift 端传递的完整配置来获取，但由于 Swift 端未传，我们使用一个内置的备选方案：从已缓存的配置中读取）
    // 为了简化，我们假设 jar 脚本地址可以通过 api 名称映射到已知地址，但最佳方案是由 Swift 端在请求中传递 spider 地址。
    // 我们修改 Swift 端来传递 spider，但这里先实现一个基于 api 名称的本地映射（临时方案，后续可优化）。

    // 临时映射表（您可以根据需要扩展）
    const spiderMap = {
        'csp_NewZhiZhenGuard': 'https://aisearch.cdn.bcebos.com/fileManager/pzB7vSo_ZKMdkLpEH2KJFw/17757605409407s1LX1.txt',
        'csp_NewDouBanGuard': 'https://aisearch.cdn.bcebos.com/fileManager/40aicoLgDtklAyS8-ZZBrA/1767300502404G_ouRK.txt',
        // 可继续添加其他 csp_xxx 对应的 spider 地址
    };

    const spiderUrl = spiderMap[api];
    if (!spiderUrl) {
        throw new Error(`未知的 jar 标识符: ${api}`);
    }

    // 2. 下载 jar 脚本（如果未缓存）
    let scriptContent = jarCache.get(spiderUrl);
    if (!scriptContent) {
        console.log(`[Node] 下载 jar 脚本: ${spiderUrl}`);
        scriptContent = await fetchRemoteScript(spiderUrl, getDefaultHeaders(), 15000);
        jarCache.set(spiderUrl, scriptContent);
    }

    // 3. 在沙箱中执行 jar 脚本，并调用对应方法
    return executeJarScript(scriptContent, action, key, ext, tid, page, vodId, keyword);
}

function executeJarScript(scriptContent, action, key, ext, tid, page, vodId, keyword) {
    const sandbox = {
        result: null,
        // jar 脚本通常会定义一个全局对象或函数，这里模拟 TVBox 的 JavaScript 环境
        console: console,
        // 提供一些必要的全局函数
        log: (msg) => console.log(`[Jar] ${msg}`),
        // 用于接收结果的回调
        setResult: (data) => { sandbox.result = data; },
        // 模拟一些常用对象
        $: { ajax: null }, // 占位
        // 暴露给 jar 脚本的请求参数（某些 jar 脚本通过全局变量获取参数）
        ACTION: action,
        KEY: key,
        EXT: ext,
        TID: tid,
        PAGE: page,
        VOD_ID: vodId,
        KEYWORD: keyword,
    };

    // 创建沙箱上下文
    vm.createContext(sandbox);

    // 执行 jar 脚本
    vm.runInContext(scriptContent, sandbox, {
        filename: 'jar-script.js',
        timeout: 15000
    });

    // 尝试获取结果（不同 jar 脚本的返回方式不同，可能需要调用特定函数）
    // 常见模式：脚本定义了一个全局对象（如 `rule`），然后通过调用 `rule.home()` 等方法获取数据
    // 这里我们实现一个通用的探测逻辑

    let data = sandbox.result;
    if (!data) {
        // 尝试调用可能存在的函数
        try {
            if (action === 'home') {
                if (typeof sandbox.home === 'function') {
                    data = sandbox.home();
                } else if (sandbox.rule && typeof sandbox.rule.home === 'function') {
                    data = sandbox.rule.home();
                }
            } else if (action === 'list') {
                if (typeof sandbox.list === 'function') {
                    data = sandbox.list(tid, page);
                } else if (sandbox.rule && typeof sandbox.rule.list === 'function') {
                    data = sandbox.rule.list(tid, page);
                }
            } else if (action === 'detail') {
                if (typeof sandbox.detail === 'function') {
                    data = sandbox.detail(vodId);
                } else if (sandbox.rule && typeof sandbox.rule.detail === 'function') {
                    data = sandbox.rule.detail(vodId);
                }
            } else if (action === 'search') {
                if (typeof sandbox.search === 'function') {
                    data = sandbox.search(keyword);
                } else if (sandbox.rule && typeof sandbox.rule.search === 'function') {
                    data = sandbox.rule.search(keyword);
                }
            }
        } catch (e) {
            console.error('[Jar] 调用函数失败:', e.message);
        }
    }

    // 如果依然没有数据，返回错误
    if (!data) {
        throw new Error('jar 脚本未返回有效数据');
    }

    // 确保返回的数据格式符合预期（与标准接口一致）
    return normalizeJarResponse(data, action);
}

function normalizeJarResponse(data, action) {
    // 根据不同 action 调整数据结构
    if (action === 'home') {
        // 期望格式: { class: [...], list: [...] }
        if (Array.isArray(data.class) || data.list) {
            return data;
        }
        // 如果只返回了视频列表，则构造默认分类
        if (Array.isArray(data)) {
            return { class: [], list: data };
        }
    } else if (action === 'list' || action === 'search') {
        // 期望格式: { list: [...] }
        if (Array.isArray(data)) {
            return { list: data };
        }
        if (data.list) {
            return data;
        }
    } else if (action === 'detail') {
        // 期望格式: { list: [ {...} ] }
        if (!Array.isArray(data) && data.vod_id) {
            return { list: [data] };
        }
        if (data.list) {
            return data;
        }
    }
    return data;
}

// ---------- 以下为原有通用解析函数 ----------
function parseGeneric(url, headers = {}) {
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
