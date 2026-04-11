const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');
const zlib = require('zlib');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');

const PORT = 3000;
const jarCache = new Map();

// ========== 可写目录 ==========
const NODE_PATH = process.env.NODE_PATH || path.join(__dirname, '..', 'Documents');
if (!fs.existsSync(NODE_PATH)) fs.mkdirSync(NODE_PATH, { recursive: true });

// ========== 内置 cat.js 完整模拟 ==========
const _ = {
    get: (obj, path, defaultValue) => {
        const keys = path.split('.');
        let result = obj;
        for (const key of keys) {
            if (result == null) return defaultValue;
            result = result[key];
        }
        return result !== undefined ? result : defaultValue;
    },
    has: (obj, key) => Object.prototype.hasOwnProperty.call(obj, key),
    map: (arr, fn) => (arr || []).map(fn),
    each: (arr, fn) => (arr || []).forEach(fn),
    filter: (arr, fn) => (arr || []).filter(fn),
    random: (min, max) => Math.floor(Math.random() * (max - min + 1)) + min,
};

class Uri {
    constructor(url) {
        this.url = url;
    }
    path() {
        const parsed = URL.parse(this.url);
        return parsed.pathname || '';
    }
}

function md5(text) {
    return crypto.createHash('md5').update(text, 'utf8').digest('hex');
}

function base64EncodeBuf(buff, urlsafe = false) {
    return buff.toString(urlsafe ? 'base64url' : 'base64');
}

function base64Encode(text, urlsafe = false) {
    return Buffer.from(text, 'utf8').toString(urlsafe ? 'base64url' : 'base64');
}

function base64DecodeBuf(text) {
    return Buffer.from(text, 'base64');
}

function base64Decode(text) {
    return base64DecodeBuf(text).toString('utf8');
}

function aes(mode, encrypt, input, inBase64, key, iv, outBase64) {
    try {
        let algo = mode.includes('CBC') ? (key.length === 16 ? 'aes-128-cbc' : 'aes-256-cbc') :
                   (key.length === 16 ? 'aes-128-ecb' : 'aes-256-ecb');
        const inBuf = inBase64 ? base64DecodeBuf(input) : Buffer.from(input, 'utf8');
        let keyBuf = Buffer.from(key);
        if (keyBuf.length < 16) keyBuf = Buffer.concat([keyBuf], 16);
        let ivBuf = iv ? Buffer.from(iv) : Buffer.alloc(0);
        const cipher = encrypt ? crypto.createCipheriv(algo, keyBuf, ivBuf) : crypto.createDecipheriv(algo, keyBuf, ivBuf);
        const outBuf = Buffer.concat([cipher.update(inBuf), cipher.final()]);
        return outBase64 ? base64EncodeBuf(outBuf) : outBuf.toString('utf8');
    } catch (e) {
        return '';
    }
}

function des(mode, encrypt, input, inBase64, key, iv, outBase64) {
    try {
        let algo = mode.includes('CBC') ? (key.length === 24 ? 'des-ede3-cbc' : 'des-ede-cbc') : 'des-ede3-ecb';
        const inBuf = inBase64 ? base64DecodeBuf(input) : Buffer.from(input, 'utf8');
        let keyBuf = Buffer.from(key);
        let ivBuf = iv ? Buffer.from(iv) : Buffer.alloc(0);
        const cipher = encrypt ? crypto.createCipheriv(algo, keyBuf, ivBuf) : crypto.createDecipheriv(algo, keyBuf, ivBuf);
        const outBuf = Buffer.concat([cipher.update(inBuf), cipher.final()]);
        return outBase64 ? base64EncodeBuf(outBuf) : outBuf.toString('utf8');
    } catch (e) {
        return '';
    }
}

function rsa(mode, pub, encrypt, input, inBase64, key, outBase64) {
    return '';
}

function randStr(len, withNum = true) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const max = withNum ? chars.length - 1 : chars.length - 11;
    let result = '';
    for (let i = 0; i < len; i++) {
        result += chars[_.random(0, max)];
    }
    return result;
}

