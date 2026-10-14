# 发布到 GitHub：新手操作步骤（ShawnZhou1993）

本地仓库已初始化好（2 个 commit，author 已设为 ShawnZhou1993），你只需要 4 步。

## 第 1 步：在 GitHub 创建空仓库

1. 浏览器打开 https://github.com/new
2. **Repository name** 填：`ps5-portal-high-bitrate-docker`
3. **Public**（公开，别人才能看到和拉镜像）
4. ⚠️ **不要勾选** "Add a README file" / "Add .gitignore" / "Choose a license" 中任何一项
   （勾了会和本地仓库冲突，push 会被拒绝）
5. 点 **Create repository**

创建后页面会显示一个仓库地址，形如：
`https://github.com/ShawnZhou1993/ps5-portal-high-bitrate-docker.git`

## 第 2 步：本地关联并推送

打开 Git Bash（或本终端），执行：

```bash
cd /d/PS5-Router/ps5-portal-relay-docker
git remote add origin https://github.com/ShawnZhou1993/ps5-portal-high-bitrate-docker.git
git push -u origin main
```

**第一次 push 会弹出浏览器窗口要求登录 GitHub**（这是 Git 自带的凭据管理器 GCM）：
- 点 "Sign in with your browser" → 浏览器里登录你的 GitHub 账号 → 授权
- 授权后回到终端，推送自动继续，等到出现 `Branch 'main' set up to track...` 即成功

> 如果弹窗没出现或报 `Authentication failed`，见文末「常见问题」。

## 第 3 步：开启 Actions 写权限（CI 推镜像用）

1. 打开 https://github.com/ShawnZhou1993/ps5-portal-high-bitrate-docker/settings/actions
2. **Workflow permissions** 选 **Read and write permissions**
3. 点 Save

不做这步，第 4 步的 CI 会在最后推镜像时报 403 权限错误。

## 第 4 步：打标签发版（触发多架构镜像构建）

```bash
git tag v0.1.0
git push --tags
```

然后打开 https://github.com/ShawnZhou1993/ps5-portal-high-bitrate-docker/actions
能看到 "Release multi-arch image" 工作流开始跑（amd64+arm64 约 5-10 分钟，QEMU 模拟 arm64 编译较慢是正常的）。

绿勾 ✅ 后镜像就在 `ghcr.io/shawnzhou1993/portal-relay:v0.1.0`（同时打 `:0.1.0` `:0.1` `:0` `:latest`）。

**默认发布出来的镜像是 private**。想让别人也能 `docker pull`：
1. 打开 https://github.com/users/ShawnZhou1993/packages/container/portal-relay/settings
2. **Change visibility** → Public
3. 按提示确认

## 验证发布成功

```bash
docker pull ghcr.io/shawnzhou1993/portal-relay:latest
docker run --rm ghcr.io/shawnzhou1993/portal-relay:latest version
```

## 常见问题

**Q: push 时报 `remote: Support for password authentication was removed`**
A: 你的 Git 版本在用账号密码而不是 GCM。执行 `git config --global credential.helper manager` 后重试 push，应该弹浏览器。

**Q: 弹窗一直不出现 / 报 `could not read Username`**
A: 手动触发一次：`git credential-manager github login`（Git Bash 里），或在 Windows「凭据管理器」里删掉旧的 github.com 条目再试。

**Q: Actions 页面说 "Workflows aren't being run on this repository"**
A: 仓库太新或没权限。到 Settings → Actions → General → 确认 "Allow all actions and reusable workflows" 已选中。main 分支的首次 push 本身就会触发一次构建（tag 是 `:main`）。

**Q: 推完想改 commit 作者？**
A: push 前改最简单。已经 push 了要重写历史：
```bash
git config user.name "ShawnZhou1993"
git config user.email "ShawnZhou1993@users.noreply.github.com"
git rebase -i --root --exec "git commit --amend --reset-author --no-edit"
git push --force-with-lease origin main
```

**Q: 以后代码更新了怎么发新版？**
```bash
git add -A && git commit -m "描述改了什么"
git push
git tag v0.1.1 && git push --tags   # 触发新镜像
```
