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
            // 忽略所有请求参数，直接返回测试数据
            res.writeHead(200, { 'Content-Type': 'application/json' });
            res.end(JSON.stringify({
                success: true,
                data: {
                    class: [],
                    list: [
                        {
                            vod_id: "test001",
                            vod_name: "✅ 文件替换成功",
                            vod_pic: "",
                            vod_remarks: "请截图此页面反馈"
                        }
                    ]
                }
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
