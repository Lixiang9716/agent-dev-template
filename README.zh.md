# agent-dev-template

[English](README.md) | 中文

一个语言无关的 agent 开发模板仓库:治理平面让编码 agent 并行高速工作,同时由机器而不是自觉守住质量底线。

模板只提供治理平面。它不预设你的编程语言、测试框架或包管理器——你的工具链以命令槽位的形式接入 `gates.json`。唯一的运行时要求是 Node.js 20+(治理脚本本身使用;无 npm 依赖、无安装步骤)。

## 里面有什么

- `gates.json` + `scripts/gates.mjs` —— 声明式 DAG 门禁调度器:按依赖顺序并行执行、失败传播、任何子进程启动前先做 fail-loud 校验。
- `.agents/notes/` —— Agent Notes 体系:五段式决策记录,带生命周期(`proposed` / `implemented` / `rejected`)与 sha256 封存的冻结归档。由 `scripts/verify-agent-notes.mjs` 与 `scripts/archive-agent-notes.mjs` 校验。
- `scripts/change-scope.mjs` —— 以稳定 JSON 报告一次改动触及的范围,让 agent 选择最小充分检查集,而不是条件反射地全量跑。
- `scripts/verify-translation-pairing.mjs` —— 双语文档配对(`foo.md` + `foo.zh.md` + `foo.i18n.yaml`),用 git blob 哈希保证一致性;单侧编辑会让门禁变红。
- `.agents/skills/` —— 声明式技能(pre-push 检查、代码评审、笔记归档),其 description 就是触发条件。
- `scripts/verify-doc-budgets.mjs` —— 只降不升的词数上限。

## 快速开始

```sh
git clone <this-repo> my-project
cd my-project
rm -rf .git && git init
node scripts/gates.mjs --mode all   # everything green, zero install
sh scripts/install-hooks.sh         # pre-commit, pre-push, merge driver
```

非 Node 项目可以用容器跑同一套门禁:

```sh
docker run --rm -v "$PWD":/w -w /w node:20 node scripts/gates.mjs --mode all
```

## 接入你的工具链

`gates.json` 把每个门禁声明为一个命令槽位。一个 Go 项目可以加:

```json
{ "id": "test", "command": ["go", "test", "./..."] }
```

任何失败时以非零退出的命令都是门禁。见 [docs/architecture.md](docs/architecture.zh.md)。

## 来源

这些机制蒸馏自 DeepSeek Harness 仓库,其治理公理是:agent 对强制门禁的遵从远高于对散文式约定的遵从。常设规则见 [AGENTS.md](AGENTS.zh.md)。
