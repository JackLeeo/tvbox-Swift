const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');

const PORT = 3000;
const jarCache = new Map();

// ========== 内置 cat.js 模拟环境 ==========
function createSpiderSandbox() {
    const req = (url, options = {}) => {
        return new Promise((resolve, reject) => {
            const headers = options.headers || {};
            const method = (options.method || 'get').toUpperCase();
            const cleanUrl = url.replace(/[\n\r\t]/g, '').trim();
            const parsed = URL.parse(cleanUrl);
            const client = parsed.protocol === 'https:' ? https : http;
            const reqOptions = { method, headers };
            const request = client.request(cleanUrl, reqOptions, (res) => {
                let data = '';
                res.on('data', chunk => data += chunk);
                res.on('end', () => resolve({ content: data, statusCode: res.statusCode }));
            });
            request.on('error', reject);
            if (options.data) request.write(options.data);
            request.end();
        });
    };

    const load = (html) => {
        const $ = (selector) => ({
            text: () => '',
            attr: () => '',
            find: () => $(''),
            map: (fn) => [],
        });
        return $;
    };

    const _ = {
        map: (arr, fn) => (arr || []).map(fn),
        each: (arr, fn) => (arr || []).forEach(fn),
        filter: (arr, fn) => (arr || []).filter(fn),
    };

    const Crypto = {
        MD5: (str) => require('crypto').createHash('md5').update(str).digest('hex'),
    };

    return { req, load, _, Crypto };
}

// ========== 加载本地 Spider 脚本 ==========
function loadLocalSpider(apiName) {
    // 移除 csp_ 前缀
    const scriptName = apiName.replace(/^csp_/, '') + '.js';
    const localPath = path.join(__dirname, 'open', scriptName);
    if (!fs.existsSync(localPath)) {
        return null;
    }
    const scriptContent = fs.readFileSync(localPath, 'utf8');

    const sandbox = createSpiderSandbox();
    sandbox.console = { log: () => {}, error: () => {} };
    sandbox.setTimeout = setTimeout;
    sandbox.clearTimeout = clearTimeout;
    sandbox.Buffer = Buffer;
    sandbox.__dirname = path.join(__dirname, 'open');

    // 支持 require 相对路径（如 ./lib/cat.js）
    sandbox.require = (modulePath) => {
        const resolvedPath = path.resolve(sandbox.__dirname, modulePath);
        if (!fs.existsSync(resolvedPath)) {
            throw new Error(`Cannot find module '${modulePath}'`);
        }
        const moduleContent = fs.readFileSync(resolvedPath, 'utf8');
        const moduleSandbox = createSpiderSandbox();
        moduleSandbox.exports = {};
        moduleSandbox.module = { exports: moduleSandbox.exports };
        vm.createContext(moduleSandbox);
        vm.runInContext(moduleContent, moduleSandbox, { filename: resolvedPath, timeout: 10000 });
        return moduleSandbox.module.exports;
    };

    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, { filename: localPath, timeout: 15000 });

    if (typeof sandbox.__jsEvalReturn === 'function') {
        return sandbox.__jsEvalReturn();
    }
    return sandbox;
}

// ========== HTTP 服务器 ==========
const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200);
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
                        .catch(err => sendError(res, `[Generic] ${err.message}`));
                    return;
                }

                if (api && api.startsWith('csp_')) {
                    handleSpiderRequest(api, spider, action, key, ext, tid, page, vod_id, wd)
                        .then(data => sendSuccess(res, data))
                        .catch(err => sendError(res, `[Spider] ${err.message}`));
                    return;
                }

                sendError(res, '无效的请求参数');
            } catch (err) {
                sendError(res, `[Parse] ${err.message}`);
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

// ========== Spider 请求处理 ==========
async function handleSpiderRequest(api, spider, action, key, ext, tid, page, vodId, keyword) {
    // 优先尝试加载本地 Spider
    let spiderModule = loadLocalSpider(api);
    if (spiderModule) {
        console.log(`[Node] 使用本地 Spider: ${api}`);
    } else if (spider) {
        // 回退到网络下载
        let cleanSpider = spider.split(';')[0].replace(/[\n\r\t]/g, '').trim();
        spiderModule = await downloadAndLoadSpider(cleanSpider);
    } else {
        throw new Error(`未找到本地 Spider (${api}) 且未提供 spider 地址`);
    }

    // 初始化
    if (spiderModule.init) {
        const cfg = { skey: key, stype: 3, ext: ext };
        await spiderModule.init(cfg);
    }

    let result;
    switch (action) {
        case 'home':
            if (!spiderModule.home) throw new Error('Spider未实现home函数');
            result = await spiderModule.home();
            break;
        case 'list':
            if (!spiderModule.category) throw new Error('Spider未实现category函数');
            result = await spiderModule.category(tid, page, {}, ext);
            break;
        case 'detail':
            if (!spiderModule.detail) throw new Error('Spider未实现detail函数');
            result = await spiderModule.detail(vodId);
            break;
        case 'search':
            if (!spiderModule.search) throw new Error('Spider未实现search函数');
            result = await spiderModule.search(keyword, false, page);
            break;
        default:
            throw new Error(`未知的action: ${action}`);
    }

    if (typeof result === 'string') {
        try { result = JSON.parse(result); } catch (e) {}
    }
    return normalizeResponse(result, action);
}

async function downloadAndLoadSpider(spiderUrl) {
    if (!spiderUrl) throw new Error('缺少spider地址');
    let scriptContent = jarCache.get(spiderUrl);
    if (!scriptContent) {
        const buffer = await fetchRemoteBuffer(spiderUrl, getDefaultHeaders(), 20000);
        if (buffer[0] === 0x50 && buffer[1] === 0x4B) {
            const files = unzipBuffer(buffer);
            const jsFile = files.find(f => f.name.endsWith('.js')) || files[0];
            scriptContent = jsFile.data.toString('utf8');
        } else {
            scriptContent = buffer.toString('utf8');
        }
        jarCache.set(spiderUrl, scriptContent);
    }

    const sandbox = createSpiderSandbox();
    sandbox.console = { log: () => {}, error: () => {} };
    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, { filename: 'spider.js', timeout: 15000 });

    if (typeof sandbox.__jsEvalReturn === 'function') {
        return sandbox.__jsEvalReturn();
    }
    return sandbox;
}

