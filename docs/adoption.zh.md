# 派生项目的第一天

[English](adoption.md) | 中文

你的项目继承的平面已经在工作:门禁、钩子与配对在第一次提交时即可运行。本指南是第一天的路线:平面给你什么、要校准什么、以及从派生到第一次 pull request 的有序步骤。常设规则见 [AGENTS.md](../AGENTS.zh.md);机制详解见 [architecture.md](architecture.zh.md)。

## 平面给你什么

- `gates.json` + `scripts/gates.*` —— 声明式调度器:凡命令能检查的承诺都是门禁;`bash scripts/gates.sh --mode all` 按依赖顺序运行它们(pwsh:`pwsh -File scripts/gates.ps1 -Mode all`)。
- `scripts/install-hooks.sh` —— 一条命令安装 pre-commit、pre-push 与配对合并驱动;钩子保持快速,穷尽性矩阵归 CI。
- `.agents/notes/` —— Agent Notes:带生命周期与冻结归档的决策记录。
- 双语配对 —— 每个面向用户的文档都是三个兄弟文件,由 git blob 哈希钉住;单侧编辑会让配对门禁变红,直到 `--write` 重新记录。
- `.agents/skills/` —— 把反复出现的 agent 工作流提炼成可执行的引导。

## 要校准什么

模板的默认值是种子值,不是定论。第一次 PR 之前,把四份清单设成你项目的实情:

1. `scripts/vocabulary.json` —— 禁用的声明状态词与你的文档需要的豁免。改它就是在改门禁:重跑词汇门禁及其测试。
2. `scripts/doc-budgets.json` —— 每篇文档的词数上限。它们只降不升;上调是需要在 PR 里论证的刻意行为。
3. `scripts/script-pairs.json` —— 双生脚本哈希。改了一个孪生脚本,就在同一变更里用 `bash scripts/verify-script-pairs.sh --write` 重新确认。
4. `AGENTS.md` —— 你的 agent 继承的常设规则。保留"门禁优先于散文"的脊梁;按你项目的需要改写。

上面任何一份清单的改动都是对平面的改动:在同一 PR 里更新所属的 Agent Note 并重跑受影响的门禁。

## notes 树是继承的种子记忆

`.agents/notes/` 随模板而来:每篇笔记记录一个决策、它击败了什么、以及后果。写你自己的笔记之前先读已有的——目录布局就是索引。你的第一篇笔记是一个文件:

```text
.agents/notes/implemented/process/2026-01-01-first-decision.md
```

头部恰好三行内容,正文以 `## Problem` 开头;implemented 笔记携带 `## Decision`、`## Alternatives considered` 与 `## Consequences`。`- Claim:` 条目必须指名 verifier、coverage 与 goal-link。`scripts/verify-agent-notes.sh` 机械地强制这个形状;写下你的第一篇笔记、跑一次门禁、并在记录该改动的同一 PR 里提交它。

## 第一天清单

```sh
gh repo create my-app --template <owner>/agent-dev-template   # or clone and re-init
cd my-app
bash scripts/gates.sh --mode all          # everything green, zero install
sh scripts/install-hooks.sh               # pre-commit, pre-push, merge driver
# calibrate the four manifests above, then:
bash scripts/change-scope.sh --base main  # the smallest sufficient check set
# make your first real change, record it as an Agent Note, and:
bash scripts/verify-translation-pairing.sh --write README.md   # after any doc edit
git add -A && git commit                  # pre-commit runs the local gates
GATES_FORCE_HEAVY=1 bash scripts/gates.sh --mode all   # the full adoption proof (CI runs it every 12h)
```

然后打开第一个 PR。Pre-push 运行 quick 模式;CI 在每次 push 上跑轻通道,每 12 小时按计划跑重通道。`scripts/adopt-plane.sh` 会在你仓库的一份副本上重跑整条路线——保持它全绿,第一天故事就始终为真。本地钩子保持轻;只有手动重跑耗时长到 SSH push 可能需要 `GIT_SSH_COMMAND='ssh -o ServerAliveInterval=60'`。
