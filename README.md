# gin-ok-service

一个最小的 Gin HTTP 服务。访问根路径会返回纯文本 `ok`。

## 本地运行

```bash
go run .
curl http://localhost:8080/
```

## Docker 运行

```bash
docker compose up --build -d
curl http://localhost:8080/
```

停止服务：

```bash
docker compose down
```

服务默认监听 `8080` 端口，也可以通过 `PORT` 环境变量修改。
