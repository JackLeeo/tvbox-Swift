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

function safePreview(str, len = 200) {
    if (!str) return '';
    return str.slice(0, len).replace(/[\\]/g, '\\\\').replace(/"/g, '\\"').replace(/\n/g, '\\n').replace(/\r/g, '\\r');
}

// 保存调试文件
function saveDebugFile(buffer, url) {
    try {
        const timestamp = new Date().toISOString().replace(/[:.]/g, '-');
        const fileName = `spider_${timestamp}.jar`;
        const filePath = path.join(NODE_PATH, fileName);
        fs.writeFileSync(filePath, buffer);
        console.log(`[Node] 调试文件已保存: ${filePath}`);
    } catch (e) {}
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
    console.log(`[Node] ZIP 解压: 大小 ${buffer.length} bytes`);
    if (buffer.length < 22) throw new Error('文件太小');
    const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
    let eocdOffset = -1;
    for (let i = buffer.length - 22; i >= 0; i--) if (view.getUint32(i, true) === 0x06054b50) { eocdOffset = i; break; }
    if (eocdOffset === -1) throw new Error('不是有效的ZIP');
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
    console.log(`[Node] 解压出 ${files.length} 个文件`);
    return files;
}

// ========== uleb128 解码 ==========
function readUleb128(view, pos) {
    let result = 0;
    let shift = 0;
    let byte;
    do {
        if (pos >= view.byteLength) throw new Error('ULEB128 越界');
        byte = view.getUint8(pos++);
        result |= (byte & 0x7F) << shift;
        shift += 7;
    } while ((byte & 0x80) !== 0);
    return { result, pos };
}

function extractAllStringsFromDex(dexBuffer) {
    console.log(`[Node] DEX 大小: ${dexBuffer.length} bytes`);
    if (dexBuffer.length < 112) throw new Error('DEX太小');
    const view = new DataView(dexBuffer.buffer, dexBuffer.byteOffset, dexBuffer.byteLength);
    const stringIdsSize = view.getUint32(56, true);
    const stringIdsOff = view.getUint32(60, true);
    console.log(`[Node] 字符串池: ${stringIdsSize} 个，偏移: ${stringIdsOff}`);
    if (stringIdsSize === 0) return [];
    const strings = [];
    for (let i = 0; i < stringIdsSize; i++) {
        const stringOff = view.getUint32(stringIdsOff + i * 4, true);
        if (stringOff + 4 > dexBuffer.length) continue;
        let pos = stringOff;
        let len;
        try { const d = readUleb128(view, pos); len = d.result; pos = d.pos; } catch (e) { continue; }
        if (pos + len > dexBuffer.length) continue;
        let str = '';
        for (let j = 0; j < len; j++) str += String.fromCharCode(view.getUint8(pos++));
        strings.push(str);
    }
    return strings;
}

// ========== 下载并提取 ==========
async function fetchSpiderFromJar(spiderUrl) {
    let cleanUrl = spiderUrl.split(';')[0].trim();
    console.log(`[Node] 清洗后 URL: ${cleanUrl}`);
    const buffer = await downloadBuffer(cleanUrl);
    console.log(`[Node] 下载完成: ${buffer.length} bytes`);
    saveDebugFile(buffer, cleanUrl);

    if (buffer.length >= 2 && buffer[0] === 0x50 && buffer[1] === 0x4B) {
        const files = unzipBuffer(buffer);
        const dexFile = files.find(f => f.name === 'classes.dex');
        if (!dexFile) throw new Error('未找到classes.dex');
        const strings = extractAllStringsFromDex(dexFile.data);
        console.log(`[Node] 提取到 ${strings.length} 个字符串`);
        strings.sort((a, b) => b.length - a.length);
        const longest = strings[0] || '';
        console.log(`[Node] 最长字符串长度: ${longest.length}`);
        console.log(`[Node] 预览: ${safePreview(longest, 500)}`);
        return longest;
    } else {
        const content = buffer.toString('utf8');
        console.log(`[Node] 文本内容预览: ${safePreview(content, 500)}`);
        return content;
    }
}

function downloadBuffer(url, redirectCount = 0) {
    return new Promise((resolve, reject) => {
        if (redirectCount > 5) { reject(new Error('重定向过多')); return; }
        const cleanUrl = url.replace(/[\n\r\t]/g, '').trim();
        const parsed = URL.parse(cleanUrl);
        const client = parsed.protocol === 'https:' ? https : http;
        const headers = { 'User-Agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_0 like Mac OS X) AppleWebKit/605.1.15' };
        client.get(cleanUrl, { headers }, (res) => {
            if (res.statusCode >= 300 && res.statusCode < 400 && res.headers.location) {
                resolve(downloadBuffer(URL.resolve(cleanUrl, res.headers.location), redirectCount + 1));
                return;
            }
            if (res.statusCode !== 200) { reject(new Error(`HTTP ${res.statusCode}`)); return; }
            const chunks = [];
            res.on('data', chunk => chunks.push(chunk));
            res.on('end', () => resolve(Buffer.concat(chunks)));
        }).on('error', reject);
    });
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
                    // 通用解析
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: false, error: 'Generic parse not implemented' }));
                    return;
                }
                if (api && api.startsWith('csp_')) {
                    if (!spider) throw new Error('缺少 spider 地址');
                    console.log(`[Node] 收到请求: action=${action}, api=${api}`);
                    const spiderCode = await fetchSpiderFromJar(spider);
                    // 尝试执行
                    const sandbox = {
                        axios, qs, crypto, https, fs, Uri, _, request,
                        md5, base64Encode, base64Decode, aes, des, rsa, randStr,
                        localGet, localSet,
                        console: { log: () => {}, error: () => {} },
                        setTimeout, clearTimeout, Buffer,
                        __dirname: path.join(__dirname, 'open'),
                        java: {
                            io: { File: class {}, IOException: class {} },
                            lang: { String, StringBuilder: class { constructor() { this.str = ''; } append(s) { this.str += s; return this; } toString() { return this.str; } } },
                            util: { ArrayList: class { constructor() { this.list = []; } add(e) { this.list.push(e); } } },
                        },
                        org: { xmlpull: { v1: { XmlPullParserFactory: { newInstance: () => ({ setInput: () => {}, next: () => 1 }) } } } },
                    };
                    vm.createContext(sandbox);
                    try {
                        vm.runInContext(spiderCode, sandbox, { filename: 'spider.js', timeout: 30000 });
                    } catch (e) {
                        console.log(`[Node] 执行失败: ${e.message}`);
                        // 尝试包装
                        try { vm.runInContext(`(function(){${spiderCode}})()`, sandbox, { timeout: 30000 }); } catch (e2) {}
                    }
                    let spiderModule = sandbox.__jsEvalReturn ? sandbox.__jsEvalReturn() : sandbox;
                    if (spiderModule.init) await spiderModule.init({ skey: key, stype: 3, ext });
                    let result;
                    if (action === 'home') result = await spiderModule.home();
                    else result = { list: [] };
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: true, data: result }));
                } else {
                    res.writeHead(200, { 'Content-Type': 'application/json' });
                    res.end(JSON.stringify({ success: false, error: '无效的请求参数' }));
                }
            } catch (err) {
                console.log(`[Node] 请求异常: ${err.message}`);
                res.writeHead(200, { 'Content-Type': 'application/json' });
                res.end(JSON.stringify({ success: false, error: `[Parse] ${err.message}` }));
            }
        });
        return;
    }
    res.writeHead(404); res.end();
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`[Node] 服务器已启动: http://127.0.0.1:${PORT}`);
});
