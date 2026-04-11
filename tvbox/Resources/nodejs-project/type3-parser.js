const http = require('http');
const https = require('https');
const vm = require('vm');
const URL = require('url');
const fs = require('fs');
const path = require('path');
const crypto = require('crypto');
const zlib = require('zlib');

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
    constructor(url) { this.url = url; }
    path() { const parsed = URL.parse(this.url); return parsed.pathname || ''; }
}

function md5(text) { return crypto.createHash('md5').update(text, 'utf8').digest('hex'); }
function base64EncodeBuf(buff, urlsafe = false) { return buff.toString(urlsafe ? 'base64url' : 'base64'); }
function base64Encode(text, urlsafe = false) { return Buffer.from(text, 'utf8').toString(urlsafe ? 'base64url' : 'base64'); }
function base64DecodeBuf(text) { return Buffer.from(text, 'base64'); }
function base64Decode(text) { return base64DecodeBuf(text).toString('utf8'); }

function aes(mode, encrypt, input, inBase64, key, iv, outBase64) {
    try {
        let algo = mode.includes('CBC') ? (key.length === 16 ? 'aes-128-cbc' : 'aes-256-cbc') :
                   (key.length === 16 ? 'aes-128-ecb' : 'aes-256-ecb');
        const inBuf = inBase64 ? base64DecodeBuf(input) : Buffer.from(input, 'utf8');
        let keyBuf = Buffer.from(key); if (keyBuf.length < 16) keyBuf = Buffer.concat([keyBuf], 16);
        let ivBuf = iv ? Buffer.from(iv) : Buffer.alloc(0);
        const cipher = encrypt ? crypto.createCipheriv(algo, keyBuf, ivBuf) : crypto.createDecipheriv(algo, keyBuf, ivBuf);
        const outBuf = Buffer.concat([cipher.update(inBuf), cipher.final()]);
        return outBase64 ? base64EncodeBuf(outBuf) : outBuf.toString('utf8');
    } catch (e) { return ''; }
}

function des(mode, encrypt, input, inBase64, key, iv, outBase64) {
    try {
        let algo = mode.includes('CBC') ? (key.length === 24 ? 'des-ede3-cbc' : 'des-ede-cbc') : 'des-ede3-ecb';
        const inBuf = inBase64 ? base64DecodeBuf(input) : Buffer.from(input, 'utf8');
        let keyBuf = Buffer.from(key); let ivBuf = iv ? Buffer.from(iv) : Buffer.alloc(0);
        const cipher = encrypt ? crypto.createCipheriv(algo, keyBuf, ivBuf) : crypto.createDecipheriv(algo, keyBuf, ivBuf);
        const outBuf = Buffer.concat([cipher.update(inBuf), cipher.final()]);
        return outBase64 ? base64EncodeBuf(outBuf) : outBuf.toString('utf8');
    } catch (e) { return ''; }
}

function rsa() { return ''; }

function randStr(len, withNum = true) {
    const chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789';
    const max = withNum ? chars.length - 1 : chars.length - 11;
    let result = '';
    for (let i = 0; i < len; i++) result += chars[_.random(0, max)];
    return result;
}

