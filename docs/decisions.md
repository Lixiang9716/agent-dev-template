# 治理模板 · 待决清单

核心诉求 B：让 agent 开发的质量靠机器（门禁）守住、决策靠记录（笔记）留下，且轻到能一条命令装进任何项目。

待决项按依赖顺序排列，状态分 `待定` / `已决`。

---

## D0 — gate 和 note 的分界（全局，先定）

- **问题**：一个承诺，什么时候做成 gate（机械检查），什么时候写成 note（决策理由）？重叠了怎么办？
- **选项**：
  - (a) 严格二分：能命令检查 → gate，否则 → note，二者不重叠
  - (b) 先 note 后 gate：先记决策，等能机械检查了再升级成 gate
- **倾向**：(b)，但需精确化"重叠"的含义（见下）
- **卡住什么**：门禁"该做几个"、笔记"该写多少"都以此为准
- **状态**：已决
- **决定**：note 和 gate 是两条正交的轴——note 回答"为什么有这条规则"（历史理由，人判断），gate 回答"这条规则现在为真吗"（机械检查，可重复）。同一规则可同时拥有 note（记理由）和 gate（守状态），各司其职不重叠。判别测试：①"这个承诺现在为真吗？"能用一条命令回答 → gate；②"为什么有这个承诺？"答案是历史理由 → note。生命周期：决策先以 note 诞生，后果变得可机械检查时 gate 随之诞生，note 不删（理由永不过期）。

## D1 — gates.json 的最小 schema

- **问题**：`{ id, command }` 够吗？
- **选项**：(a) 只 id+command（顺序跑）；(b) 加 needs（DAG）；(c) 加 modes（分组）
- **倾向**：(a)（后被推翻：全字段都要 + Python 单实现）
- **卡住什么**：runner 的复杂度
- **状态**：已决
- **决定**：开发者优先，**用 Python 3 单实现，删除 `{sh, pwsh}` 变体对象**。完整 schema：顶层 `{ modes, concurrency, gates[] }`；每个 gate 含 `id`（唯一非空）+ `command`（**纯 argv 数组，单态**）+ 可选 `label`/`needs`/`timeoutMs`/`allowFailure`。配置期校验重复 id、未知 needs、循环依赖，三者 fail loud。runner 与全部治理脚本用 Python 3；安装前提 = Python 3。

## D2 — "失败大声"的精确契约

- **问题**：退出码、输出格式、未知命令/缺失文件各怎么处理？
- **选项**：(a) 统一约定（非零退出 + 打印失败 gate id + 命令输出）；(b) 结构化 JSON 报告
- **倾向**：(a) 起步，JSON 后加；"未知命令/缺失文件 = 失败并报名字"必须写死
- **卡住什么**：门禁与"一串 shell 命令"的本质区别
- **状态**：已决
- **决定**：门禁五种结局 `PASS`/`FAIL`/`TIMEOUT`/`MISSING`/`SKIP`。退出码 `0`=全绿、`1`=有阻断失败、`2`=配置无效（启动前校验）。输出：每 gate 一行结局 + FAIL 附命令输出尾部 + 汇总行；通过静默（`--verbose` 全量）。默认 run-all（尊重 DAG），`--fail-fast` 可选。MISSING（命令不存在）单独点名，与 FAIL 严格区分。

## D3 — 拒绝测试的地位

- **问题**：每个门禁必带"引入违规 → 变红"的测试，还是可选？
- **选项**：(a) 核心，必带；(b) 可选，后加
- **倾向**：(a) 核心
- **卡住什么**：B 的"可信"是否成立
- **状态**：已决
- **决定**：拒绝测试是核心，但**只约束治理平面自己的门禁**（verify_notes 等）。每个治理门禁带一个拒绝用例（引入违规 → 断言变红 → 还原），由一个 meta-gate `self-test` 统一执行。项目自己的门禁（`go test` 等）不要求拒绝测试——其工具语义已保证拒绝。这是"门禁"与"空转脚本"的分水岭。
- **延伸（查结果不查过程）**：门禁失败信息必须带"规则出处"（指向 `.gov/rules.md`）。新增 `verify-note-presence` 软门禁：diff 触及代码/契约但无新增 note → **警告不阻断**。原理：不查"读没读规则"，查"做没做对"，失败信息逼 agent 去读——"不读就修不好"，比自毁行/读回执可靠（查产出、不可游戏、不引入状态变异）。

