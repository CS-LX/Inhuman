# 红圈验证 · 关卡投稿指南

想把你的整活关卡塞进 [Circle.html](./Circle.html) 的轮播池？欢迎。

---

## 五分钟流程

> 前提：你会用 git，会发 PR。

1. **Fork** [`CS-LX/Inhuman`](https://github.com/CS-LX/Inhuman) → clone 到本地。
2. **打开 [`Editor.html`](./Editor.html)**（双击或本地服务器），左上角填：
   - 作者名 = **你的 GitHub 用户名**（用作署名）
   - 作者链接 = `https://github.com/<你的用户名>`（可选）
   - Pack 名 = 一个**只含小写字母/数字/连字符**的英文短名，例如 `my-cats`
3. **左侧路径前缀改成 `imgs/<你的用户名>/`**（比如 `imgs/octocat/`）。
4. 上传图片对、拖红圈、滚轮调半径、加入列表。**至少 2 关。**
5. **导出 pack JSON**（按钮在左下角，文件名会自动 = `<pack>.json`）。
6. 在仓库里：
   ```
   Circle/imgs/<你的用户名>/    ← 把所有 PNG 放进来
   Circle/configs/<pack>.json   ← 把刚才导出的 JSON 放进来
   Circle/configs/manifest.json ← 在 "packs" 数组末尾加一行 "<pack>.json"
   ```
7. `git commit -m "feat(Circle): add pack <pack> by <你的用户名>"` → push → 在 GitHub 上发 PR。

---

## PR 描述模板（直接复制）

```markdown
### Pack 信息
- Pack 名: 
- 作者(GitHub): @
- 关卡数: 

### 整活思路
（一句话说明你的关卡在玩什么梗 / 怎么找）

### 我已确认
- [ ] 图片放在我自己的 `imgs/<我的用户名>/` 目录下
- [ ] 没有用别人未授权的素材，也不是 NSFW / 政治敏感
- [ ] 已在 `configs/manifest.json` 注册了我的 pack
```

---

## 会被打回的 PR

- 图片塞到 `imgs/default/` 或别人的目录里（**不要污染别人的命名空间**）
- 只交了 1 关
- 用了别人原创的素材而没标授权（自己画的、自己拍的、CC0 的都欢迎）
- NSFW / 政治敏感
- 整活思路那栏空着

其它的事情，相信你会判断。

---

## 一点心得

最好的红圈关：图里东西很多，但目标**真的找得到**，找到瞬间会"哦——卧槽——"。  
最差的红圈关：纯抽象，没人能找，"找不到才是整活"——那是你不会做关卡。

---

祝整活愉快。  
有疑问开 issue 问 [@CS-LX](https://github.com/CS-LX)。