// ========== 模拟 axios ==========
const axios = {
    async request(config) {
        const method = (config.method || 'get').toUpperCase();
        const url = config.url, headers = config.headers || {}, data = config.data;
        const timeout = config.timeout || 15000, responseType = config.responseType;
        return new Promise((resolve, reject) => {
            const parsed = URL.parse(url);
            const client = parsed.protocol === 'https:' ? https : http;
            const req = client.request(url, { method, headers }, (res) => {
                const chunks = [];
                res.on('data', chunk => chunks.push(chunk));
                res.on('end', () => {
                    const buffer = Buffer.concat(chunks);
                    let respData;
                    if (responseType === 'arraybuffer') respData = buffer;
                    else respData = buffer.toString('utf8');
                    resolve({ status: res.statusCode, headers: res.headers, data: respData });
                });
            });
            req.on('error', reject);
            if (data) {
                if (typeof data === 'object' && !Buffer.isBuffer(data)) req.write(JSON.stringify(data));
                else req.write(data);
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
                parts.push(`${encode ? encodeURIComponent(key) : key}=${encode ? encodeURIComponent(value) : value}`);
            }
        }
        return parts.join('&');
    },
    parse(str) {
        const result = {};
        str.split('&').forEach(part => {
            const [key, value] = part.split('=');
            result[decodeURIComponent(key)] = decodeURIComponent(value || '');
        });
        return result;
    },
};

// ========== 请求函数 ==========
async function request(url, opt = {}) {
    const method = (opt.method || 'get').toUpperCase();
    const headers = opt.headers || {};
    const data = opt.data;
    const timeout = opt.timeout || 15000;
    const returnBuffer = opt.buffer || 0;
    const postType = opt.postType;
    if (postType === 'form' && data) headers['Content-Type'] = 'application/x-www-form-urlencoded';
    try {
        const resp = await axios.request({ url, method, headers, data, timeout, responseType: returnBuffer ? 'arraybuffer' : 'text' });
        let content = resp.data;
        if (returnBuffer === 1) return { code: resp.status, headers: resp.headers, content };
        if (returnBuffer === 2) return { code: resp.status, headers: resp.headers, content: Buffer.from(content).toString('base64') };
        return { code: resp.status, headers: resp.headers, content: typeof content === 'string' ? content : JSON.stringify(content) };
    } catch (e) { return { code: 0, headers: {}, content: '' }; }
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
    if (fs.existsSync(filePath)) data = JSON.parse(fs.readFileSync(filePath, 'utf8'));
    data[key] = value;
    fs.writeFileSync(filePath, JSON.stringify(data));
}

// ========== ZIP 解压 ==========
function unzipBuffer(buffer) {
    if (buffer.length < 22) throw new Error('文件太小');
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    let eocdOffset = -1;
    for (let i = buffer.length - 22; i >= 0; i--) if (view.getUint32(i, true) === 0x06054b50) { eocdOffset = i; break; }
    if (eocdOffset === -1) throw new Error('不是有效的ZIP文件');
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
        if (view.getUint32(localOffset, true) !== 0x04034b50) { offset += 46 + fileNameLength + extraFieldLength + fileCommentLength; continue; }
        const localFileNameLength = view.getUint16(localOffset + 26, true);
        const localExtraFieldLength = view.getUint16(localOffset + 28, true);
        const dataOffset = localOffset + 30 + localFileNameLength + localExtraFieldLength;
        let fileData = buffer.slice(dataOffset, dataOffset + compressedSize);
        if (compressionMethod === 8) {
            try { fileData = zlib.inflateRawSync(fileData); } catch (e) { fileData = zlib.inflateSync(fileData); }
        }
        files.push({ name: fileName, data: fileData });
        offset += 46 + fileNameLength + extraFieldLength + fileCommentLength;
    }
    return files;
}

// ========== DEX 字符串提取 ==========
function extractStringsFromDex(dexBuffer) {
    const view = new DataView(dexBuffer.buffer, dexBuffer.byteOffset, dexBuffer.byteLength);
    const stringIdsSize = view.getUint32(56, true);
    const stringIdsOff = view.getUint32(60, true);
    const strings = [];
    for (let i = 0; i < stringIdsSize; i++) {
        const stringOff = view.getUint32(stringIdsOff + i * 4, true);
        let pos = stringOff;
        const len = view.getUint16(pos, true);
        pos += 2;
        let str = '';
        for (let j = 0; j < len; j++) str += String.fromCharCode(view.getUint8(pos++));
        strings.push(str);
    }
    return strings;
}

