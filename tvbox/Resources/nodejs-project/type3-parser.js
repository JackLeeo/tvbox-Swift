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
            // 构造一个完整的、符合 TVBox 首页格式的响应
            const responseData = {
                class: [
                    { type_id: "1", type_name: "电影" },
                    { type_id: "2", type_name: "电视剧" }
                ],
                list: [
                    {
                        vod_id: "test001",
                        vod_name: "✅ 替换成功",
                        vod_pic: "https://example.com/pic.jpg",
                        vod_remarks: "测试"
                    }
                ]
            };
            const response = { success: true, data: responseData };
            const jsonStr = JSON.stringify(response);
            console.log('[Node] 返回数据:', jsonStr);
            
            // 为了让悬浮窗直接看到返回内容，我们故意返回一个错误，把 JSON 放在错误消息里
            // 这样您就能在悬浮窗中复制完整 JSON
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                success: false,
                error: 'DEBUG: ' + jsonStr
            }));
        });
        return;
    }

    res.writeHead(404);
    res.end();
});

server.listen(PORT, '127.0.0.1', () => {
    console.log(`[Node] Test server running on port ${PORT}`);
});
