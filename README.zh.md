# govrail

[English](README.md) | 中文

[![CI](https://github.com/Lixiang9716/govrail/actions/workflows/ci.yml/badge.svg)](https://github.com/Lixiang9716/govrail/actions/workflows/ci.yml)
[![PyPI](https://img.shields.io/pypi/v/govrail.svg)](https://pypi.org/project/govrail/)
[![Python](https://img.shields.io/pypi/pyversions/govrail.svg)](https://pypi.org/project/govrail/)
[![GitHub Repo stars](https://img.shields.io/github/stars/Lixiang9716/govrail)](https://github.com/Lixiang9716/govrail/stargazers)

一个语言无关的、面向 agent 驱动开发的治理平面：让 coding agent 快速并行工作，同时由机器——而非人的警惕——守住质量线。唯一运行时依赖是 Python 3。

平面提供两个机制：**门禁**（任何能被命令检查的承诺都变成机械检查）和**笔记**（每个非平凡改动记录决策、被打败的方案与后果）。双语配对让对外展示文档保持同步。

## 它改变了什么

| 没有 govrail | 有 govrail |
|---|---|
| Agent 靠"自觉"守规则，没人强制 | 每个可检查的承诺都变成会大声失败的门禁 |
| "为什么这么做"被遗忘或反复争论 | 每个决策都有一条带"被否方案"的笔记 |
| 采用工具意味着重构或引入新运行时 | 一条命令、零重构：`gov init` |

看一个被治理的项目长什么样：[examples/demo-project](examples/demo-project)。

## 安装

```sh
pip install govrail        # 或：uv tool install govrail / pipx install govrail
```

这把 `gov` CLI 放到你的 PATH 上（纯标准库，无第三方依赖）。每个动作一个子命令：

```sh
gov init --project <path>      # 把平面注入现有项目
gov init --project <path> --hooks --ci  # 同时安装 pre-push 钩子与 CI
gov uninstall --project <path> # 精确反转
gov run                        # 跑默认模式（defaultMode）的门禁 DAG
gov run --base HEAD~1          # 只跑 paths 命中本次 diff 的门
gov run --gate pairing         # 单门重跑
gov self-test                  # 证明每个治理门禁都能拒绝
gov verify-pairing --write     # 编辑一侧后重新确认双语配对
gov verify-pairing --write en:docs/a.md zh:docs/a_CN.md  # 登记任意命名的配对
gov verify-note-presence       # 非平凡 diff 未带 Agent Note 时警告
gov verify-rubric              # 检查评审量规的结构
gov change-scope --base <ref>  # 一次 diff 的最小充分检查集
```

`init` 非侵入且幂等：创建 `.gov/rules.md`，仅在缺失时添加 `gates.json` 和笔记 README，向 AGENTS.md 追加一行引用，绝不覆盖项目自己的文件。`uninstall` 精确反转——包括 `--hooks`/`--ci` 装的钩子与 workflow。新装首跑不红：pairing 门禁以 advisory 落地，`gov verify-pairing --write` 为存量文档建立基线后，摘除 `allowFailure` 即升级为强制。`enabled: false` 让门禁下线而不删除定义。

## 内部内容

- `gov/` — Python 包：`gates`（`gates.json` 上的 DAG 运行器）、`verify_notes`（三段必填）、`verify_translation_pairing`（git blob 哈希）、`verify_note_presence`、`verify_rubric`、`change_scope`、`self_test`、`archive_notes`。
- `gov/templates/` — `gov init` 注入项目所用的规则、默认 `gates.json` 和笔记格式。
- `.gov/rules.md` — 规则的唯一事实源。
- `.agents/notes/` — 决策记录格式与生命周期。
- `docs/review-rubric.md` — PR 如何被评审：门禁查不了的标准，逐条判定。

## 出处

机制蒸馏自 DeepSeek Harness 仓库，其"门禁高于散文"公理塑造了本模板。保留：治理平面。留给你：产品平面。已锁定的设计决策见 [docs/decisions.md](docs/decisions.md)。

## Star 历史

![Star History](https://raw.githubusercontent.com/Lixiang9716/govrail/stats/stars.svg)
