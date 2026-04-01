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

本仓库**不再提供**部署脚本；用 **SSH / scp** 即可。服务器与 IP 写在本地 `docs/infrastructure.md`（从 `docs/infrastructure.example.md` 复制；已 **gitignore**，勿提交）。**上传任何文件时排除 `docs/`**，避免把密码带到服务器。

### 更新首页

在仓库根目录（示例：`root`、公网 IP 换成你的）：

```bash
scp ./index.html root@<ECS公网IP>:/var/web/my_product/index.html
```

### 当前约定（Ubuntu + Nginx）

- **站点根**：`/var/web/my_product`（与 `docs/infrastructure.md` 里「部署对应关系」一致即可）。
- **虚拟主机**：`/etc/nginx/sites-available/product.xyptkd.cn`，并启用：

  ```bash
  sudo ln -sf /etc/nginx/sites-available/product.xyptkd.cn /etc/nginx/sites-enabled/
  sudo rm -f /etc/nginx/sites-enabled/default
  sudo nginx -t && sudo systemctl reload nginx
  ```

- **HTTP-01 校验目录**：`/var/www/certbot`（配置里 `location /.well-known/acme-challenge/` 指向该目录）。

示例 `server` 块（与现网一致时可整段保存为 `sites-available` 文件）：

```nginx
server {
    listen 80;
    listen [::]:80;
    server_name product.xyptkd.cn;

    root /var/web/my_product;
    index index.html;

    location /.well-known/acme-challenge/ {
        root /var/www/certbot;
    }

    location / {
        try_files $uri $uri/ =404;
    }

    location = /index.html {
        add_header Cache-Control "no-cache";
    }
}
```

服务器上自检：

```bash
curl -sI http://127.0.0.1/ -H 'Host: product.xyptkd.cn'
```

### HTTPS（Let’s Encrypt，在服务器上手动）

1. `sudo apt install -y certbot python3-certbot-nginx`（或 `certbot` + 手动改 Nginx）。  
2. 保证 **80** 可从公网访问到上述 `/.well-known/`（Cloudflare **橙云** 时需回源通；失败可临时 **灰云** 签证书）。  
3. 示例：`sudo certbot --nginx -d product.xyptkd.cn`（按提示操作）。  
4. 续期由 **certbot 自带的 systemd timer** 或自行加 **cron**：`certbot renew --quiet`（成功后 `systemctl reload nginx`）。

源站 **443 + 可信证书** 就绪后，Cloudflare 可用 **Full (strict)**；仅 **80** 时用 **Flexible**，否则易 **522**。

### 访问检查清单

1. **DNS**：权威在 **Cloudflare** 时，只在 CF 面板改 **A 记录** 指向 ECS 公网 IP。  
2. **安全组**：入站 **TCP 80 / 443**（及 SSH 端口）。  
3. **验证**：`curl -sI https://product.xyptkd.cn`（经 CF 时应为 200，具体以 SSL 模式为准）。

## 说明

- 根目录的 `.nojekyll` 用于关闭 Jekyll，避免个别静态文件被误处理。
- 若你的默认分支不是 `main`，请改 `.github/workflows/pages.yml` 里 `branches` 或把仓库默认分支改成 `main`。
- 页面里字体等资源使用外链，子路径部署（`/仓库名/`）无需改 `base`；若以后增加以 `/` 开头的本地资源路径，需再配置 `base` 或改为相对路径。
