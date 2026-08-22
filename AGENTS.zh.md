# AGENTS.md —— 常设规则

[English](AGENTS.md) | 中文

<!-- gov:rules --> 开始工作前，先读 .gov/rules.md 并遵守其中的规则。

本仓库**就是**治理平面（agent-dev-template）：它提供 `gov init` 注入其他项目所用的门禁、笔记与规则。已锁定的设计决策见 [docs/decisions.md](docs/decisions.md)；机制说明见 [docs/architecture.md](docs/architecture.md)。

运行 `gov self-test` 验证每个治理门禁都能拒绝违规；运行 `gov run --mode all` 跑完整门禁 DAG。
