# Account Switch — landing page

浏览器扩展 **Account Switch（Cookie 配置）** 的简介页（`index.html`），可随本仓库一并发布到 GitHub Pages。

静态站点，通过 GitHub Actions 发布到 **GitHub Pages**。

## 首次发布步骤

1. 在 GitHub 新建仓库（可设为 Public，免费 Pages 最省事），不要勾选添加 README（本地已有文件时避免冲突）。
2. 本地初始化并推送（分支名需与 workflow 一致，默认 `main`）：

   ```bash
   cd /path/to/my_product
   git init
   git add .
   git commit -m "Add landing page and GitHub Pages workflow"
   git branch -M main
   git remote add origin https://github.com/<你的用户名>/<仓库名>.git
   git push -u origin main
   ```

3. 打开仓库 **Settings → Pages**。
4. **Build and deployment** 里，**Source** 选 **GitHub Actions**（不要选 Deploy from a branch，除非你想改用手动选分支发布）。
5. 回到 **Actions** 标签页，确认 **Deploy to GitHub Pages** 已成功跑完；若首次需点一次 **Approve** 批准 workflow。
6. 站点地址一般为：`https://<你的用户名>.github.io/<仓库名>/`

## 自建服务器（product 站点）

在本机填好 `docs/infrastructure.md`（从 `docs/infrastructure.example.md` 复制；该文件已被 git 忽略，**不会**进远程仓库）。在项目根目录执行：

```bash
./scripts/deploy-my-product.sh
```

脚本只上传根目录的 `index.html`，**不会**上传 `docs/`。若未配置 SSH 公钥，需已安装 `sshpass`（macOS 可用 Homebrew 安装）；优先尝试密钥登录。

### 服务器侧（Nginx 一键配置）

若已上传 `index.html` 但外网仍 **Cloudflare 522**、或直连 IP 无响应，在本机执行（会 SSH 登录服务器、安装/重启 Nginx、写入 `product.xyptkd.cn` 虚拟主机）：

```bash
./scripts/remote-setup-nginx-my-product.sh
```

- 站点根目录默认 **`/var/web/my_product`**（与 `deploy-my-product.sh` 从 `docs/infrastructure.md` 解析的路径一致；若写 `var/web/my_product` 会自动变成绝对路径）。
- 配置文件模板：`scripts/nginx-product.xyptkd.cn.conf`（HTTP + ACME 目录；远端为 `/etc/nginx/conf.d/product.xyptkd.cn.conf`）。
- 启用 HTTPS 后的完整配置：`scripts/nginx-product.xyptkd.cn.full.conf`（由下方 SSL 脚本部署）。

在服务器上自检（应返回 `HTTP/1.1 200`）：

```bash
curl -sI http://127.0.0.1/ -H 'Host: product.xyptkd.cn'
```

### HTTPS（Let’s Encrypt + 定时续期）

前提：`product.xyptkd.cn` 已解析到本机，且 **入站 TCP 80** 对公网或 Let’s Encrypt 校验路径可达（使用 **Cloudflare 橙云** 时，HTTP-01 一般会经 CDN 回源到源站 80，需保证回源与 `/.well-known/acme-challenge/` 未被拦截）。

在本机执行（SSH 登录服务器、安装 `certbot`、申请证书、切换为 **HTTPS Nginx 配置**、写入 **cron 每天 3:00 / 15:00 尝试续期**，续期成功则 `reload nginx`）：

```bash
./scripts/remote-ssl-certbot-my-product.sh
```

- 续期任务文件：`/etc/cron.d/letsencrypt-renew-nginx`（`certbot renew --deploy-hook "systemctl reload nginx"`）。
- 证书路径：`/etc/letsencrypt/live/product.xyptkd.cn/`。

源站已有 **443 + 有效证书** 后，Cloudflare 加密模式可改为 **Full (strict)**（此前仅 80 时易 522）。

**若脚本报错且含 `522` / `unauthorized`（HTTP-01）**：Let’s Encrypt 会访问 `http://product.xyptkd.cn/.well-known/...`，经 Cloudflare 回源；若源站 80 仍 522，校验失败。处理顺序建议：

1. 阿里云安全组放行 **TCP 80**（对 `0.0.0.0/0` 或 Cloudflare IP 段）。  
2. Cloudflare 把 **`product` 的 A 记录改为「仅 DNS」（灰云）**，再执行 `./scripts/remote-ssl-certbot-my-product.sh`；证书签发成功后，再开回 **橙云**，并把 SSL 模式设为 **Full (strict)**。  
3. 若必须长期橙云且 80 回源仍异常，可改用 **DNS-01**（在 DNS 面板手动添加 `_acme-challenge` TXT，或使用 `certbot-dns-cloudflare` 等插件 + API Token），不在此脚本内自动化。

### 要让 `https://product.xyptkd.cn` 在浏览器里能打开

1. **DNS**：权威解析在 **Cloudflare** 时，在 Cloudflare 面板维护记录；`product`（或泛解析 `*`）**A 记录** 指向 `docs/infrastructure.md` 中的 **ECS 公网 IP**。若在阿里云 DNS 控制台改记录但 NS 仍指向 Cloudflare，**改阿里云不会生效**。
2. **阿里云安全组**：入方向放行 **TCP 80**、**TCP 443**，源至少包含 **Cloudflare IP 段**（简化可先 `0.0.0.0/0` 验证后再收紧）。
3. **Cloudflare SSL/TLS**：源站仅 80 时用 **Flexible**；源站已按上文脚本启用 **443 + Let’s Encrypt** 后，可改为 **Full (strict)**。
4. 验证：`curl -sI https://product.xyptkd.cn` 应出现 `HTTP/2 200` 或 `HTTP/1.1 200`。

## 说明

- 根目录的 `.nojekyll` 用于关闭 Jekyll，避免个别静态文件被误处理。
- 若你的默认分支不是 `main`，请改 `.github/workflows/pages.yml` 里 `branches` 或把仓库默认分支改成 `main`。
- 页面里字体等资源使用外链，子路径部署（`/仓库名/`）无需改 `base`；若以后增加以 `/` 开头的本地资源路径，需再配置 `base` 或改为相对路径。
