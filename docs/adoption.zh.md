# 把平面采用进项目

[English](adoption.md) | 中文

平面用"一个动作一条命令"的方式采用。规则在 [.gov/rules.md](../.gov/rules.md)；已锁定的决策在 [decisions.md](decisions.md)。

## 安装与移除

```sh
gov init --project <path>       # 注入门禁、笔记、规则、引用行
gov uninstall --project <path>  # 精确反转；只删 init 创建的东西
```

`init` 幂等（重复运行是 no-op）且非侵入：创建 `.gov/rules.md`，仅在缺失时添加 `gates.json` 和笔记 README，向 AGENTS.md 追加一行引用，绝不覆盖项目自己的文件。

## 第一天循环

```sh
gov run --mode all      # 完整门禁 DAG，零安装
gov self-test             # 证明每个治理门禁都能拒绝违规
gov change-scope --base HEAD~1   # 最小充分检查集
```

然后做一次真实改动，记为 Agent Note，再重跑门禁。
