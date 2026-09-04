# 治理架构

[English](architecture.md) | 中文

模板分离两个平面。**治理平面**——门禁、笔记、配对、范围——是 Python 3 实现的、语言无关的机制，只作用于 git、Markdown 和 JSON。**产品平面**是你的任意语言代码，仅通过 `gates.json` 里的命令槽接入。

## 门禁 DAG

`gov run --mode <name>` 读取 `gates.json` 并运行一个模式。一个门禁 = 一个"非零退出即失败"的命令数组；`needs` 构成 DAG（门禁在所有依赖通过后才启动，依赖阻塞失败时标 `SKIP`），`concurrency` 限制并行度。启动任何子进程前先校验整个配置：重复 id、未知 needs、循环都会带名字 abort（退出码 2）。

不带 `--mode` 时，若配置了顶层 `defaultMode` 则运行它（注入模板自带 `"defaultMode": "all"`）——改 mode 就是改默认运行集。`enabled: false` 把门禁停在一切运行之外，输出一行 `DISABLED`，"下线"留在配置里而不是删除定义。

门禁用 `paths` glob（`**` 跨目录）声明自己覆盖的范围：`gov run --base <ref>` 按 diff 选中 paths 命中的门（无 paths 的门永远相关）并报告哪些门出了范围——最小充分集出自同一事实源，`gov change-scope` 的建议也读同一份 `paths`。`gov run --gate <id>` 单门重跑。

模板还自带一个查内容而非只看退出码的门：`gov verify-conflict-markers`（issue #104/D38）读变更文件的工作区内容，发现行首的 git 冲突标记即以 `file:line` 点名失败——git 拒绝自查的那种 rebase 失败模式由门禁接管；确实要写字面量的行追加令牌 `gov:ignore-marker` 即豁免，孤立的裸 `=======`（Markdown 标题下划线）不算标记。

每个门禁落到五种结局之一——`PASS` / `FAIL` / `TIMEOUT` / `MISSING`（可执行文件不存在）/ `SKIP`——`allowFailure: true` 让该门禁的失败仅作 advisory：结局行与输出带 `advisory` 标记照常报告，退出码保持 0。通过但有输出的门禁以 `(passed with output)` 块保留其末尾几行——"有话说的通过"绝不被静默（D20）。退出码 0 = 全绿，1 = 有阻塞失败；阻塞失败末尾追加摘要块：哪个门挂了 + 首行输出 + 单门重跑命令。

## 知识平面

- **Agent Notes** 承载决策（`implemented/` 然后冻结的 `archived/`）。`gov verify-notes` 强制三段必填：`## Problem`、`## Decision`、`## Alternatives considered`（`## Consequences` 可选）。`gov verify-note-presence` 检查规则 2 可观察的那一半——diff 触及行为面而无 note 变更时警告（带规则出处）；`--strict` 升级为拦截。其 base 是 auto：脏树审查工作树，干净树审查领先 upstream 的提交（无 upstream 则最后一个提交）——push 钩子与 CI 永远看到干净树，因此审查的是被推送的工作而非空 diff。记忆的读侧：`gov recall <terms>` 跨笔记、决策、postmortem 检索（按命中位置排序）；`gov audit-notes` 报机械新鲜度信号——世界已不再满足的引用——作为归档技能判断的证据。
- **双语配对** 承载对外展示文档：源 `foo.md` + 译文侧 + `foo.i18n.yaml` 记录，用 git blob 哈希钉死两侧（并钉住译文侧文件名）。命名约定是 `.gov/pairing.json` 里的配置（`include`、`counterparts`、`exclude`）；不符合任何约定的配对用 `gov verify-pairing --write en:<path> zh:<path>` 显式登记。单边编辑失败。
- **`gov self-test`** 为每个治理门禁跑一个拒绝用例——证明每个门禁都能拦住所声称的违规，所以没有空转脚本。它是工具自身的回归，进模板默认运行（`governance` 模式保留为单跑自检的快捷方式）：模板 CI 装的是未钉版本的 govrail，工具自身的冒烟测试因此在采用者侧运行。每个已启用门禁必须属于某个 mode——停靠只有 `"enabled": false` 这一条响的机制（DISABLED 行）；`gov run --every-gate` 是显式全矩阵。
- **评审量规** 承载门禁查不了的判断标准：[review-rubric.md](review-rubric.zh.md) 对 PR 逐条带证据判定；每条的 `Gate candidate` 字段写明承诺可机械化后是否毕业成门禁。`gov verify-rubric` 检查量规自身的结构——永不检查判断本身。

## 采用：gov init / uninstall

`gov init` 把平面注入项目：复制 `.gov/rules.md`（规则的唯一事实源），仅在缺失时创建 `gates.json`、笔记 README 与 agent 技能（recall-first、pre-push-checks、code-review、archive-agent-notes）——项目自己的技能绝不被覆盖——向 AGENTS.md 追加一行引用，并把创建了什么记进 `.gov/manifest.json`。`gov uninstall` 读取该 manifest 精确反转 init——只删 init 创建的东西，绝不碰项目自己的文件。两者都幂等。

执行路径是显式选装：`gov init --hooks` 装 pre-push 钩子跑门禁 DAG（外来的 pre-push 绝不覆盖——加装在任何变更之前预检、fail loud），`gov init --ci` 仅在文件不存在时生成 `.github/workflows/gov.yml` 跑 `gov run`。两者都记入 manifest，`uninstall` 精确反转。

新装项目首跑不红：pairing 门禁以 advisory 落地（`allowFailure: true`），报告哪些文档待 baseline；`gov verify-pairing --write` 记录存量配对后，摘除 `allowFailure` 即升级为强制。`init` 会打印这些 next steps。

## 平面成长

治理平面是地板，不是天花板。成长是事件驱动的，不是灵感驱动的：

| 触发 | 落点 |
|---|---|
| 缺陷类别上线且重发现成本高 | `docs/postmortem/` 条目；其护栏蒸馏成门禁 |
| 某约定第三次被手工执行 | 一个技能，其 description 即触发条件 |
| 某散文承诺变得可机械检查 | `gates.json` 里一个新门禁 + 拒绝测试 |
| 一个非平凡决策被做出 | 同一改动里一条 Agent Note |
