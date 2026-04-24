# Inhuman · 整活网页合集

> 一个不把你当人的整活网页合集。  
> 在线预览：**https://cs-lx.github.io/Inhuman/**

这里收集了一堆"抽象"的小网页 —— 长得像验证码、网盘、注册表单…… 点进去会让你开始怀疑人生。

## 项目列表

| 文件夹 | 项目 | 配套视频 |
| --- | --- | --- |
| `Circle/` | 红圈验证 —— 证明你是人类 | — |
| `NetDisk [BV1p8DeBtEN5]/` | 摆渡网盘 | [BV1p8DeBtEN5](https://www.bilibili.com/video/BV1p8DeBtEN5) |
| `Prediction [BV1XgAczLEq5]/` | 预测长大的你 | [BV1XgAczLEq5](https://www.bilibili.com/video/BV1XgAczLEq5) |
| `Registration [BV1hfieBqE3u]/` | 用户身份统一注册中心 | [BV1hfieBqE3u](https://www.bilibili.com/video/BV1hfieBqE3u) |
| `Sisyphus/` | 西西弗斯验证码 | — |
| `Sort/` | 机器人身份验证（排序） | — |

> 文件夹命名规则：带 `[BVxxxx]` 的表示有对应的 B 站视频，文件夹里同名 `html`（去掉中括号）就是整活页面入口。

## 开启 GitHub Pages

仓库已经推到 `main` 分支，只需要：

1. 打开仓库 **Settings → Pages**。
2. **Source** 选择 `Deploy from a branch`。
3. **Branch** 选择 `main`，目录保持 `/ (root)`。
4. 保存后等待一两分钟，访问 [https://cs-lx.github.io/Inhuman/](https://cs-lx.github.io/Inhuman/) 即可。

本仓库已经包含：

- `index.html` —— 主页导航，带卡片式项目列表。
- `404.html` —— 兜底的错误页。
- `.nojekyll` —— 告诉 Pages 跳过 Jekyll，直接原样发布（省得遇到奇怪的文件名/目录名问题）。

## 本地预览

直接双击 `index.html` 可以看效果，但部分整活页面（例如 `Circle` 需要读 `imgs_config.json`）涉及 `fetch`，浏览器安全策略要求用 HTTP 访问。推荐在仓库根目录起一个简易服务器：

```bash
# Python 3
python -m http.server 8000
# 或 Node
npx serve .
```

然后浏览器访问 `http://localhost:8000/`。

## 新增一个整活页面

1. 建一个新文件夹，例如 `Foo/` 或 `Foo [BVxxxxx]/`。
2. 在里面放一个以文件夹名（去掉中括号）命名的 HTML，例如 `Foo.html`。
3. 打开 `index.html`，在 `projects` 数组里加一条：

   ```js
   {
       title: "标题",
       subtitle: "一句话副标题",
       desc: "详细介绍",
       icon: "🎲",
       folder: "Foo [BVxxxxx]",
       path: "Foo%20%5BBVxxxxx%5D/Foo.html",   // 空格和中括号要 URL 编码
       bv: "BVxxxxx"  // 没有 B 站视频就写 null
   }
   ```

4. 提交并 push，Pages 会自动更新。

## License

仅供娱乐。随便玩，别当真。
