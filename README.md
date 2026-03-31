# Cookie Switcher Pro — landing page

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

## 说明

- 根目录的 `.nojekyll` 用于关闭 Jekyll，避免个别静态文件被误处理。
- 若你的默认分支不是 `main`，请改 `.github/workflows/pages.yml` 里 `branches` 或把仓库默认分支改成 `main`。
- 页面里字体等资源使用外链，子路径部署（`/仓库名/`）无需改 `base`；若以后增加以 `/` 开头的本地资源路径，需再配置 `base` 或改为相对路径。
