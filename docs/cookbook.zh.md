# 食谱 —— 任务、命令、预期输出

[English](cookbook.md) | 中文

食谱按任务组织：症状或目标、命令、好的输出长什么样。参考手册在
README；这一层回答"现在该做什么"。

## 安装与第一天

```sh
gov init --project .            # 规则、门禁、笔记、技能落地
gov doctor                      # PATH、python、钩子、gates schema——健康？
gov run                         # pairing 以 advisory 运行直到 baseline
```

新装不该红。有文档要配对时：

```sh
gov verify-pairing --write      # 全部配对建立基线（部分成功：能记的记，
                                # 不能记的报）
```

## 改完文档 pairing 变红了

报错自带修复——照抄即可：

```
docs/foo.md: out of sync — re-confirm: gov verify-pairing --write docs/foo
(the en side last moved in a1b2c3d, confirmed 2026-09-01T10:00:00+00:00)
```

`--write <stem>` 只重基线指名的对。括号里说明哪侧在哪个提交动的、
何时确认的——先核对翻译再确认，别反过来。

## 加一个门禁的完整闭环

1. 在 `gates.json` 定义（未知键即报错——笔误无法静默停靠）：

```json
{"id": "source-limits", "command": ["./check_limits.sh"],
 "paths": ["src/**", "eval/**"]}
```

2. 证明它能拒绝——`.gov/rejections/` 下的拒绝用例，shebang 在首行、
   gate 声明在前五行内：

```sh
#!/bin/sh
# gate: source-limits
# 造一个超限模块，断言门禁变红，还原
...
```

3. 查账本：`gov self-test --scope project` 末尾应是
   `source-limits(1)`——而不是 `NONE — rule 6`。

## rebase 把冲突标记带进了提交

症状：rebase 中途 `git add` 了仍带 `<<<<<<<` / `=======` / `>>>>>>>`
块的文件，`git rebase --continue` 一声不吭照单提交——git 分不清真
标记与被引用的标记，只能沉默。conflict-markers 门随模板 all 模式
自带，读的是变更文件的内容：

```sh
gov verify-conflict-markers            # 变更文件 vs auto 基线
gov verify-conflict-markers --staged   # 只查暂存区——pre-commit 轻量版
```

diff 里存在带标记文件时的预期输出（exit 1）：

```
doc.md:3: conflict marker '<<<<<<<' — resolve the merge, or append 'gov:ignore-marker' to exempt a deliberate literal
doc.md:5: conflict marker '======='
doc.md:7: conflict marker '>>>>>>>'
verify_conflict_markers: 3 marker(s) in 1 file(s) — git will not police its own conflict text; the gate does (D38)
```

逃生门：确实要写字面量（引用标记的测试夹具、讲合并的文档）时，
在该行行尾追加令牌 `gov:ignore-marker` 即可通过。孤立的裸
`=======`（Markdown H1 setext 下划线）不算标记；只有同文件存在
兄弟标记时才计数（D38）。

## 实验装置不是运行时代码

`.gov/surfaces.json`：

```json
{"eval/**": {"surface": "experiments", "gates": ["source-limits"]}}
```

此后 eval-only 改动的 `gov change-scope` 只建议
`source-limits`——产品面零噪音。

## 评审一份 PR

```sh
gov review --base origin/main --grade
```

一条命令：档案（范围、笔记、recall、量规），然后交互打分
（`p`/`f`/`s`/`q`；`f` 追问证据），然后裁决块——逐条行、blockers、
`verdict: approve` 或 `request changes`。人裁决；机器誊写。

## 写一篇笔记

```sh
gov note new --class process --ref D6 "为什么选 x"
gov note check        # 格式 + 路径 + 悬空 D 引用，pre-commit 级轻量
```

错的 class 或悬空的 D 引用在投入文字之前就被拒。没有决策表时
D 引用明示"未核对"——绝不静默跳过。

## 决策表

`gov verify-decisions` 守卫编号（唯一、连续）、备选（每条 D 记录
打败了什么）、并报告孤儿（无笔记引用——信息性）。上下文可能过期
的决策带 `review-by: 2027-01-01`；过期打 review-due 提示。

## 模板演进了——先看，再采纳

```sh
gov init --upgrade            # 逐文件 diff；绝不写入
gov init --adopt all          # 只落地缺失的模板文件
gov init --adopt-new gates.json  # 把新 shipped 门增量合入定制版
                                 # gates.json（按 gate id）
gov whatsnew                  # 自你的 init 版本以来新增了什么
```

修改类文件仍归你手工合并（两步哲学）；纯新增一条命令落地；定制版
gates.json 可增量吸收新 shipped 门——本地门原样保留，同名冲突大声
拒绝（D39）；`--upgrade --json` 让 agent 程序化决策。

## 读 trend 的 mover

运行默认记录（`.gov/history/`，已 gitignore）。`gov trend` 按窗口
对半比较每门 p50；mover（`×1.8 ↑`）是要调查的问题，不是结论：

```sh
gov trend --gate tests --base v1.2.0   # 该版本前后对比
```

## 长会话被未跟踪文件警告淹没

```sh
gov verify-note-presence --staged     # 只看 index；干净即静默
```

超五条折叠（`…and N more`）。

## 环境感觉不对劲

```sh
gov doctor
```

规则 5 风格点名问题：gov 不在 PATH、钩子不可执行、门禁命令解析
不到、schema 笔误、决策表解析失败。