// ========== 下载远程 Jar 并提取 Spider JS（智能检测格式） ==========
async function fetchSpiderFromJar(spiderUrl) {
    const buffer = await downloadBuffer(spiderUrl);
    // 检查是否为ZIP（PK头）
    if (buffer.length >= 2 && buffer[0] === 0x50 && buffer[1] === 0x4B) {
        const files = unzipBuffer(buffer);
        const dexFile = files.find(f => f.name === 'classes.dex');
        if (!dexFile) throw new Error('Jar中未找到classes.dex');
        const strings = extractStringsFromDex(dexFile.data);
        if (strings.length === 0) throw new Error('DEX字符串池为空');
        strings.sort((a, b) => b.length - a.length);
        const spiderCode = strings[0];
        if (!spiderCode || spiderCode.length < 100) throw new Error('提取的字符串过短，可能不是JS代码');
        return spiderCode;
    } else {
        // 非ZIP，直接当作文本JavaScript执行
        const content = buffer.toString('utf8').trim();
        if (content.length === 0) throw new Error('下载的内容为空');
        // 简单判断是否为JavaScript（包含function或var等）
        if (content.includes('function') || content.includes('var ') || content.includes('const ') || content.includes('__jsEvalReturn')) {
            return content;
        }
        // 可能是JSON配置或其他，尝试从中提取
        try {
            const json = JSON.parse(content);
            // 如果JSON中有spider字段，递归处理
            if (json.spider) return fetchSpiderFromJar(json.spider);
            throw new Error('下载内容不是有效的JavaScript或ZIP');
        } catch (e) {
            throw new Error('下载内容不是ZIP且不是有效的JavaScript');
        }
    }
}

function downloadBuffer(url) {
    return new Promise((resolve, reject) => {
        const cleanUrl = url.replace(/[\n\r\t]/g, '').trim();
        const parsed = URL.parse(cleanUrl);
        const client = parsed.protocol === 'https:' ? https : http;
        client.get(cleanUrl, { headers: getDefaultHeaders() }, (res) => {
            const chunks = [];
            res.on('data', chunk => chunks.push(chunk));
            res.on('end', () => resolve(Buffer.concat(chunks)));
        }).on('error', reject);
    });
}

// ========== 创建 Spider 沙箱 ==========
function createSpiderSandbox(spiderDir) {
    const sandbox = {
        axios, qs, crypto, https, fs, Uri, _, request,
        md5, base64Encode, base64Decode, aes, des, rsa, randStr,
        localGet, localSet,
        console: { log: () => {}, error: () => {} },
        setTimeout, clearTimeout, Buffer,
        __dirname: spiderDir,
    };
    sandbox.require = (modulePath) => {
        if (modulePath === 'axios') return axios;
        if (modulePath === 'qs') return qs;
        if (modulePath === 'crypto') return crypto;
        if (modulePath === 'fs') return fs;
        if (modulePath === 'https') return https;
        if (modulePath === 'path') return path;
        if (modulePath === 'url') return URL;
        if (modulePath.startsWith('.')) {
            const resolved = path.resolve(sandbox.__dirname, modulePath);
            const ext = path.extname(resolved) ? resolved : resolved + '.js';
            if (!fs.existsSync(ext)) throw new Error(`Cannot find module '${modulePath}'`);
            const code = fs.readFileSync(ext, 'utf8');
            const mod = { exports: {} };
            const modSandbox = { ...sandbox, module: mod, exports: mod.exports, require: (p) => sandbox.require(p.startsWith('.') ? path.resolve(path.dirname(ext), p) : p) };
            vm.createContext(modSandbox);
            vm.runInContext(code, modSandbox, { filename: ext });
            return mod.exports;
        }
        throw new Error(`Cannot find module '${modulePath}'`);
    };
    return sandbox;
}

// ========== 智能查找本地 Spider ==========
function findLocalSpider(apiName, sourceName = '') {
    const baseDir = path.join(__dirname, 'open');
    if (!fs.existsSync(baseDir)) return null;
    const cleanApi = apiName.replace(/^csp_/, '').toLowerCase();
    const keywords = [cleanApi, sourceName.toLowerCase()].filter(k => k.length > 0);
    function getAllJsFiles(dir) {
        let results = [];
        const items = fs.readdirSync(dir);
        for (const item of items) {
            const fullPath = path.join(dir, item);
            const stat = fs.statSync(fullPath);
            if (stat.isDirectory()) results = results.concat(getAllJsFiles(fullPath));
            else if (item.endsWith('.js')) results.push({ path: fullPath, name: item, dir: path.dirname(fullPath) });
        }
        return results;
    }
    const allFiles = getAllJsFiles(baseDir);
    if (allFiles.length === 0) return null;
    const scored = allFiles.map(file => {
        const fileName = file.name.toLowerCase();
        const filePath = file.path.toLowerCase();
        let score = 0;
        for (const kw of keywords) {
            if (fileName === kw + '.js') score += 100;
            else if (fileName.includes(kw)) score += 50;
            else if (filePath.includes(kw)) score += 30;
            const chineseMatch = sourceName.match(/[\u4e00-\u9fa5]+/g);
            if (chineseMatch) for (const ch of chineseMatch) if (fileName.includes(ch)) score += 40;
        }
        return { ...file, score };
    });
    scored.sort((a, b) => b.score - a.score);
    if (scored[0] && scored[0].score > 0) return scored[0];
    return null;
}

