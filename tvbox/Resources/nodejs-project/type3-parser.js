const http = require('http');
const PORT = 3000;

const server = http.createServer((req, res) => {
    if (req.method === 'GET' && req.url === '/health') {
        res.writeHead(200);
        res.end('OK');
        return;
    }

    if (req.method === 'POST' && req.url === '/parse') {
        // 忽略所有请求内容，直接返回测试数据
        const response = {
            success: true,
            data: {
                class: [
                    { type_id: "1", type_name: "电影" },
                    { type_id: "2", type_name: "电视剧" }
                ],
                list: [
                    {
                        vod_id: "verify001",
                        vod_name: "✅ 脚本替换验证成功",
                        vod_pic: "",
                        vod_remarks: "请确认文件已更新"
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
    console.log('[Node] Verify server running on port', PORT);
});
