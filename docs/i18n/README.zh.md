# 双语配对契约

[English](README.md) | 中文

两种语言具有同等权威;任何一种都可以先写。一个配对是三个同级文件:`foo.md`、`foo.zh.md`、`foo.i18n.yaml`。

## Sidecar

sidecar 记录两侧在上次确认一致状态下的 git blob 哈希。编辑任意一侧后,在同一改动中重新确认:

```sh
node scripts/verify-translation-pairing.mjs --write docs/example.md
```

当记录的哈希不再匹配文件时门禁变红——单侧编辑永远不会静默——结构签名发散(标题数、列表数、表格行数、链接目标、代码围栏)同样变红。代码围栏跨语言逐字节相同。

## 合并

`scripts/translation-pairing-merge.mjs` 在只有一侧前进时自动解决 sidecar 冲突;两侧都前进时留下普通冲突。任何合并后重跑门禁。

## 诚实的边界

绿灯意味着配对在这些内容上被确认过一致——不代表翻译质量好。质量属于评审。
