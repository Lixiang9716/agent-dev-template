# 治理架构

[English](architecture.md) | 中文

模板分离两个平面。**治理平面**——门禁、笔记、配对、范围——是 Python 3 实现的、语言无关的机制，只作用于 git、Markdown 和 JSON。**产品平面**是你的任意语言代码，仅通过 `gates.json` 里的命令槽接入。

## 门禁 DAG

`gov run --mode <name>` 读取 `gates.json` 并运行一个模式。一个门禁 = 一个"非零退出即失败"的命令数组；`needs` 构成 DAG（门禁在所有依赖通过后才启动，依赖阻塞失败时标 `SKIP`），`concurrency` 限制并行度。启动任何子进程前先校验整个配置：重复 id、未知 needs、循环都会带名字 abort（退出码 2）。

每个门禁落到五种结局之一——`PASS` / `FAIL` / `TIMEOUT` / `MISSING`（可执行文件不存在）/ `SKIP`——`allowFailure: true` 让该门禁的失败仅作观察。退出码 0 = 全绿，1 = 有阻塞失败。

## 知识平面

- **Agent Notes** 承载决策（`implemented/` 然后冻结的 `archived/`）。`gov verify-notes` 强制三段必填：`## Problem`、`## Decision`、`## Alternatives considered`（`## Consequences` 可选）。
- **双语配对** 承载对外展示文档：`foo.md` + `foo.zh.md` + `foo.i18n.yaml`，用 git blob 哈希钉死。`gov verify-pairing` 让单边编辑失败。
- **`gov self-test`** 为每个治理门禁跑一个拒绝用例——证明每个门禁都能拦住所声称的违规，所以没有空转脚本。

## 采用：gov init / uninstall

`gov init` 把平面注入项目：复制 `.gov/rules.md`（规则的唯一事实源），仅在缺失时创建 `gates.json` 和笔记 README，向 AGENTS.md 追加一行引用，并把创建了什么记进 `.gov/manifest.json`。`gov uninstall` 读取该 manifest 精确反转 init——只删 init 创建的东西，绝不碰项目自己的文件。两者都幂等。

## 平面成长

治理平面是地板，不是天花板。成长是事件驱动的，不是灵感驱动的：

| 触发 | 落点 |
|---|---|
| 缺陷类别上线且重发现成本高 | `docs/postmortem/` 条目；其护栏蒸馏成门禁 |
| 某约定第三次被手工执行 | 一个技能，其 description 即触发条件 |
| 某散文承诺变得可机械检查 | `gates.json` 里一个新门禁 + 拒绝测试 |
| 一个非平凡决策被做出 | 同一改动里一条 Agent Note |
