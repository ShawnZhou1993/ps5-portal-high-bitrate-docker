# Push to GitHub: 操作步骤

**前置**：你已在 GitHub 创建空仓库 `ps5-portal-high-bitrate-docker`
（不要勾选 Initialize with README/.gitignore/LICENSE，保持空仓库）。

## 方式 A（推荐）：直接 git push（保留 commit 历史）

1. 浏览器打开 https://github.com/new
2. Repository name: `ps5-portal-high-bitrate-docker`
3. **不要勾**任何初始化选项（README/.gitignore/LICENSE）
4. 点 Create repository，然后回到本地终端：

```bash
cd /d/PS5-Router/ps5-portal-relay-docker

# ⚠️ 把这两行换成你自己的 GitHub 用户名（id 数字不知道可省略，用 GitHub 提供的 noreply）
# 也可以直接保持现暂定身份推送，后续 git filter-branch 或 rebase 改
# 简单做法：现在改本仓库身份（不影响全局）
git config user.name "你的GitHub用户名"
git config user.email "你的GitHub用户名@users.noreply.github.com"

# 改完身份后修正最近一次 commit 的 author
git commit --amend --reset-author --no-edit

# 加 remote（把 YOUR-USER 换成你的 GitHub 用户名）
git remote add origin https://github.com/YOUR-USER/ps5-portal-high-bitrate-docker.git

git push -u origin main
```

推送后，**给上游送 PR**（可选但推荐）：
1. 在你的仓库 Settings → 勾上 Issues
2. 上游仓 https://github.com/atameric/ps5-portal-high-bitrate/issues/new 开个 issue，标题如
   "Docker image (multi-arch) for headless NAS/router deployment"，正文贴你仓库链接 +
   简短说明（macvlan + non-interactive configure-env + CI workflow）。

## 方式 B：纯网页上传（不推荐，丢 commit 历史）

如果你只想快速在 GitHub 上有个仓库不在乎历史，可以：
1. 在 GitHub 创建空仓库
2. 下载本目录生成的 `ps5-portal-high-bitrate-docker-gh.zip`（不含 .git，34 文件 / 64KB）
3. 解压到本地某处
4. 在 GitHub 仓库页用 "uploading an existing file" 把所有文件拖进去

不推荐——你将丢失 commit 历史和以后基于 git 的协作能力。

## CI 首次触发

push 完成后，actions 第一次会在 `main` 分支上跑（`type=ref,event=branch`）打出 `:main` 标签镜像。
正式发版时：
```bash
git tag v0.1.0
git push --tags
```
这次会同时打 `:v0.1.0` `:0.1.0` `:0.1` `:0` `:latest` 五个标签，并触发多架构 build。

## 推送后的额外配置

- 仓库 Settings → Actions → General → Workflow permissions 选 **Read and write permissions**（CI 才能推到 ghcr.io）
- 首次发布的镜像默认是 private，到 https://github.com/users/YOUR-USER/packages/container/ps5-portal-relay/settings 改成 Public（如果想让别人 docker pull）

## 关于 commit 作者身份

当前 commit 的身份是暂定的 `ps5-portal-relay contributor <contributor@users.noreply.github.com>`。
按上面方式 A 改完身份后用 `--amend --reset-author` 修正。**push 之前**改最简单；如果已 push 想
重写历史：
```bash
git rebase -i --root --exec "git commit --amend --reset-author --no-edit"
git push --force-with-lease origin main
```
（GitHub 也支持改 author 但更麻烦）