## D4 — 笔记三段 vs 五段

- **问题**：`Problem / Decision / Alternatives` 够吗，要不要 `Consequences`？
- **选项**：(a) 三段核心，Consequences 可选；(b) 五段全必填
- **倾向**：(a)
- **卡住什么**：笔记格式校验器写多严
- **状态**：已决
- **决定**：必填三段 `## Problem`（动机，独立成立）+ `## Decision`（决策，现在时）+ `## Alternatives considered`（被否方案，防重新争论）。`## Consequences` 为可选段：允许存在、不强制、不校验，等"成本"维度值钱再升格必填。校验器只认三段必填，三段缺一变红。

## D5 — 笔记生命周期最小集

- **问题**：`implemented + archived` 够吗，要不要 `proposed/rejected`？
- **选项**：(a) 只 implemented + archived；(b) 全四态
- **倾向**：(a)
- **卡住什么**：目录结构 + 归档规则
- **状态**：已决
- **决定**：最小集 = `implemented/` + `archived/`（冻结、sha256 封存、永不编辑）。`rejected/` 后加——触发条件：真的有人重新提议被否方案（事件驱动）。`proposed/` 排除——是规划工作流，非决策记忆。回退边界：`implemented` 可改，`archived` 不可改（是证据不是状态）。

## D6 — "非平凡改动"的边界

- **问题**：什么改动必须写 note？
- **选项**：(a) 宽松（改变行为/架构/跨文件契约/维护者可能重新审视的决定）；(b) 严格（机械改动也写）
- **倾向**：(a)
- **卡住什么**：规则 2 是空话还是有牙齿
- **状态**：已决
- **决定**：非平凡改动 = 改变可观察行为 / 架构结构 / 跨文件契约 / 流程工具 / 测试策略，或"维护者可能重新审视"的决定。豁免 = 纯机械/局部（错字、格式、局部重命名、注释同步）。操作化判据：一个月后的维护者看到 diff 会问"为什么"吗？会问就写 note，不问就豁免。防两端：少写丢决策，多写造疲劳。

---

## 怎么交付（③简易安装 + ④轻松适配）

## D7 — 安装载体

- **问题**：一条命令是什么形态？
- **选项**：(a) pip 包 + `init` 子命令；(b) 单文件脚本
- **倾向**：(a)
- **卡住什么**：安装/升级/卸载的体验
- **状态**：已决
- **决定**：Python CLI 包（pip/pipx 可装），含 `init` 子命令——`init` 把 gates.json 模板、笔记格式、规则注入目标项目。工具装一次、项目文件每项目注入一次。卸载 = `pipx uninstall`，天然可回退。包名待定。

## D8 — 追加不覆盖的合并语义

- **问题**：目标项目已有 AGENTS.md / gates.json 时，怎么合并？冲突怎么办？
- **选项**：待钉
- **倾向**：待钉
- **卡住什么**：适配现有项目是否真"轻松"
- **状态**：已决
- **决定**：不向 AGENTS.md 追加规则内容，改为——① 创建独立规则文件 `.gov/rules.md`；② 在 AGENTS.md 加**一行命令式引用**（幂等：已有则跳过）。规则永不与项目规则合并，语义冲突在结构上消失。选分叉 A（本地文件），不做真外部引用（依赖工具解析与联网）。结构性冲突（引用行已存在）机械报，语义冲突靠"独立文件 + 并列存在 + 提示人工"兜底，init 不仲裁。

## D9 — 幂等

- **问题**：重复 install 是否安全 no-op？
- **选项**：待钉
- **倾向**：待钉
- **卡住什么**：误操作是否造成重复
- **状态**：已决
- **决定**：幂等 = 检测"已初始化"标记（AGENTS.md 的引用行 或 `.gov/` 目录存在）→ 已存在则 no-op，打印"已初始化，版本 X"。重复 `gov init` 不产生任何变更。

## D10 — 回退契约

- **问题**：uninstall 如何精确还原 install 做的事？
- **选项**：待钉
- **倾向**：待钉
- **卡住什么**：可回退是否成立
- **状态**：已决
- **决定**：`gov uninstall` 精确反转 init——① 删 `.gov/` 目录（含 manifest + rules.md）；② 移除 AGENTS.md 里的引用行（标记可识别）；③ 按 manifest 删除 init 创建的项目文件（**仅 create-if-missing 的**，项目原有的绝不碰）。`.gov/manifest.json` 记录 init 创建了什么，uninstall 读它反转。

