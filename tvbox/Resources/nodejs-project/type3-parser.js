const http = require('http');
const PORT = 3000;

const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200);
        res.end('OK');
        return;
    }
    if (req.method === 'POST' && req.url === '/parse') {
        const response = {
            success: true,
            data: {
                class: [{ type_id: "1", type_name: "电影" }],
                list: [{ vod_id: "v3_001", vod_name: "✅ 脚本版本: V3", vod_pic: "", vod_remarks: "" }]
            }
        };
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(response));
        return;
    }
    res.writeHead(404);
    res.end();
});

server.listen(PORT, '127.0.0.1', () => console.log('V3 Server on', PORT));
