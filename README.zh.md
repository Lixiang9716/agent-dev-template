# govrail

[English](README.md) | 中文

一个语言无关的、面向 agent 驱动开发的治理平面：让 coding agent 快速并行工作，同时由机器——而非人的警惕——守住质量线。唯一运行时依赖是 Python 3。

平面提供两个机制：**门禁**（任何能被命令检查的承诺都变成机械检查）和**笔记**（每个非平凡改动记录决策、被打败的方案与后果）。双语配对让对外展示文档保持同步。

## 安装

```sh
pip install .            # 或：uv tool install . / pipx install .
```

这把 `gov` CLI 放到你的 PATH 上（纯标准库，无第三方依赖）。每个动作一个子命令：

```sh
gov init --project <path>      # 把平面注入现有项目
gov uninstall --project <path> # 精确反转
gov run --mode all             # 跑项目的门禁 DAG
gov self-test                  # 证明每个治理门禁都能拒绝
gov verify-pairing --write     # 编辑一侧后重新确认双语配对
gov change-scope --base <ref>  # 一次 diff 的最小充分检查集
```

`init` 非侵入且幂等：创建 `.gov/rules.md`，仅在缺失时添加 `gates.json` 和笔记 README，向 AGENTS.md 追加一行引用，绝不覆盖项目自己的文件。`uninstall` 精确反转。

## 内部内容

- `gov/` — Python 包：`gates`（`gates.json` 上的 DAG 运行器）、`verify_notes`（三段必填）、`verify_translation_pairing`（git blob 哈希）、`change_scope`、`self_test`、`archive_notes`。
- `gov/templates/` — `gov init` 注入项目所用的规则、默认 `gates.json` 和笔记格式。
- `.gov/rules.md` — 规则的唯一事实源。
- `.agents/notes/` — 决策记录格式与生命周期。

## 出处

机制蒸馏自 DeepSeek Harness 仓库，其"门禁高于散文"公理塑造了本模板。保留：治理平面。留给你：产品平面。已锁定的设计决策见 [docs/decisions.md](docs/decisions.md)。
