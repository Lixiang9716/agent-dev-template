# agent-dev-template

[English](README.md) | 中文

一个语言无关的 agent 开发模板仓库:治理平面让编码 agent 并行高速工作,同时由机器而不是自觉守住质量底线。

模板只提供治理平面。它不预设你的编程语言、测试框架或包管理器——你的工具链以命令槽位的形式接入 `gates.json`。每个脚本提供两份等价实现:bash 版(`scripts/*.sh`,要求 bash 5+)与 PowerShell 版(`scripts/*.ps1`,要求 pwsh 7+)。主机上有什么就用什么,无额外运行时、无安装步骤。

## Agent 开发模式

agent 对强制门禁的遵从远高于对散文式约定的遵从——这是本模板的立身观察。模式是一个循环:

1. **自由工作,机械验证。** 凡命令能检查的承诺都是 `gates.json` 里的门禁;没有任何环节依赖人的自觉。
2. **记录为什么。** 每个非平凡改动在同一个 PR 里携带一篇 Agent Note:决策、它击败的备选、后果——共享记忆让已定的决策不再被反复重议。
3. **只查改动触及的部分。** `change-scope` 报告触及面,最小充分门禁集由此而来;穷尽性归 CI。
4. **文档成对,否则变红。** 双语配对被 git blob 哈希钉住;单侧编辑无处藏身。

常设规则见 [AGENTS.md](AGENTS.zh.md);机制详解见 [docs/architecture.md](docs/architecture.zh.md)。

## 安装

任何有 curl 或 wget 的主机,一行命令完成:

```sh
curl -fsSL https://raw.githubusercontent.com/Lixiang9716/agent-dev-template/master/install.sh | sh -s -- my-project
```

Windows PowerShell:

```powershell
irm https://raw.githubusercontent.com/Lixiang9716/agent-dev-template/master/install.ps1 | iex
```

或者直接从 GitHub 模板派生新仓库:

```sh
gh repo create my-app --template Lixiang9716/agent-dev-template
```

显式步骤:

```sh
git clone https://github.com/Lixiang9716/agent-dev-template my-project
cd my-project
rm -rf .git && git init
bash scripts/gates.sh --mode all    # everything green, zero install
sh scripts/install-hooks.sh         # pre-commit, pre-push, merge driver
```

PowerShell 主机运行孪生脚本:

```sh
pwsh -File scripts/gates.ps1 -Mode all
```

两种 shell 都没有的主机只需安装 pwsh 7——一个软件包,无需容器:

```sh
winget install --id Microsoft.PowerShell   # Windows
brew install powershell                    # macOS
```

检出固定为 LF 行尾(`.gitattributes`),内容寻址门禁在所有平台上行为一致。

## 接入你的工具链

`gates.json` 把每个门禁声明为一个命令槽位。一个 Go 项目可以加:

```json
{ "id": "test", "command": ["go", "test", "./..."] }
```

任何失败时以非零退出的命令都是门禁;纯数组在两种 shell 下都会执行。见 [docs/architecture.md](docs/architecture.zh.md)。

## 里面有什么

- `gates.json` + `scripts/gates.*` —— 声明式 DAG 门禁调度器:按依赖顺序并行执行、失败传播、任何子进程启动前先做 fail-loud 校验。
- `.agents/notes/` —— Agent Notes:五段式决策记录,带生命周期与 sha256 封存的冻结归档。
- `scripts/change-scope.*` —— 以稳定 JSON 报告一次改动触及的范围。
- `scripts/verify-translation-pairing.*` —— 用 git blob 哈希钉住的双语配对。
- `.agents/skills/` —— 声明式技能(pre-push 检查、代码评审、笔记归档)。
- `scripts/verify-doc-budgets.*` —— 只降不升的词数上限。

## 来源

这些机制蒸馏自 DeepSeek Harness 仓库——其"一切皆插件"的架构与"门禁优先于散文"的公理塑造了本模板。保留:治理平面。留给你:产品平面。
