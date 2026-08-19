# gin-ok-service

一个最小的 Gin HTTP 服务。访问根路径会返回纯文本 `hello world`。

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

## GitHub Actions CI/CD

工作流位于 `.github/workflows/cicd.yml`，执行流程如下：

1. 运行单元测试、静态检查并验证 Docker 构建。
2. `main` 分支更新后，构建 `linux/amd64` 和 `linux/arm64` 镜像并推送到阿里云容器镜像服务 ACR。
3. 配置启用后，通过 SSH 把生产 Compose 文件上传到物理服务器。
4. 服务器使用临时 Docker 凭证，从 ACR 拉取以 Git commit SHA 标记的镜像；部署结束后凭证自动清理。
5. 服务器启动容器并等待健康检查。
6. 健康检查失败时，自动尝试恢复上一次部署的镜像。

部署功能默认关闭。请在仓库 `Settings > Secrets and variables > Actions` 中设置：

### Secrets

| 名称 | 内容 |
| --- | --- |
| `SERVER_HOST` | 服务器公网 IP 或可从 GitHub Runner 访问的域名 |
| `DEPLOY_SSH_KEY` | 专用于部署的 SSH 私钥，建议使用无密码的 Ed25519 密钥 |
| `SERVER_KNOWN_HOSTS` | 已核验的服务器 SSH host key，例如 `ssh-keyscan -H -p 22 example.com` 的输出 |
| `ACR_USERNAME` | ACR“访问凭证”页面显示的用户名 |
| `ACR_PASSWORD` | ACR 固定密码，不是阿里云账号登录密码 |

### Variables

| 名称 | 是否必填 | 默认值/说明 |
| --- | --- | --- |
| `SERVER_USER` | 是 | SSH 用户，必须有执行 Docker 的权限 |
| `ENABLE_DEPLOY` | 是 | 准备完成后设置为 `true` |
| `SERVER_PORT` | 否 | `22` |
| `DEPLOY_PATH` | 否 | `/opt/gin-ok-service`，SSH 用户必须可写 |
| `APP_BIND_ADDRESS` | 否 | `0.0.0.0`；有本机反向代理时建议使用 `127.0.0.1` |
| `APP_PORT` | 否 | `8080` |
| `ACR_REGISTRY` | 是 | ACR 公网登录地址，不包含 `https://` |
| `ACR_NAMESPACE` | 是 | ACR 命名空间 |
| `ACR_REPOSITORY` | 是 | ACR 镜像仓库名，例如 `gin-ok-service` |

服务器需要安装 Docker Engine 和 Docker Compose v2，并允许 SSH 用户执行 `docker`。例如：

```bash
sudo mkdir -p /opt/gin-ok-service
sudo chown <SSH用户>:<SSH用户> /opt/gin-ok-service
sudo usermod -aG docker <SSH用户>
```

修改用户组后需要重新登录。服务器还需要允许 GitHub 托管 Runner 通过 SSH 访问，并能访问配置的 ACR 公网地址拉取镜像。

也可以使用仓库提供的本地配置文件和上传脚本：

```bash
# 编辑服务器和 ACR 本地配置文件；两个文件均已被 .gitignore 忽略
vim deploy/github-actions-config.env
vim deploy/acr-config.env

# 校验配置并上传 Secrets/Variables
./deploy/configure-github-actions.sh
```

可提交的字段说明模板位于 `deploy/github-actions-config.env.example` 和 `deploy/acr-config.env.example`。实际配置、ACR 密码和 SSH 私钥都不应提交到 Git。
