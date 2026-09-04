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

## 漂移在提交时抓到，而不是推送时

pre-push 拦截有效，但忙碌分支上每次对编辑都先付一次被阻塞的 push
（issue #110 的实证）。装上可选的 pre-commit 钩子——只对暂存文件跑
廉价内容门：

```sh
gov init --hooks --pre-commit   # 加装项；单用 --hooks 仍是 push 阶段
```

同样的编辑现在早一个阶段、在 `git commit` 时失败，内联同款点名修
复——照跑、重新暂存，提交直接落地，不经 push 往返：

```
docs/foo.md: out of sync — re-confirm: gov verify-pairing --write docs/foo
verify_translation_pairing: 1 violation(s) in 1 staged pair(s)
```

暂存里没有配对文件？钩子保持安静。觉得 commit 钩子侵入的仓库不传
`--pre-commit` 即可——提交阶段零变化，pre-push 模型原样。

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

## 并行分支都要"下一个 D 号"

```sh
gov decision next --base origin/master   # 合并后历史会显示的号
gov decision add --from draft.md          # 原子追加，写前校验
gov verify-decisions --base origin/master
```

两个 worktree 从同一基线各算"下一个空闲号"都会拿到 D39；`--base`
并入基线分支已落地的号，门禁运行时点名冲突（`D39: number
collision … 用 gov decision next --base 重编号）而不是让重复行
悄悄合并。单文件格式的追加是原子的（临时文件+替换），但跨
worktree 合并仍是文本冲突——配置 `.gov/decisions.json`
`{"path": ".gov/decisions", "format": "dir"}`（一决策一文件）后
追加即新增文件：并行分支合并零冲突。

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

## 编排多个 worktree 而不 cd

```sh
gov -C ../wt-x run --base master   # 门禁跑在 wt-x 那棵树，不是当前树
gov -C ../wt-x doctor
```

`-C <path>`（或 `--path`，置于子命令之前；可像 git 一样链式）在派发
前按值切换目录，输出头部点名解析出的 work-tree 根——跑错树一眼可
见，而不只是"合法"。路径不存在则大声失败（#121）。自带 `--path`
的子命令（verify-decisions、verify-rubric）不受影响：它们的
`--path` 指文件，且写在命令之后。

## 读 trend 的 mover

运行默认记录（`.gov/history/`，已 gitignore）。`gov trend` 按窗口
对半比较每门 p50；mover（`×1.8 ↑`）是要调查的问题，不是结论：

```sh
gov trend --gate tests --base v1.2.0   # 该版本前后对比
```

## 多 agent 一个仓库——这些运行是谁的？

给运行打 `--tag`（或导出 `GOV_CALLER`；旗标优先），标签以调用方
自由文本落入 `.gov/history/gates.jsonl`。`gov trend --by-tag` 按
caller 切分窗口——每个标签的 mover 与稳定门各自报告，未打标的
运行归入 `(untagged)`，不打标则记录形状与从前完全一致（#120）：

```sh
gov run --tag subagent-3        # 或：GOV_CALLER=subagent-3 gov run
gov trend --by-tag              # 按 caller 的前后半窗口 p50 对比
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
