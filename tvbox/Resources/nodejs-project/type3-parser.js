const http = require('http');
const PORT = 3000;

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
            const responseData = {
                class: [
                    { type_id: "1", type_name: "电影" },
                    { type_id: "2", type_name: "电视剧" }
                ],
                list: [
                    {
                        vod_id: "test001",
                        vod_name: "✅ 文件替换成功",
                        vod_pic: "https://example.com/pic.jpg",
                        vod_remarks: "测试影片"
                    }
                ]
            };
            const response = { success: true, data: responseData };
            const jsonStr = JSON.stringify(response);
            console.log('[Node] 返回数据:', jsonStr);
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(jsonStr);
        });
        return;
    }

    res.writeHead(404);
    res.end();
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`[Node] Test server running on port ${PORT}`);
});