// ========== 模拟 axios ==========
const axios = {
    async request(config) {
        const method = (config.method || 'get').toUpperCase();
        const url = config.url;
        const headers = config.headers || {};
        const data = config.data;
        const timeout = config.timeout || 15000;
        const responseType = config.responseType;

        return new Promise((resolve, reject) => {
            const parsed = URL.parse(url);
            const client = parsed.protocol === 'https:' ? https : http;
            const req = client.request(url, { method, headers }, (res) => {
                const chunks = [];
                res.on('data', chunk => chunks.push(chunk));
                res.on('end', () => {
                    const buffer = Buffer.concat(chunks);
                    let data;
                    if (responseType === 'arraybuffer') {
                        data = buffer;
                    } else {
                        data = buffer.toString('utf8');
                    }
                    resolve({
                        status: res.statusCode,
                        headers: res.headers,
                        data,
                    });
                });
            });
            req.on('error', reject);
            if (data) {
                if (typeof data === 'object' && !Buffer.isBuffer(data)) {
                    req.write(JSON.stringify(data));
                } else {
                    req.write(data);
                }
            }
            req.end();
        });
    },
    get(url, config) { return this.request({ ...config, method: 'get', url }); },
    post(url, data, config) { return this.request({ ...config, method: 'post', url, data }); },
};

// ========== 模拟 qs ==========
const qs = {
    stringify(obj, options = {}) {
        const encode = options.encode !== false;
        const parts = [];
        for (const key in obj) {
            if (Object.prototype.hasOwnProperty.call(obj, key)) {
                const value = obj[key];
                const encodedKey = encode ? encodeURIComponent(key) : key;
                const encodedValue = encode ? encodeURIComponent(value) : value;
                parts.push(`${encodedKey}=${encodedValue}`);
            }
        }
        return parts.join('&');
    },
    parse(str) {
        const result = {};
        const parts = str.split('&');
        for (const part of parts) {
            const [key, value] = part.split('=');
            result[decodeURIComponent(key)] = decodeURIComponent(value || '');
        }
        return result;
    },
};

// ========== 请求函数（Spider 中使用的 req） ==========
async function request(url, opt = {}) {
    const method = (opt.method || 'get').toUpperCase();
    const headers = opt.headers || {};
    const data = opt.data;
    const timeout = opt.timeout || 15000;
    const returnBuffer = opt.buffer || 0;
    const postType = opt.postType;

    // 处理 form 类型
    if (postType === 'form' && data) {
        headers['Content-Type'] = 'application/x-www-form-urlencoded';
    }

    try {
        const resp = await axios.request({ url, method, headers, data, timeout, responseType: returnBuffer ? 'arraybuffer' : 'text' });
        let content = resp.data;
        if (returnBuffer === 1) {
            return { code: resp.status, headers: resp.headers, content };
        } else if (returnBuffer === 2) {
            return { code: resp.status, headers: resp.headers, content: Buffer.from(content).toString('base64') };
        }
        return { code: resp.status, headers: resp.headers, content: typeof content === 'string' ? content : JSON.stringify(content) };
    } catch (e) {
        return { code: 0, headers: {}, content: '' };
    }
}

// ========== 本地存储 ==========
function localGet(storage, key) {
    const filePath = path.join(NODE_PATH, `js_${storage}.json`);
    if (!fs.existsSync(filePath)) return '';
    const data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    return _.get(data, key, '');
}

function localSet(storage, key, value) {
    const filePath = path.join(NODE_PATH, `js_${storage}.json`);
    let data = {};
    if (fs.existsSync(filePath)) {
        data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    }
    data[key] = value;
    fs.writeFileSync(filePath, JSON.stringify(data));
}

