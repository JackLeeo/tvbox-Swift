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

const NODE_PATH = process.env.NODE_PATH || path.join(__dirname, '..', 'Documents');
if (!fs.existsSync(NODE_PATH)) fs.mkdirSync(NODE_PATH, { recursive: true });

function safePreview(str, len = 150) {
    if (!str) return '';
    return str.slice(0, len).replace(/[\\]/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '\\r');
}

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

// ========== axios 模拟 ==========
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

// ========== qs 模拟 ==========
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
        if (offset + 46 > buffer.length) break;
        if (view.getUint32(offset, true) !== 0x02014b50) break;
        const compressionMethod = view.getUint16(offset + 10, true);
        const compressedSize = view.getUint32(offset + 20, true);
        const fileNameLength = view.getUint16(offset + 28, true);
        const extraFieldLength = view.getUint16(offset + 30, true);
        const fileCommentLength = view.getUint16(offset + 32, true);
        const localHeaderOffset = view.getUint32(offset + 42, true);
        if (offset + 46 + fileNameLength > buffer.length) break;
        const fileName = buffer.toString('utf8', offset + 46, offset + 46 + fileNameLength);
        let localOffset = localHeaderOffset;
        if (localOffset + 30 > buffer.length) { offset += 46 + fileNameLength + extraFieldLength + fileCommentLength; continue; }
        if (view.getUint32(localOffset, true) !== 0x04034b50) { offset += 46 + fileNameLength + extraFieldLength + fileCommentLength; continue; }
        const localFileNameLength = view.getUint16(localOffset + 26, true);
        const localExtraFieldLength = view.getUint16(localOffset + 28, true);
        const dataOffset = localOffset + 30 + localFileNameLength + localExtraFieldLength;
        if (dataOffset + compressedSize > buffer.length) { offset += 46 + fileNameLength + extraFieldLength + fileCommentLength; continue; }
        let fileData = buffer.slice(dataOffset, dataOffset + compressedSize);
        if (compressionMethod === 8) {
            try { fileData = zlib.inflateRawSync(fileData); } catch (e) { fileData = zlib.inflateSync(fileData); }
        }
        files.push({ name: fileName, data: fileData });
        offset += 46 + fileNameLength + extraFieldLength + fileCommentLength;
    }
    return files;
}

// ========== uleb128 解码 ==========
function readUleb128(view, pos) {
    let result = 0;
    let shift = 0;
    let byte;
    do {
        if (pos >= view.byteLength) throw new Error('ULEB128 读取越界');
        byte = view.getUint8(pos++);
        result |= (byte & 0x7F) << shift;
        shift += 7;
    } while ((byte & 0x80) !== 0);
    return { result, pos };
}

// ========== 判断是否为 Java 类名（包括数组） ==========
function isJavaClassName(str) {
    return (str.startsWith('L') || str.startsWith('[')) && str.includes('/');
}

// ========== DEX 字符串提取（修正 uleb128） ==========
function extractStringsFromDex(dexBuffer) {
    if (dexBuffer.length < 112) throw new Error(`DEX文件太小: ${dexBuffer.length} bytes`);
    const view = new DataView(dexBuffer.buffer, dexBuffer.byteOffset, dexBuffer.byteLength);
    const stringIdsSize = view.getUint32(56, true);
    const stringIdsOff = view.getUint32(60, true);
    if (stringIdsSize === 0) throw new Error('DEX字符串池为空');
    if (stringIdsOff + stringIdsSize * 4 > dexBuffer.length) throw new Error(`字符串索引区越界`);
    const strings = [];
    for (let i = 0; i < stringIdsSize; i++) {
        const stringOff = view.getUint32(stringIdsOff + i * 4, true);
        if (stringOff + 4 > dexBuffer.length) continue;
        let pos = stringOff;
        // 读取 uleb128 长度
        let len;
        try {
            const decoded = readUleb128(view, pos);
            len = decoded.result;
            pos = decoded.pos;
        } catch (e) {
            continue;
        }
        if (pos + len > dexBuffer.length) continue;
        let str = '';
        for (let j = 0; j < len; j++) {
            str += String.fromCharCode(view.getUint8(pos++));
        }
        // 过滤 Java 类名
        if (!isJavaClassName(str)) {
            strings.push(str);
        }
    }
    return strings;
}

function selectSpiderCode(strings) {
    console.log(`[Node] 候选字符串数量: ${strings.length}`);
    const jsKeywords = ['function', 'var ', 'const ', '__jsEvalReturn', 'home(', 'category(', 'detail(', 'search('];
    for (const kw of jsKeywords) {
        const found = strings.find(s => s.includes(kw));
        if (found) {
            console.log(`[Node] 通过关键字 '${kw}' 匹配到 Spider`);
            return found;
        }
    }
    const longStrings = strings.filter(s => s.length > 500);
    if (longStrings.length > 0) {
        longStrings.sort((a, b) => b.length - a.length);
        console.log(`[Node] 使用最长非 Java 字符串 (长度: ${longStrings[0].length})`);
        return longStrings[0];
    }
    strings.sort((a, b) => b.length - a.length);
    console.log(`[Node] 回退到最长字符串 (长度: ${strings[0].length})`);
    return strings[0];
}