## D11 — 默认运行集与 gate 下线（gates.json schema 增补）

- **问题**：`gov run` 不带 `--mode` 时跑全部 gates，`modes.all` 只是可显式选择的名字而非默认集——从 modes.all 摘掉某 gate 后默认运行照旧；想下线一个 gate 只能物理删除定义，丢失配置历史与"未来重新启用"的意图。
- **选项**：(a) 魔法默认：存在名为 `all` 的 mode 即默认；(b) 顶层 `defaultMode` 显式声明；(c) per-gate `enabled: false`
- **倾向**：(b)+(c)
- **状态**：已决
- **决定**：(b)+(c) 都要。`"defaultMode": "<mode>"` 显式声明默认集（`--mode` 可覆盖；未声明且未传 `--mode` 时保持跑全部，向后兼容）；`"enabled": false` 把 gate 从一切选择中排除，运行输出打一行 `DISABLED <id>`（可见，绝不静默消失）。mode 引用 disabled gate 合法（自动过滤）——下线是一处编辑；引用**未知** gate 仍 fail loud。`defaultMode` 指向不存在的 mode = 配置错误（exit 2，带名字）。
- **被否**：(a) 隐式魔法名与"fail loud、不猜意图"冲突；(c) 单独不够——mode 集合仍无法作为默认生效；mode 引用 disabled gate 直接报错被否——那会逼用户改两处，退回"删除定义"老路。

## D12 — pairing 约定可配置 + 显式登记

- **问题**：`.zh.md` 命名与扫描范围硬编码在工具里（docs/ + README.md，排除 decisions.md 是本仓库私有事实），存量项目（如 `_CN.md` 约定）无法采用此 gate；`--write` 只能重记录已配对文件、不能声明配对，报错 `missing counterpart` 误导（用户以为是"登记"，实际什么也没发生）。
- **选项**：(a) 配置塞进 gates.json；(b) 独立 `.gov/pairing.json`；(c) 只加 `--write` 显式登记，不加配置
- **倾向**：(b)+(c)
- **状态**：已决
- **决定**：(b)+(c) 都要。`.gov/pairing.json`（全键可选，坏配置 exit 2）：`include`（glob 数组，默认 `["docs/**/*.md","README.md"]`）、`counterparts`（`{stem}` + 字面后缀的模式数组，默认 `["{stem}.zh.md"]`，后缀禁 `/` 与花括号）、`exclude`（路径数组，默认空）；本仓库对 decisions.md 的排除从代码移入本仓库自己的配置。记录文件新增 `counterpart: <文件名>` 字段钉住译文侧名字，验证优先读它，旧记录无此字段则按约定推导（向后兼容）；被记录钉住的文件名不再被当作源文档。`--write en:<path> zh:<path>` 显式登记任意命名的配对（两侧须同目录、均存在）；报错必须带"试了什么约定 + 怎么显式登记"的行动指引。
- **被否**：(a) 污染 D1 锁定的 gate schema，工具私有配置混进通用配置；(c) 单独不够——登记了约定外名字后，验证扫描发现不了该配对（登记必须能持续生效）；支持任意目录的 counterpart 被否——记录按同目录 basename 钉名字，跨目录让记录语义复杂化。

## D13 — 新装项目 advisory-first（首跑不红）

- **问题**：`gov init` 后首个 `gov run` 即红（存量文档无配对记录 → pairing 违规），第一印象是"装完就挂"，阻碍采用。
- **选项**：(a) init 探测存量文档并自动 baseline；(b) 新装 gate 先 advisory（只报告不拦截），显式确认后升级强制；(c) 保持全强制
- **倾向**：(b) + 轻量引导
- **状态**：已决
- **决定**：模板 `gates.json` 的 pairing gate 带 `allowFailure: true` 落地；runner 对 advisory 失败打标输出（结局行标 `(advisory; allowFailure)`、输出块照打——原先 allowFailure 失败不打印输出，advisory 等于看不见）；`gov init` 结束打印 next steps（跑 → `verify-pairing --write` baseline → 摘除 allowFailure 升级强制）。已 baseline 的项目（本仓库自身）直接强制。manifest 的 version 字段改记注入时的 CLI 实际版本（原硬编码 0.1.0）。
- **被否**：(a) init 内跑门禁/写 baseline 越权——init 只注入不评判，且自动写记录等于替用户确认"翻译一致"这一人类判断；(c) 即被拒的现状。