function unzipBuffer(buffer) {
    // 与之前相同的ZIP解压逻辑
    if (buffer.length < 22) throw new Error('文件太小');
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    let eocdOffset = -1;
    for (let i = buffer.length - 22; i >= 0; i--) {
        if (view.getUint32(i, true) === 0x06054b50) { eocdOffset = i; break; }
    }
    if (eocdOffset === -1) throw new Error('找不到EOCD');
    const cdOffset = view.getUint32(eocdOffset + 16, true);
    const totalEntries = view.getUint16(eocdOffset + 10, true);
    const files = [];
    let offset = cdOffset;
    for (let i = 0; i < totalEntries; i++) {
        if (view.getUint32(offset, true) !== 0x02014b50) break;
        const compressionMethod = view.getUint16(offset + 10, true);
        const compressedSize = view.getUint32(offset + 20, true);
        const fileNameLength = view.getUint16(offset + 28, true);
        const extraFieldLength = view.getUint16(offset + 30, true);
        const fileCommentLength = view.getUint16(offset + 32, true);
        const localHeaderOffset = view.getUint32(offset + 42, true);
        const fileName = buffer.toString('utf8', offset + 46, offset + 46 + fileNameLength);
        let localOffset = localHeaderOffset;
        if (view.getUint32(localOffset, true) !== 0x04034b50) {
            offset += 46 + fileNameLength + extraFieldLength + fileCommentLength;
            continue;
        }
        const localFileNameLength = view.getUint16(localOffset + 26, true);
        const localExtraFieldLength = view.getUint16(localOffset + 28, true);
        const dataOffset = localOffset + 30 + localFileNameLength + localExtraFieldLength;
        let fileData = buffer.slice(dataOffset, dataOffset + compressedSize);
        if (compressionMethod === 8) {
            try { fileData = zlib.inflateRawSync(fileData); }
            catch (e) { fileData = zlib.inflateSync(fileData); }
        }
        files.push({ name: fileName, data: fileData });
        offset += 46 + fileNameLength + extraFieldLength + fileCommentLength;
    }
    return files;
}

function normalizeResponse(data, action) {
    if (action === 'home') {
        if (data.class || data.list) return data;
        if (Array.isArray(data)) return { class: [], list: data };
    } else if (action === 'list' || action === 'search') {
        if (data.list) return data;
        if (Array.isArray(data)) return { list: data };
    } else if (action === 'detail') {
        if (data.list) return data;
        if (data.vod_id || data.vod_name) return { list: [data] };
    }
    return data;
}

function parseGeneric(url, headers = {}) {
    return fetchRemoteBuffer(url, headers, 10000).then(buf => {
        const script = buf.toString('utf8');
        const sandbox = { result: {}, setResult: (d) => { sandbox.result = d; } };
        vm.createContext(sandbox);
        vm.runInContext(script, sandbox, { filename: 'generic.js', timeout: 10000 });
        return sandbox.result;
    });
}

function fetchRemoteBuffer(url, headers, timeout) {
    return new Promise((resolve, reject) => {
        const cleanUrl = url.replace(/[\n\r\t]/g, '').trim();
        const parsed = URL.parse(cleanUrl);
        const client = parsed.protocol === 'https:' ? https : http;
        client.get(cleanUrl, { headers }, (res) => {
            const chunks = [];
            res.on('data', chunk => chunks.push(chunk));
            res.on('end', () => resolve(Buffer.concat(chunks)));
        }).on('error', reject);
    });
}

function getDefaultHeaders() {
    return {
        'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1',
    };
}