function loadLocalSpider(apiName, sourceName) {
    const found = findLocalSpider(apiName, sourceName);
    if (!found) return null;
    const scriptContent = fs.readFileSync(found.path, 'utf8');
    const sandbox = createSpiderSandbox(found.dir);
    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, { filename: found.path });
    if (typeof sandbox.__jsEvalReturn === 'function') return sandbox.__jsEvalReturn();
    return sandbox;
}

// ========== 统一加载 ==========
async function loadSpider(api, spiderUrl, sourceName) {
    const local = loadLocalSpider(api, sourceName);
    if (local) return local;
    if (!spiderUrl) throw new Error(`未找到本地 Spider (${api}) 且未提供 spider 地址`);
    let scriptContent = jarCache.get(spiderUrl);
    if (!scriptContent) {
        scriptContent = await fetchSpiderFromJar(spiderUrl);
        jarCache.set(spiderUrl, scriptContent);
    }
    const sandbox = createSpiderSandbox(path.join(__dirname, 'open'));
    vm.createContext(sandbox);
    vm.runInContext(scriptContent, sandbox, { filename: 'spider.js', timeout: 15000 });
    if (typeof sandbox.__jsEvalReturn === 'function') return sandbox.__jsEvalReturn();
    return sandbox;
}

// ========== HTTP 服务器 ==========
const server = http.createServer(async (req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200); res.end('OK'); return;
    }
    if (req.method === 'POST' && req.url === '/parse') {
        let body = '';
        req.on('data', chunk => body += chunk);
        req.on('end', async () => {
            try {
                const request = JSON.parse(body);
                const { action, api, key, ext, tid, page, vod_id, wd, url, headers, spider, sourceName } = request;
                if (url) {
                    parseGeneric(url, headers).then(data => sendSuccess(res, data)).catch(err => sendError(res, `[Generic] ${err.message}`));
                    return;
                }
                if (api && api.startsWith('csp_')) {
                    const spiderModule = await loadSpider(api, spider, sourceName || '');
                    const result = await executeSpider(spiderModule, action, key, ext, tid, page, vod_id, wd);
                    sendSuccess(res, result);
                } else {
                    sendError(res, '无效的请求参数');
                }
            } catch (err) { sendError(res, `[Parse] ${err.message}`); }
        });
        return;
    }
    res.writeHead(404); res.end();
});

server.listen(PORT, '127.0.0.1', () => {});

function sendSuccess(res, data) { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ success: true, data })); }
function sendError(res, error) { res.writeHead(200, { 'Content-Type': 'application/json' }); res.end(JSON.stringify({ success: false, error })); }

async function executeSpider(spiderModule, action, key, ext, tid, page, vodId, keyword) {
    if (spiderModule.init) await spiderModule.init({ skey: key, stype: 3, ext });
    let result;
    switch (action) {
        case 'home': result = await spiderModule.home(); break;
        case 'list': result = await spiderModule.category(tid, page, {}, ext); break;
        case 'detail': result = await spiderModule.detail(vodId); break;
        case 'search': result = await spiderModule.search(keyword, false, page); break;
        default: throw new Error(`未知 action: ${action}`);
    }
    if (typeof result === 'string') try { result = JSON.parse(result); } catch (e) {}
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

function getDefaultHeaders() {
    return { 'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.0 Mobile/15E148 Safari/604.1' };
}