## D14 — note 存在性软门禁（兑现 D3 延伸）

- **问题**：规则 2 说"每个非平凡变更必须带 Agent Note"，规则 1 说可检查的承诺必须是 gate——存在性恰恰可检查（diff 触及行为面 ↔ diff 触及 notes），但 notes gate 只验格式，存在性纯靠自觉。规则与工具脱节。
- **选项**：(a) 硬门禁：非平凡 diff 无 note 即红；(b) 软门禁：警告不阻断 + 规则出处；(c) commit message 里要求 `note:` 引用
- **倾向**：(b)（D3 延伸已锁定）
- **状态**：已决
- **决定**：新增 `gov verify-note-presence`：diff（含未跟踪文件）触及行为面（非 docs/非 notes/非根级 .md）而无 `implemented/` note 变更 → **警告不阻断（exit 0）**，输出带 `.gov/rules.md` 规则 2 出处与"平凡改动可忽略"的出口；`--strict` 升级为阻断（exit 1）。默认 base=`HEAD`（工作树+暂存区——本地推送前检查的自然单位，且从仓库第一个提交起就存在；CI 显式传 ref）。git 失败 exit 2。默认进模板 `all` 模式。change-scope 输出同款提示联动。
- **被否**：(a) "是否平凡"终究是人的判断，机械硬拦必产生假阳性，逼人绕过；(c) commit message 是另一个平面（且 squash/rebase 会改写），diff+notes 文件面才是稳定证据。

## D15 — gate 级 `paths` 与 diff 选门

- **问题**：规则 1 说"按变更跑最小集合"，但工具不支持 scope→gate 映射——`gov run` 不知道哪些门与本次变更相关（单测挂了也拦文档改动），长期诱导 `--mode quick` 绕过或 `--no-verify`。change-scope 的面→门映射硬编码（还引用不存在的 `links` 门），与 gates.json 脱节。
- **选项**：(a) 不做，靠 mode 手选；(b) gate 定义加 `paths` glob 数组 + `gov run --base <ref>` 自动选门；(c) 只改 change-scope 的硬编码映射
- **倾向**：(b)
- **状态**：已决
- **决定**：gate 可选字段 `"paths": [glob]`（`**` 跨目录、`*` 不跨；匹配仓库相对全路径）。`gov run --base <ref>`：git diff（含未跟踪）→ 选 paths 命中的门 + 无 paths 的门（永远相关），打印 `scope vs <ref>: N/M ...; out of scope: ...`。`--mode`/`--base`/`--gate`（单门重跑）互斥、显式传参优先于 defaultMode。change-scope 建议改为读 gates.json 的 paths（单一事实源；无 paths 配置才退回落级映射，删除幽灵 `links`），并给出 `gov run --base` 执行提示。失败运行末尾追加摘要块：哪个门挂 + 首行输出 + `gov run --gate <id>` 重跑提示。
- **被否**：(a) 最小集合原则空转；(c) 两份映射必然漂移（`links` 幽灵即证据）；把 paths 塞进 change-scope 私有配置被否——门与它覆盖的范围属同一事实，必须住在 gate 定义里。

## D16 — init 的 hooks / CI 加装

- **问题**：治理平面的价值全在"自动执行"，但 `gov init` 不提供任何执行路径——采用者只能手写 pre-push hook 和 CI workflow。
- **选项**：(a) 不做（用户自理）；(b) `gov init --hooks` / `gov init --ci` 可选加装；(c) 默认全装
- **倾向**：(b)
- **状态**：已决
- **决定**：`--hooks` 装 `.gov/hooks/pre-push`（留档可见）并写入 `.git/hooks/pre-push`（可执行，内容即 `exec gov run`）；`.git/hooks/pre-push` 已存在且非 gov 钩子 → **加装前预检 fail loud（exit 2）**，绝不覆盖、不留半初始化状态；已存在 gov 钩子 → 幂等替换。`--ci` 仅在 `.github/workflows/gov.yml` 缺失时生成（checkout + setup-python + pip install govrail + `gov run`），已存在则不动。两者记入 manifest（created + gitHooks），`uninstall` 精确反转。非 git 仓库用 `--hooks` → exit 2。
- **被否**：(a) 与"机器守线"的立身之本矛盾；(c) 惊喜写入 `.git/` 与 `.github/` 侵犯项目主权，加装必须显式 opt-in。
