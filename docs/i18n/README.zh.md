# 双语配对契约

[English](README.md) | 中文

两种语言具有同等权威；任何一种都可以先写。一个配对是三个同级文件：`foo.md`、`foo.zh.md`、`foo.i18n.yaml`。

## Sidecar

sidecar 记录两侧在上次确认一致状态下的 git blob 哈希。编辑任意一侧后，在同一改动中重新确认：

```sh
gov verify-pairing --write docs/example.md
```

当记录的哈希不再匹配文件时门禁变红——单侧编辑永远不会静默。

## 诚实的边界

绿灯意味着配对在这些内容上被确认过一致——不代表翻译质量好。质量属于评审。