// ========== 创建 Spider 沙箱 ==========
function createSpiderSandbox(spiderDir) {
    const sandbox = {
        axios,
        qs,
        crypto,
        https,
        fs,
        Uri,
        _,
        request,
        md5,
        base64Encode,
        base64Decode,
        aes,
        des,
        rsa,
        randStr,
        localGet,
        localSet,
        console: { log: () => {}, error: () => {} },
        setTimeout,
        clearTimeout,
        Buffer,
        __dirname: spiderDir,
    };

    sandbox.require = (modulePath) => {
        // 内置模块优先
        if (modulePath === 'axios') return axios;
        if (modulePath === 'qs') return qs;
        if (modulePath === 'crypto') return crypto;
        if (modulePath === 'fs') return fs;
        if (modulePath === 'https') return https;
        if (modulePath === 'path') return path;
        if (modulePath === 'url') return URL;
        if (modulePath === 'zlib') return zlib;

        // 处理相对路径
        if (modulePath.startsWith('.')) {
            const resolved = path.resolve(sandbox.__dirname, modulePath);
            const ext = path.extname(resolved) ? resolved : resolved + '.js';
            if (!fs.existsSync(ext)) {
                throw new Error(`Cannot find module '${modulePath}'`);
            }
            const code = fs.readFileSync(ext, 'utf8');
            const mod = { exports: {} };
            const modSandbox = {
                ...sandbox,
                module: mod,
                exports: mod.exports,
                require: (p) => {
                    if (p.startsWith('.')) {
                        return sandbox.require(path.resolve(path.dirname(ext), p));
                    }
                    return sandbox.require(p);
                },
            };
            vm.createContext(modSandbox);
            vm.runInContext(code, modSandbox, { filename: ext });
            return mod.exports;
        }
        throw new Error(`Cannot find module '${modulePath}'`);
    };

    return sandbox;
}

// ========== 查找本地 Spider 脚本 ==========
function findSpiderScript(apiName) {
    const baseDir = path.join(__dirname, 'open');
    const scriptName = apiName.replace(/^csp_/, '') + '.js';

    function searchDir(dir) {
        if (!fs.existsSync(dir)) return null;
        const items = fs.readdirSync(dir);
        for (const item of items) {
            const fullPath = path.join(dir, item);
            const stat = fs.statSync(fullPath);
            if (stat.isDirectory()) {
                const found = searchDir(fullPath);
                if (found) return found;
            } else if (item === scriptName) {
                return { path: fullPath, dir: path.dirname(fullPath) };
            }
        }
        return null;
    }

    return searchDir(baseDir);
}

// ========== 加载本地 Spider ==========
function loadLocalSpider(apiName) {
    const found = findSpiderScript(apiName);
    if (!found) return null;

    const scriptContent = fs.readFileSync(found.path, 'utf8');
    const sandbox = createSpiderSandbox(found.dir);

    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, { filename: found.path });

    if (typeof sandbox.__jsEvalReturn === 'function') {
        return sandbox.__jsEvalReturn();
    }
    return sandbox;
}

// ========== HTTP 服务器 ==========
const server = http.createServer(async (req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200);
        res.end('OK');
        return;
    }
    if (req.method === 'POST' && req.url === '/parse') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', async () => {
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
                    const result = await handleSpiderRequest(api, spider, action, key, ext, tid, page, vod_id, wd);
                    sendSuccess(res, result);
                } else {
                    sendError(res, '无效的请求参数');
                }
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
    res.end(JSON.stringify({ success: true, data }));
}

function sendError(res, error) {
    res.writeHead(200, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify({ success: false, error }));
}

async function handleSpiderRequest(api, spider, action, key, ext, tid, page, vodId, keyword) {
    let spiderModule = loadLocalSpider(api);
    if (!spiderModule) {
        throw new Error(`未找到本地 Spider: ${api}`);
    }

    if (spiderModule.init) {
        await spiderModule.init({ skey: key, stype: 3, ext });
    }

    let result;
    switch (action) {
        case 'home':
            result = await spiderModule.home();
            break;
        case 'list':
            result = await spiderModule.category(tid, page, {}, ext);
            break;
        case 'detail':
            result = await spiderModule.detail(vodId);
            break;
        case 'search':
            result = await spiderModule.search(keyword, false, page);
            break;
        default:
            throw new Error(`未知 action: ${action}`);
    }

    if (typeof result === 'string') {
        try { result = JSON.parse(result); } catch (e) {}
    }
    return normalizeResponse(result, action);
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
        if (data.vod_id) return { list: [data] };
    }
    return data;
}

async function parseGeneric(url, headers) {
    const resp = await request(url, { headers, buffer: 0 });
    const script = resp.content;
    const sandbox = { result: {}, setResult: (d) => { sandbox.result = d; } };
    vm.createContext(sandbox);
    vm.runInContext(script, sandbox, { filename: 'generic.js', timeout: 10000 });
    return sandbox.result;
}