// ========== 下载远程 Jar（支持重定向和 gzip） ==========
async function fetchSpiderFromJar(spiderUrl) {
    let cleanUrl = spiderUrl.split(';')[0].trim();
    const buffer = await downloadBuffer(cleanUrl);
    
    // 严格判断ZIP文件：前4个字节必须是 PK\003\004
    if (buffer.length >= 4 && buffer.readUInt32LE(0) === 0x04034b50) {
        const files = unzipBuffer(buffer);
        const dexFile = files.find(f => f.name === 'classes.dex');
        if (!dexFile) throw new Error('Jar中未找到classes.dex文件，可能下载到了错误的内容');
        
        const strings = extractStringsFromDex(dexFile.data);
        if (strings.length === 0) throw new Error('DEX字符串池为空（过滤后）');
        
        const spiderCode = selectSpiderCode(strings);
        if (!spiderCode || spiderCode.length < 100) throw new Error('提取的字符串过短，可能不是JS代码');
        console.log(`[Node] 选中 Spider 预览: ${safePreview(spiderCode, 150)}`);
        return spiderCode;
    } else {
        let content = buffer.toString('utf8').trim();
        if (content.startsWith('<?xml') || content.includes('<Error>') || content.includes('resource not found')) {
            throw new Error(`下载到错误页面: ${safePreview(content, 200)}，Jar源服务器拒绝了访问，请检查网络`);
        }
        if (content.includes('function') || content.includes('__jsEvalReturn')) {
            return content;
        }
        const decoded = tryDecodeSpider(content);
        if (decoded) return decoded;
        throw new Error(`无法解析 Spider 内容。预览: ${safePreview(content, 150)}`);
    }
}

function tryDecodeSpider(content) {
    try {
        const decoded = Buffer.from(content, 'base64').toString('utf8');
        if (decoded.includes('function') || decoded.includes('__jsEvalReturn')) return decoded;
    } catch (e) {}
    return null;
}

// 增强版下载：支持重定向（301/302）和 gzip 解压，用TVBox原生的okhttp请求头！
function downloadBuffer(url, redirectCount = 0) {
    return new Promise((resolve, reject) => {
        if (redirectCount > 5) { reject(new Error('重定向次数过多')); return; }
        const cleanUrl = url.replace(/[\n\r\t]/g, '').trim();
        const parsed = URL.parse(cleanUrl);
        const client = parsed.protocol === 'https:' ? https : http;
        const headers = getDefaultHeaders();
        headers['Accept-Encoding'] = 'gzip, deflate';
        client.get(cleanUrl, { headers }, (res) => {
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                const newUrl = URL.resolve(cleanUrl, res.headers.location);
                resolve(downloadBuffer(newUrl, redirectCount + 1));
                return;
            }
            if (res.statusCode !== 200) { reject(new Error(`HTTP ${res.statusCode}`)); return; }
            const chunks = [];
            const stream = res.headers['content-encoding'] === 'gzip' ? res.pipe(zlib.createGunzip()) : res;
            stream.on('data', chunk => chunks.push(chunk));
            stream.on('end', () => resolve(Buffer.concat(chunks)));
            stream.on('error', reject);
        }).on('error', reject);
    });
}

// ========== 创建 Spider 沙箱 ==========
function createSpiderSandbox() {
    const sandbox = {
        axios, qs, crypto, https, fs, Uri, _, request,
        md5, base64Encode, base64Decode, aes, des, rsa, randStr,
        localGet, localSet,
        console: { log: () => {}, error: () => {} },
        setTimeout, clearTimeout, Buffer,
        __dirname: path.join(__dirname, 'open'),
    };
    sandbox.require = (modulePath) => {
        if (modulePath === 'axios') return axios;
        if (modulePath === 'qs') return qs;
        if (modulePath === 'crypto') return crypto;
        if (modulePath === 'fs') return fs;
        if (modulePath === 'https') return https;
        if (modulePath === 'path') return path;
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

// ========== 统一加载 ==========
async function loadSpider(spiderUrl) {
    if (!spiderUrl) throw new Error('未提供 spider 地址');
    let scriptContent = jarCache.get(spiderUrl);
    if (!scriptContent) {
        scriptContent = await fetchSpiderFromJar(spiderUrl);
        jarCache.set(spiderUrl, scriptContent);
    }
    let cleanScript = scriptContent.replace(/^\uFEFF/, '').trim();
    const sandbox = createSpiderSandbox();
    vm.createContext(sandbox);
    try {
        vm.runInContext(cleanScript, sandbox, { filename: 'spider.js', timeout: 15000 });
    } catch (e) {
        try {
            vm.runInContext(`(function(){${cleanScript}})()`, sandbox, { filename: 'spider.js', timeout: 15000 });
        } catch (e2) {
            throw new Error(`脚本执行失败: ${e.message}。预览: ${safePreview(cleanScript, 150)}`);
        }
    }
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
                const { action, api, key, ext, tid, page, vod_id, wd, url, headers, spider } = request;
                if (url) {
                    parseGeneric(url, headers).then(data => sendSuccess(res, data)).catch(err => sendError(res, `[Generic] ${err.message}`));
                    return;
                }
                // 这里放开了！不管是csp_还是远程Jar，都处理！
                if (api) {
                    if (!spider) throw new Error('缺少 spider 地址');
                    const spiderModule = await loadSpider(spider);
                    const result = await executeSpider(spiderModule, action, key, ext, tid, page, vod_id, wd);
                    sendSuccess(res, result);
                } else {
                    sendError(res, '无效的请求参数');
                }
            } catch (err) {
                sendError(res, `[Parse] ${safePreview(err.message, 500)}`);
            }
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
    // TVBox原生的请求头！和安卓TVBox完全一样！Jar源的服务器绝对认这个！
    return { 
        'User-Agent': 'okhttp/3.14.9',
        'Accept': '*/*',
        'Connection': 'Keep-Alive'
    };
}
