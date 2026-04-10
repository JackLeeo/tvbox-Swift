const http = require('http');
const PORT = 3000;

const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200);
        res.end('OK');
        return;
    }

    if (req.method === 'POST' && req.url === '/parse') {
        // 完全忽略请求内容，直接返回测试数据
        const response = {
            success: true,
            data: {
                class: [
                    { type_id: "1", type_name: "电影" },
                    { type_id: "2", type_name: "电视剧" }
                ],
                list: [
                    {
                        vod_id: "final001",
                        vod_name: "✅ 最终验证成功",
                        vod_pic: "",
                        vod_remarks: "请确认此影片出现"
                    }
                ]
            }
        };
        res.writeHead(200, { 'Content-Type': 'application/json' });
        res.end(JSON.stringify(response));
        return;
    }

    res.writeHead(404);
    res.end();
});

server.listen(PORT, '127.0.0.1', () => {
    console.log('[Node] Final verify server on port', PORT);
});
