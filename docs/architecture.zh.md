# 治理架构

[English](architecture.md) | 中文

模板把两个平面分开。治理平面——门禁、笔记、配对、范围——是语言无关的机制,只操作 git、Markdown 和 JSON。产品平面是你的任何语言的代码;它只通过 `gates.json` 的命令槽位接入。

每个治理脚本提供两份等价实现:bash 版(`scripts/*.sh`,要求 bash 5+)与 PowerShell 版(`scripts/*.ps1`,要求 pwsh 7+)。两者读取同一个 `gates.json`,产出同一套词汇表;CI 两者都跑。孪生配对一起确认:`scripts/script-pairs.json` 钉住两侧的 blob 哈希,漂移的配对会让门禁变红,直到同一改动内用 `--write` 重新确认——重确认就是"孪生文件已被考虑"的显式凭证。门禁槽位是纯命令数组(两种 shell 下相同)或按 shell 的变体;变体对象必须写全封闭集合里的每种 shell——缺变体直接中止,而不是在那个平台上静默跳过。

## 门禁调度器

`scripts/gates.sh --mode <name>`(pwsh:`scripts/gates.ps1 -Mode <name>`)读取 `gates.json` 并运行一个模式(`all|quick|docs`)。门禁通过 `needs` 构成 DAG:依赖全部通过才启动;失败的依赖会让下游标记为 skipped 并记录原因,而不是照常运行。整个配置在任何子进程启动前先被校验——重复 id、未知依赖、依赖环都会带着肇事名字中止。`allowFailure: true` 让门禁的失败不进入阻塞集合,供观察性通道使用。

并发默认取 CPU 数,可用 `GATE_CONCURRENCY` 封顶。输出按门禁捕获:通过的门禁保持静默(设 `GATE_VERBOSE=1` 可见),失败的门禁打印命令、结果与输出。

## 是槽位,不是框架

门禁是任何失败时以非零退出的命令数组。语言相关的工作——测试、覆盖率、类型检查、lint——以槽位形式声明一次,由 CI 永久运行。治理脚本自托管了这个模式:它们自己的测试套件(`scripts/self-test.sh`、`scripts/self-test.ps1`)就是 `self-test` 门禁,每个移植一份套件。

## 知识平面

Agent Notes 承载决策(`proposed` / `implemented` / `rejected`,再到封存的 `archived/`);校验器强制五段式格式,归档用 sha256 封存内容。双语配对承载面向用户的文档;配对校验器用 git blob 哈希钉住两侧。尸检报告承载失败;其护栏沉淀为门禁。[docs/tiers.md](tiers.zh.md) 把每个事实映射到它唯一的家。

## 生长治理平面

治理平面是地板,不是天花板:派生项目用自己的历史去扩展它,而生长由事件驱动,绝不靠灵感驱动。

| 触发器 | 落点 |
|---|---|
| 某类缺陷已交付且重新发现代价高昂 | `docs/postmortem/` 尸检;其护栏蒸馏为一道门禁 |
| 某个约定第三次靠人工执行 | `.agents/skills/` 技能,其 description 就是触发条件 |
| 散文里的承诺变得可机检 | `gates.json` 新门禁 + 拒绝测试(规则 3) |
| 发生非平凡决策 | 同一 PR 内的 Agent Note(规则 2) |
| 新事实需要安家 | 先定层级([tiers.md](tiers.zh.md)),只落一次 |

封闭集合(笔记类、生命周期)靠审慎行为增长,校验器与笔记 README 同步更新。词数预算约束生长:新增一个家,就为它喂一个上限。

## 检查点纪律

跨重启的长任务维护一份编号、仅追加的检查点记录。每条检查点携带三个字段:verifier(谁核验了它)、coverage(覆盖什么)、goal-link(服务哪个 Goal/Core)。编号顺序 1..N,从不改写或重排;恢复从链完好的最高编号条目续行;链损坏的条目不是恢复点。
