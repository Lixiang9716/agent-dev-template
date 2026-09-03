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

## D17 — 评审量规（rubric）与元门禁

- **问题**：规则 1 说"不可检查的约定属于评审"，但评审本身没有结构——标准活在评审人脑子里：跨人（跨 agent）不一致、不可审计、作者无法在提交前自检；"评审质量"本身无从检验。
- **选项**：(a) 只写散文式评审指南；(b) 双语量规文档 + code-review skill 接线；(c) 再加 `verify-rubric` 元门禁
- **倾向**：(b)+(c)
- **状态**：已决
- **决定**：`docs/review-rubric.md`（+.zh.md+.i18n.yaml 双语三件套，规则 7）：R1–R8，每条四字段 `Checks`/`Evidence`/`Anti-pattern`/`Gate candidate`——**条目是评审态，门禁是运行态**，`Gate candidate` 显式标注毕业去向，可机械化的按事件驱动成长升级成门禁（D14 即先例）。code-review skill 按量规逐项判定（"约定第三次被手工执行 → skill"，成长表原文）。`gov verify-rubric` 只查**量规自身结构**：ID 从 R1 连续唯一、四字段齐全非空、`yes` 必须写去向、`.zh.md` 侧 ID 集合对齐（跨语言契约是 ID，措辞是译者自由）——判断本身永不伪机械化。rubric 门禁进本仓库 gates.json（paths 限定量规两文件）；**不进注入模板**。
- **被否**：(a) 无结构散文=各人各标，正是量规要消灭的；(c) 同时把模板量规注入所有项目——违背事件驱动成长：没有采用者第三次手工执行过"写量规"这件事，就不该模板化；采用者的量规内容取决于他们的规则。

## D18 — 记忆的读侧：recall 与 audit-notes

- **问题**：写侧纪律已闭环（笔记必须存在、格式必须对——"notes are the agent memory"），但读侧只有裸 grep：找一条决策要手翻三四个目录；笔记契约说 implemented 要"与已交付事实保持一致"，漂移却完全无声。
- **选项**：(a) 只靠 grep 与人工；(b) `gov recall` 结构感知检索 + `gov audit-notes` 机械新鲜度信号；(c) 嵌入/向量检索；(d) 会话级工作记忆
- **倾向**：(b)
- **状态**：已决
- **决定**：(b)。`gov recall <terms>`：跨 notes（implemented+archived）、decisions.md（每个 `## Dn` 节是一条）、postmortem 条目（README 除外）的确定性检索；全词 AND、大小写不敏感；按命中位置排序（标题 > 节标题 > 正文）；无命中 exit 1（fail loud——不许对着空结果推理）。`gov audit-notes`：只报**机械**信号——backtick 的 `gov <子命令>` 已不存在、`Dn` 引用在 decisions.md 无对应条目、带分隔符+扩展名的 backtick 路径解析失败（占位符与 glob 豁免）；archived 冻结豁免（D5）；发现即报告、exit 0——是给 archive-agent-notes 技能的证据，不是判决。两者均为工具而非门禁（不进 gates.json），随包分发给采用者。
- **被否**：(a) 读侧摩擦正是记忆"写了没人读"的直接原因；(c) 零依赖是锁定承诺，且语义检索不可审计、在此规模（几十篇）是伪需求；(d) 工作记忆属 harness/session 层——治理平面只管版本化的仓库记忆，平画分离。

## D19 — agent 技能随包分发

- **问题**：技能（recall-first 等）此前仓库本地、不随 `gov init` 注入——采用者的 agent 会话得不到"先查记忆再提案、先选最小集再跑门禁"的触发器，工具空转到货、习惯不来。D17/D18 的"事件驱动、暂不模板化"立场中，技能这一半的事件已到：维护者明确要求分发。
- **选项**：(a) 继续仓库本地；(b) 四技能作为 init 模板注入（create-if-missing，项目自有同名技能绝不覆盖，manifest 记录、uninstall 反转）；(c) 连量规一起模板化
- **倾向**：(b)
- **状态**：已决
- **决定**：(b)。技能写成**条件式**使其在有无量规的项目都成立（code-review/pre-push-checks：有 `docs/review-rubric.md` 按条目评，无量规回退到判断轴清单）——由此模板与本仓库活文件**字节相同**，并以一条 pytest 防漂移断言锁住（模板 ≠ 活文件即红）。打包经 `package-data "skills/*/SKILL.md"` 子目录 glob，构建 wheel 实证收录。量规本身**仍不模板化**（其条目一半引用本仓库特有事实，D17 立场不变；技能用条件引用消化该依赖）。
- **被否**：(a) 工具分发了、触发器不分发，等于卖了枪不配准星——采用者 agent 的第一动作仍是手工 grep；(c) 需要重写一套通用量规条目，超出本次诉求，且"评审标准"比"工具习惯"更贴项目个性，事件未到。

## D20 — 承诺语义的机械化（诚实执行轮）

- **问题**：外部对抗测试暴露十项"文档承诺 ≠ 工具强制"：① archive-notes 在任何新项目裸崩（写 manifest 前 `archived/` 不存在，init 也不建），零笔记还封空 manifest；② runner 丢弃 exit-0 门禁的输出——advisory 警告在 DAG 里蒸发，用户只看到绿灯；③ 空 rubric（0 条目）空过，违反规则 6；④ 笔记三段顺序 README 说了但未强制；⑤ class 封闭集未强制（implemented/misc/ 照过）；⑥ `.agents/notes/drafts/` 被 verify-notes 静默忽略却被 recall 检索——两工具对"什么是笔记"意见不一，且违反规则 5；⑦ archive-notes 不解析参数；⑧ init 的 next-steps 指引在无配对文档的项目必然 exit 2；⑨ decisions.md 格式不符时 audit-notes 零提示地全量误报 Dn 引用；⑩ 根级 .md 一律 trivial，文档驱动仓库的 DESIGN.md（唯一事实源）逃逸 note 检查。
- **选项**：逐项小修 vs 引入新机制（WARN 第六结局、笔记路径配置化等）
- **倾向**：逐项小修，不加新机制
- **状态**：已决
- **决定**：① archive-notes：写前 `mkdir(parents=True)`、零笔记报 "nothing to seal"（不写空 seal）、argparse 强制（未知参数 exit 2）、非 governed 目录 exit 2。② runner（**修订 D2 的"通过静默"**）：exit 0 且有输出的门禁，PASS 结局与退出码不变，输出末尾 ≤3 行以 `(passed with output)` 块展示——"通过且无输出才静默，绿灯不吞警告"。③ verify-rubric：0 条目 = vacuous pass，拒绝。④ verify-notes：三段行级匹配且按承诺顺序强制（乱序报错）；`implemented/<class>/<file>.md` 双段路径强制、class 限 D5 封闭集；`.agents/notes/` 下未知生命周期目录 fail loud。⑤ recall 同步只检索 implemented/ + archived/——笔记的定义在两工具间唯一。⑥ verify-note-presence：根级展示文档（README*/CHANGELOG*/CHANGES*/CONTRIBUTING*）仍 trivial，**其余根级 .md（DESIGN.md、ARCHITECTURE.md 等）视为行为面**；docs/ 子树仍 trivial（配对门禁的领地）。⑦ init next-steps 做**只读存在性探测**（README.md / docs/*.md）选择指引文案——不是 D13 否决的自动 baseline：不评判、不写入，只挑建议。⑧ audit-notes：decisions.md 存在但解析出 0 条 `## Dn —` → stderr 警告格式不符、D-ref 置为 unchecked，不再全量误报。
- **被否**：WARN 第六结局——改 D2 锁定的五结局契约，展示输出尾部已达到目的；根级 .md 全部判非平凡——README/CHANGELOG 纯展示改动会刷屏警告，advisory 也怕"狼来了"；生命周期目录可配置——D5 已锁定最小集，事件未到。

## D21 — 执行器诚实轮：auto base、根锚定、部分 baseline、排序

- **问题**：① note-presence 默认 `--base HEAD`（工作树），但两个 shipped 执行器看到的都是**干净树**——push 钩子在工作树干净后运行、CI checkout 后工作树干净 → diff 恒空 → 门禁在真正的执行点上结构性失明（实测：无笔记提交推送，钩子全绿放行）。② 子目录调用时 verify-notes/verify-pairing 报 "0 notes ok / 0 pairs ok" 静默空过（路径 cwd 相对），而 recall/audit/archive/run 都会 fail loud——同一"受治理根"判断五命令两套标准。③ 裸 `--write` 遇到一个未配对文件即整体拒绝，好配对的基线也写不成。④ recall 同分排序按路径字母序，archived/ 恰在 implemented/ 前——当前权威排在冻结证据后面。
- **选项**：① 钩子从 stdin ref 区间算 base + CI 显式传 ref；或工具端 auto base 级联。② 各工具自加根校验；或共享 git 根锚定。③ 维持全有或全无；或部分成功。④ 忽略；或排序加生命周期优先级
- **倾向**：工具端统一解决
- **状态**：已决
- **决定**：① note-presence 默认 base 改为 **auto 级联**：脏树→HEAD（审查工作树）；干净→`upstream...HEAD`（审查未推送提交）；无 upstream→HEAD~1；单提交→空树（一切都是变更）。所选 base 及理由打印在输出首行。CI 模板与本仓库 ci.yml 加 `fetch-depth: 0`（浅克隆会让级联跌到"全仓库"）。钩子保持 `exec gov run`——auto 使其天然正确。显式 `--base` 永远可钉死。② 新增 `gov/root.py::anchor_to_git_root`：在 git 工作树内即 chdir 到根并**在 stderr 宣告**，五个笔记/配对工具（verify-notes、verify-pairing、recall、audit-notes、archive-notes）统一接入；非 git 目录保持原样（缺失标记自然 fail loud）。③ 裸 `--write`（含点名形式）改**部分成功**：能记的记、不能记的逐条报、末行 `wrote N, left M unpairable`、exit 1（点名不存在的路径仍是 exit 2——那是笔误不是配对状态）。④ recall 排序键加生命周期优先级：同分时 implemented/ 先于 archived/，再按路径。
- **被否**：① 钩子解析 stdin ref 区间——每个执行器各自算 base 必然再漂移；级联一次做对，钩子保持零逻辑。② 各工具自加校验——五份实现两套标准正是本缺陷的成因。③ 维持全有或全无——一个坏文件挟持所有好配对，正是"整体拒绝"在 F3 里的形态。

## D22 — 加装可补、定制不静默重置、Status 值域封闭

- **问题**：① `gov init --hooks` 对已初始化项目只报 "already initialized"——没有任何事后补装钩子的入口；唯一路径 uninstall→init --hooks 会把 `.gov/rules.md` 的定制规则与 `gates.json` 的定制标签**静默重置**为模板默认（笔记因非 init 创建而幸存）。② `Status:` 值域无校验——`Status: banana` 照过 verify-notes；生命周期实际由目录位置编码，字段成了装饰（README 未承诺封闭值域，不算违约，但按诚实标准要么校验要么明说）。
- **选项**：① 加装支持增量；或 uninstall/init 检测定制并警告/保留。② Status 封闭 {implemented, archived}；或文档声明任意文本
- **状态**：已决
- **决定**：① **双管齐下**：`--hooks`/`--ci` 在已初始化项目走**增量路径**（只做预检 + 装所请求的加装 + 合并更新 manifest；rules/gates/notes/skills/引用行一律不碰——补装钩子永不重置定制）；uninstall 保持 D10 精确反转，但删除前把**与模板有字节差异**的文件点名警告（rules.md + created 里能映射回模板的条目），定制不再静默消失。② Status 封闭为**恰一值** `implemented`（archived 笔记按归档程序本就保留 `Status: implemented` + `Archived:` 行；生命周期=目录，字段无第二状态可表达），README（仓库+模板双份）明文"值恰为 implemented，生命周期是目录不是字段"。
- **被否**：① 定制文件在 uninstall 时保留——破坏 D10 的精确反转契约；只警告不保留。② 允许 {implemented, archived} 两值——archived/ 不经 verify-notes 检查，给了第二值等于给字段塞进目录已有的职责，重新引入双事实源。

## D23 — 封条有读者、重封不洗白、uninstall 真两步

- **问题**：① uninstall 的定制警告文案说 "copy out ... then re-run"，暗示首跑已中止——实际同一运行内警告后直接删除（照提示等 re-run 再备份的用户已丢数据）。② 归档封条承诺 "any later edit is detectable"，但 manifest 只有写者没有读者：篡改归档笔记后 verify-notes（D5 跳过）/audit-notes（豁免）/recall（照常索引）无一发现；更糟的是重跑 archive-notes 按篡改后内容重算哈希重新封条——违规被永久洗白。
- **选项**：① 警告后 return 1 真两步（--force 继续）；或只改文案为"即将删除"。② 新增 verify-archive 检测器 + 重封前验旧封条；或并入 verify-notes；或维持现状加文档声明
- **状态**：已决
- **决定**：① **真两步**：检测到定制文件 → 警告 + `return 1`，**本次不删任何东西**；`gov uninstall --force` 为显式同意（仍点名删除的定制文件）。无定制时单步直删不变。② **封条闭环**：新增 `gov verify-archive` 门禁——每个归档文件对封条验 sha256、封条条目对文件双向缺失检查；未封（有文件无 manifest）也是违规。`archive-notes` 重封前**先验旧封条**：漂移 → exit 1 拒绝并列名（"restore or --rebaseline"）；`--rebaseline` 为显式同意并大声打印 RE-BASELINED 了哪些。门禁以 paths 限定 `.agents/notes/archived/**` 进本仓库与注入模板（篡改即触发）。归档技能同步：程序加"封后用 verify-archive 确认"，Never 加"不许对被篡改文件重封"。
- **被否**：① 只改文案——空头支票换成如实告示仍是单步数据丢失；两步多一次确认是 uninstall 低频操作付得起的价格。② 检测并入 verify-notes——封条是完整性不是格式，混关注点；独立门禁可被 paths 精确触发。重封无条件允许（迁移便利）——便利通道就是洗白通道，必须显式且大声。

## D24 — 门禁可达性：唯一且响的停靠机制（radiant #5 审计）

- **问题**：① 模板把 self-test 只放进 governance mode，而 defaultMode=all 不含它，注入的 CI 与 pre-push 钩子都裸跑 `gov run`——每个新 init 项目的治理自检从第一天起没有任何自动执行路径（radiant 实证：26 个拒绝用例从未在自动路径上跑过，人工审计才发现；补进 all 后 CI 10s→17s）。② 结构性根因：gates.json 存在两种停靠机制——`enabled: false`（响的：DISABLED 行）与 mode 省略（哑的：不执行也不报告，完全不可见）；后者从未被承认为停靠手段，模板自己却在用。这是 vacuous pass 的镜像：never runs 的 gate 连失败的资格都没有。③ N4：`--gate <被停门禁>` 静默 exit 0。
- **选项**：模板补 self-test 即可；或同时封死哑停靠；或引入 --every-gate
- **状态**：已决
- **决定**：三层全做。**可达性校验（fail loud）**：modes 非空时，已启用门禁不属于任何 mode → ConfigError 点名（"park with enabled:false — the one loud mechanism"）；停靠只有一条路且必响。存量项目不受影响（governance mode 里的门禁属于"某 mode"）。**模板修复**：modes.all 加入 self-test（governance mode 保留为单跑自检的快捷方式）——部分翻案 0.3.0 的"self-test 不进项目默认运行"：模板 CI 装的是**未钉版本**的 govrail，self-test 是采用者侧的工具冒烟测试，7 秒换消费者级回归检测，且规则 1"CI owns the full matrix"自洽。**--every-gate**：无视 modes/defaultMode 跑全部已启用门禁，给"full matrix"一个显式落点。**N4**：`--gate` 点名被停门禁 → exit 2（显式请求停用物是操作错误，静默绿会掩盖它）。附带：note-presence 在零提交仓库不再因无 HEAD 而 exit 2（未跟踪清单即全部变更，守住 D13 首跑不红）。
- **被否**：只修模板不封哑停靠——下一个配置还会悄悄长出 never-runs 门禁；允许"未引用 mode 的门禁"合法存在——可达性判据必须落在"属于某 mode"而非"属于 defaultMode"（否则 governance 快捷方式非法）；CI 跑两条命令（run && run --mode governance）——比一行模板改动静态多、语义少。

## D25 — 采用者愿望轮：本地拒绝用例、--json、并行分域、表面映射

- **问题**：radiant 四愿望，按价值排序：① 规则 6 要求每个治理门禁自带拒绝用例，但 self-test 只跑 govrail 自带用例——采用者给自定义门禁写的拒绝证明没有机械接线入口（"没有执行路径的承诺不存在"的自我应用）；② gate 结果只有人读行文本，机械消费（趋势、耗时回归、报告聚合）只能解析 stdout；③ self-test 进默认集后用例串行线性累积，全矩阵税会诱惑采用者把它再挪出去（G2 复发）；④ 表面分类硬编码，eval/ 这类实验装置全归 "code"，monorepo 更甚。
- **选项**：逐项采纳 vs 部分缓做
- **状态**：已决
- **决定**：四项全做。① **`.gov/rejections/` 约定**：目录下每个可执行文件是一个拒绝用例（cwd=仓库根，exit 0=拒绝证明成立；README* 跳过；不可执行点名报错）；self-test 递归执行，报告 `tools N + project M` 分开计数；`--scope tools|project` 分域；gov init 注入约定 README。② **`gov run --json`**：stdout 恰一个 JSON 数组 `[{gate, outcome, blocking, duration_ms, detail}]`（config 顺序，DISABLED 以第六种记录值出场），人读报告转 stderr，退出码不变，与一切选择器正交。③ **self-test 并行**（4 workers，输出仍按 CASES 顺序+路径序确定；全部失败一并报告而非只报第一个）。④ **`.gov/surfaces.json`**：`{"<glob>": {"surface": 名, "gates": [id...]}}`，命中者优先于内置分类、其 gates 取代回退建议（全命中时只建议配置门禁），坏配置 exit 2；无配置行为不变。
- **被否**：① 拒绝用例塞 pytest——另一个运行时、另一份报告，规则 6 的证明散落两处；② JSON 里带汇总对象——数组即记录，聚合是消费者的事（jq 一行）；分号分隔/流式行 JSON——`| jq` 直接消费要求恰一个 JSON 值；③ 用例分域替代并行——分域解决"跑哪些"，并行解决"跑多久"，全矩阵税是后者；④ 表面分类改成全配置——无配置的默认行为是新人第一印象，硬编码默认+可选覆盖才是渐进采用。

## D26 — 拒绝用例预算与 --json 纯度契约

- **问题**：① 项目拒绝用例的超时预算是 120s——一个失控用例（sleep 300）能把进了默认模式与 CI 的 self-test 拖住两分钟才失败，与门禁超时属同一家族（运行器必须有预算）。② `--json` 存在一处泄漏：`--base` 的 `scope vs` 行打到 stdout，机器消费端在 JSON 前读到人读行。
- **状态**：已决
- **决定**：① 每个拒绝用例预算 **10s**（`REJECTION_TIMEOUT_S`），超时 = FAIL 并点名 `(timed out after 10s)`，运行继续；约定写入 rejections README（拒绝证明天然是小用例）。② **--json 契约：stdout 恰一个 JSON 值**——一切人读输出（含 `scope vs` 行）走 stderr；以参数化测试锁住每个选择器路径。③ `duration_ms` 已在 0.7.0 交付（愿望 7 无需改动）。
- **被否**：预算可配置——10s 固定值 + 文档说明足够，配置项是为极端 case 服务的复杂度；用例超时缩到 3s——git init 类用例在慢 CI 上会假红。

## D27 — 模板演化的升级路径：看见，绝不代写

- **问题**：`gov init` 对已初始化项目拒绝，增量入口只有 --hooks/--ci；模板在演进（rules.md 规则、gates.json 门禁、rejections README、技能），存量采用者没有任何机械途径看到"模板变了什么、我的定制如何合并"——只能读 changelog 手工 diff（radiant 的 rules.md 已含项目规则 8，下次模板更新即手工 diff 冒险）。
- **选项**：--upgrade 自动合并/覆盖；--upgrade 只读报告；维持现状靠 changelog
- **状态**：已决
- **决定**：**`gov init --upgrade` 只做"看见"**：读 manifest 记录的 init 版本与当前包版本对（时代上下文），对每个注入文件（rules.md + notes README + rejections README + 技能 + created 里的 gates.json/gov.yml）做"现模板 vs 本地"逐文件统一 diff；缺失文件（新版模板新增、旧 init 没建过）标 MISSING-safe-to-add；全部一致时提示 safe to refresh。**绝不写入任何文件**；采纳仍是人的动作（定制文件遵循 D23 两步哲学）。差异归因诚实：init 版本=当前版本 → "customized locally"；更旧 → "customized locally and/or template evolved"（无法区分就明说无法区分）。
- **被否**：自动合并/覆盖——模板与定制三方合并是数据丢失机器，D23 刚为 uninstall 修过同类；只报"版本不同"不报文件 diff——版本号不携带哪些文件变了，等于让人继续手工 diff。

## D28 — 愿望轮 II：决策守卫、评审档案、技能防漂移、时延趋势、降噪、孤儿记录

- **问题**：六愿望。① decisions.md 是治理脊柱却是纯散文——D 编号唯一/连续、被否段在座、孤儿决策零校验（复现：重复 D9、跳号、删被否行——无工具报错）。② 评审者冷启动要手工串联 4 个命令装配材料。③ 技能文本里的 `gov` 命令/旗标引用无人校验，命令改名时面向 agent 的说明书静默过期（agent 是最照本宣科的用户）。④ `--json` 的 duration_ms 每次即弃，耗时回归只能靠人眼记忆。⑤ 长会话大量未跟踪文件让 note-presence advisory 刷屏。⑥ 双侧删除后的孤儿 .i18n.yaml 永不清点。
- **状态**：已决
- **决定**：① **`gov verify-decisions`**（verify-rubric 模式的下一个对象）：编号唯一且从 D0/D1 起连续；每条含 选项/被否/Alternatives（规则 3 精神跨文档适用）；孤儿（无笔记引用）信息性不违规。自仓库 D0–D27 首跑全绿即首位用户；进本仓库 gates.json（paths 限定 decisions.md），不进模板（内容因项目而异，同 D17 立场）。② **`gov review --base <ref>`** 四段档案：变更面（change-scope 数据）/范围内笔记（note-presence 数据）/变更关键词 recall 前五/量规条目（无量规优雅降三段）；坏 ref exit 2；code-review 技能（双份）改从档案开工。③ **audit-notes 扩技能**：`.agents/skills/**/*.md` 的反引号 `gov` 命令与旗标对照 CLI 注册表 + 旗标表（-h/--help/-v/--version 通用豁免；表覆盖全部命令）。④ **`gov run --record`** 追加一行 JSON 到 `.gov/history/gates.jsonl`（ISO 时间戳+records；append-only；**opt-in，运行默认仍无状态**）+ **`gov trend`**（窗口对半，逐门 p50 变化比，≥1.5×/≤0.67× 报为 movers）；history 不进任何 gates 校验范围，本仓库 gitignore 之。⑤ note-presence **`--staged`**（只看 index，干净即静默）+ 超五条折叠 `…and N more`；否决 ignore_untracked 配置旋钮（D26 同理）。⑥ verify-pairing 增 **dangling record** 检查（记录在、双侧皆缺 → 点名"删除或重建后 --write"）。
- **被否**：① 孤儿决策算违规——决策可以先于引用它的笔记存在，信息性是对的强度；③ 旗标注册表从 argparse 运行时反推——解析器在 main() 里运行时构建，反推的成本高于静态表+用例钉住；④ 默认记录——违背运行无状态，--record 是显式同意；⑤ 折叠阈值可配——5 条固定值足够。

## D29 — 愿望轮 III：采纳落地、环境自检、笔记前置、证据预取、严格 schema、默认记录

- **问题**：六项。① --upgrade 只报告，纯新增文件（如 rejections README）仍要手抄 site-packages。② 无环境自检：gov 不在 PATH、Python 版本错配、hook 不可执行都靠撞。③ 笔记三段式/D 引用/路径有效性都要提交后才查（笔误晚一个审计才被抓）。④ review 档案只组装不预取证据，打分仍要人工翻代码。⑤ gates.json 无 schema 校验——`"enable": false` 这类笔误静默不停靠（恰是 D24 封死的哑停靠后门）。⑥ trend opt-in 且缺席时"从未记录"与"无波动"不分。
- **状态**：已决
- **决定**：① **`gov init --adopt [file…|all]`**：只落地本地缺失的模板文件（绝不覆盖已有；钩子模板落 .gov/hooks 并 chmod +x），记入 manifest；升级报告的 MISSING 行改标 `adoptable: gov init --adopt <rel>`；修改类 diff 维持 D23 两步。② **`gov doctor`**（规则 5 风格，问题点名、exit 1）：gov 可达性、Python ≥3.9、两份 pre-push 可执行性、gates.json 严格 schema、decisions 表可解析。钩子模板解析链改为 **GOV_BIN → PATH 上的 gov → python3 -m gov**（pipx 隔离环境仍走 PATH）。③ **`gov note new --class <c> --ref <D> "标题"`**：合法路径脚手架（class 对照封闭集、D 引用对照 decisions 表，写之前就拒）；**`gov note check`**：格式+路径+悬空 D 引用，轻量到可挂 pre-commit。④ review 第 4 段为每个量规条目附**证据候选**：Checks 字段中的反引号锚点在变更文件里内联匹配（±4 行摘录、每条目至多 2 处），明示"是待核对的线索不是结论"。⑤ **load_config 严格键**：顶层与 gate 级未知键即 ConfigError 点名（`enable` 退场）。⑥ **记录默认开启**（本地文件、已 gitignore、append-only——翻转 D28 的 opt-in 子项），`--no-record` 退出；trend 区分"从未记录"与"历史存在但不足两轮"。
- **被否**：① adopt 顺带修改类文件——那是两步哲学的领地；② doctor 自动修——点名不代修，修复动作必须过人手；③ note new 自动填充内容——骨架+预校验止步，代写决策即代撒谎；⑤ 未知键警告不阻断——静默跳过的温和变体仍是静默跳过；⑥ 维持 opt-in——"本地遥测默认关"换来的只是没人打开它。

## D30 — 愿望轮 IV：评审工作台、配对往返、决策半衰期、覆盖账本、试跑、单门趋势

- **问题**：① 证据预取解决了"找证据"，裁决仍要人工誊写成 skill 契约格式。② 配对修复三步往返（变红→回想命令→全量 --write），且漂移时看不出谁先动的。③ 决策无半衰期——"D3 的上下文可能过期了"无人提示。④ 规则 6 的覆盖无人记账——13 个门禁是否都有拒绝用例纯靠自觉（evalkit-tests 差点漏掉）。⑤ gates.json 改错命令要等下次普通改动才爆（MISSING 才现形）。⑥ trend 缺单门视图与基准切分；upgrade 报告机器不可读。
- **状态**：已决
- **决定**：① **`gov review --grade`**：档案后逐条交互收 `Rn [p/f/s/q]`（f 追问 evidence），末尾生成 skill 输出契约的裁决块（逐条行 + blockers + 显式 verdict；fail → exit 1）。**人裁决、机器誊写**。② 配对：out-of-sync 报错**内联修复命令** `gov verify-pairing --write <stem>`（--write 本就支持点名对）；sidecar 增 `last_confirmed`（ISO 时刻）与 `en_commit`/`zh_commit`（双侧最后修改提交），漂移报错带"哪侧在哪个提交动的、何时确认的"。③ 决策可选 **`review-by:`** 字段（ISO 日期）：过期 → 提示行（信息性，同孤儿）；不可解析日期 → 违规。④ self-test 末尾输出**覆盖账本**：项目用例以 `# gate: <id>` 声明归属（首五行内，shebang 保持首行），报告 `gate(n)` 矩阵，无用例门禁点名 "NONE — rule 6"，幽灵 gate 名也点名；信息性不失败；坏 shebang 用例被点名而非炸穿。⑤ doctor 对每个 gate 命令做**可执行解析检查**（which 失败 → problem，把"配置能跑"与"配置是对的"分开）。⑥ trend **`--gate <id>`** 单门过滤 + **`--base <ref>`** 以该提交时间切早晚窗（变更前后对比）；`init --upgrade --json` 输出恰一个 JSON 值（status: matches/differs/missing/absent-add-on + adoptable）。
- **被否**：① --grade 自动打分——裁决主体必须是人/评审 agent，机器只管格式；② 过期 review-by 算违规——过期是"该重读"不是"错了"，与孤儿同级；④ 覆盖缺口算失败——覆盖率爬坡期会逼人删门禁而不是补用例。

## D31 — 果用性轮：样例、食谱、whatsnew、报告内指路

- **问题**：能力不是瓶颈，可发现性是——实证：至少三个已发布功能被当作新愿望重新提出（--json 的 duration_ms、--write 点名对、note new 无表提示）。更新后采用者的全部信息是 CHANGELOG 一行 + README 一行；demo-project 只演示平面约三成（无 rejections/surfaces/rubric/decisions）；无任务导向文档；报告有答案但部分缺"下一步"。
- **状态**：已决
- **决定**：四件全做。① **活样例**：demo-project 扩为全功能标本（rubric 双语对、带 review-by 的决策表、`# gate:` 声明的拒绝用例、surfaces.json、带 Related: D 的笔记、gates.json 含 rubric/decisions/source-limits 门），采用者可 `diff -r` 对表。② **食谱**（`docs/cookbook.md` 双语对）：任务导向（"pairing 变红了""加门禁闭环""读 mover""长会话降噪"），收纳本 session 真实撞墙场景，每篇 症状→命令→预期输出。③ **`gov whatsnew [--since]`**：随包分发策划版 `gov/HIGHLIGHTS.md`（用法导向，按 minor 版组织，非 commit 流水），默认 since=manifest 的 init 版本；`init --upgrade` 检测到包新于 manifest 时提示该命令——更新与发现之间的桥。④ **报告内指路铺满**：覆盖账本 NONE 行附用例文件格式；trend mover 附解读句（"是要调查的问题，不是结论"）。
- **被否**：whatsnew 直接读 CHANGELOG——commit 流水不是用法说明，策划版要维护但每一行都在回答"怎么用"；食谱进包分发——repo 文档足够，包保持轻；样例进 CI 跑全绿——样例住在我们仓库内会被根锚定到主仓库，独立验证留给采用者的拷贝。

## D32 — 对抗审计轮 III：worktree、钩子语境、爆炸半径、空洞绿灯家族

- **问题**：九项（#15–#23）。① doctor 用 `os.path.isdir(".git")` 判仓库——linked worktree 的 .git 是文件，钩子检查静默丢失还报 sound。② 裸 `verify-pairing --write` 重写所有 sidecar——绿对获得从未发生的确认（时间戳/提交字段），污染无关 diff。③ 决策平面在 docs/decisions.md 之外静默空转——表在 DESIGN.md 的项目得到 vacuous 绿（规则 6 违约穿绿灯）。④ 覆盖账本与刚 PASS 的用例自相矛盾——无 `# gate:` 声明的旧用例跑过却仍被提示"write one"。⑤ doctor 无视 manifest 版本漂移（0.12.0 vs 记录的 0.6.5，环境自检一字不提）。⑥ pre-push 钩子语境下 self-test 稳定失败而手动全绿——GIT_DIR/GIT_WORK_TREE 泄漏使根锚定把临时仓库解析到宿主仓库（本地已复现：泄漏环境下 pairing 案例锚定到 govrail 主仓库）。⑦ 范围排除的门禁输出与真扫描绿灯一模一样（"0 file(s) within limits"）。⑧ 钩子恒跑全量 defaultMode，无视 push 区间——docs-only push 也跑全套 pytest，并发 push 互相压垮。⑨ .gov/history 按 worktree 碎片化，主仓库只见零头。
- **状态**：已决
- **决定**：① doctor 以 `git rev-parse --git-common-dir` 定钩子目录（worktree 与主仓一致）。② 裸 `--write` 只重基线**当前失步**的对（全绿时明示 no-op；强制绿对走点名形式）。③ **决策源可配置**：新共享加载器 `gov/decisions.py`（`.gov/decisions.json` {path, format: sections|table}；表格格式解析 `| Dn | … |` 行、表头备选列覆盖全行检查）；verify-decisions / audit-notes / recall 三消费方统一走它；**无源且有笔记引用 D → REFUSED exit 1**（不再 vacuous 绿）；无源且无引用 → 良性。④ 账本区分"未执行"（提示 write one）与"已执行未声明"（点名文件与缺失的 `# gate:` 行；永不提示写已跑过的用例）。⑤ doctor 比对 manifest 与包版本，漂移打 note 并指 upgrade/whatsnew。⑥ **self-test 进程入口剥除 GIT_***（工具按 cwd 解析仓库是 D21 的设计，继承环境只会误导；影响仓库解析的变量被清洗时大声声明）；钩子模板同样 unset 后再 exec。⑦ 路径门禁结局行附 `n in change scope`（0 时明示"nothing changed matches"，与扫描输出可分辨）。⑧ 钩子模板读 push stdin 取 remote sha 作 `--base`（docs-only push 只跑选中门并点名排除项；新分支无 remote → 全量）。⑨ history 写入 **git common dir 的父目录**（= 主 checkout 的 .gov/history；worktree 运行入主账本）。
- **被否**：⑥ 逐 subprocess 补丁式清洗——入口一次剥离覆盖进程内用例与其全部子进程；⑧ 钩子跑全量+缓存——规则 1 说 CI 拥有全矩阵，钩子拥有最小充分集；③ 无源一律拒绝——破坏首跑不红（D13），引用存在才是危险信号。

## D33 — 宿主完整性：scratch 夹具的三墙

- **问题**：#24——self-test 的 scratch 夹具两次反噬宿主仓库：① 0.12.0 钩子语境并发运行，泄漏的 GIT_DIR/GIT_INDEX_FILE 使 scratch 的 git 命令解析到宿主仓库，三个 worktree 分支各留孤儿 "init" 提交并随 push 出货；② 0.12.1（环境清洗已生效）worktree 自测窗口内主仓库 .git/config 被改写为 core.bare=true + user t/t——机制未钉死，意味着单点修复不可信。
- **状态**：已决
- **决定**：纵深防御三墙（任何一墙独立成立即安全）：**墙 1（夹具环境）**——`_git_repo` 的每条 git 命令以剥离 GIT_* 且注入 `GIT_CEILING_DIRECTORIES=<scratch父>` 的环境运行，泄漏的解析变量进不了夹具；**墙 2（toplevel 守卫）**——init 后、任何 config/add/commit 前，断言 `git rev-parse --show-toplevel` 恰为 scratch 本身，不匹配即大声中止（"refusing to configure or commit into it"），宁可测试红也不碰别人的仓库；**墙 3（全局天花板）**——self-test 入口在清洗环境后统一设 `GIT_CEILING_DIRECTORIES=<tempdir>`，进程内用例直呼 git 也无法向上走出临时区。验收测试固化：从 linked worktree 内跑全量 self-test（含敌对 GIT_DIR/GIT_INDEX_FILE 泄漏变体），宿主 config/refs/status/HEAD 字节级不变；守卫负向用例钉住"逃逸即中止"。
- **被否**：仅靠入口清洗（0.12.1 的事故证明它不够——机制未钉死时单墙不可信）；夹具改用 libgit2/纯 Python 实现——引入依赖且重写 33 个用例的收益不抵风险；禁用 worktree 场景——采用者的真实环境正是 worktree。

## D34 — 溯源三向判定、采纳预览与申报、外部 D 引用

- **问题**：① drift 报告把一切差异标成 "customized locally and/or template evolved"——采纳者真正要问的是"上游动没动、要不要重新采纳"，只好手工 diff shipped 模板与 origin/main。② `--adopt <file>` 无法单文件预览。③ adopt 顺手改 manifest 不吭声。④ 跨项目 D 命名空间缺失：radiant 引用 govrail:D24 被判本地悬空/孤儿，无合法外部引用语法。
- **状态**：已决
- **决定**：① **采纳溯源**：init/adopt 在 manifest 记录每个实际落地模板文件的 sha256（`templates` 字段；项目自有文件不记——没有采纳就没有重采纳）；`--upgrade` 对差异文件做三向判定：local==记录 → **UPSTREAM MOVED**（你的副本自采纳后未动，`--adopt <rel>` 可安全取新模板）/ local≠记录且≠当前 → **BOTH MOVED**（你的定制与上游演化并存，手工合并）/ 无记录（旧 manifest）→ 维持含糊措辞并注明"no adoption hash recorded"；`--upgrade --json` 输出 `era` + `adoptable`。**未定制副本的安全重采纳**：`--adopt` 对"存在但与采纳哈希逐字节相等"的文件允许替换（那不是项目的内容，是旧模板的残影——替换零丢失），定制文件仍永不覆盖。② `--adopt <file> --preview`：缺失文件展示将落地内容、已有文件展示替换 diff，零写入、manifest 不动。③ adopt 修改 manifest 时显式申报（"manifest updated — N adopted, M re-adopted; template hashes recorded"）。④ **`govrail:D<n>` 为唯一合法外部引用命名空间**：audit-notes 的悬空检查、verify-decisions 的孤儿计算、note check 的校验统一**剥离**外部引用后再提取本地 D（govrail:D24 ≠ 本地 D24，既不误报悬空、也不掩盖本地孤儿）；`note new --ref govrail:D24` 接受为外部引用（记录、不本地校验、明示）。
- **被否**：任意前缀外部命名空间（`foo:D1`）——为拼写错误开静默后门，只认 govrail:（唯一已知的外部决策表）；升级时自动重采纳全部 UPSTREAM MOVED——批量替换跨多个文件时应有人看一眼 preview；manifest 记录模板全文哈希以外的内容（如时间戳）——判定只需字节身份。

## D35 — 小修轮：裸预览自解释、版本对齐防再犯、索引滞后记档

- **问题**：① 裸 `--adopt --preview` 只打横幅——可采纳/已漂移的清单明明在 `--upgrade` 里，预览入口不自解释。② HIGHLIGHTS 段落标题预写 0.12.3、轮子实发 0.13.0（同类二犯：手预测版本 vs release-please 裁决），`whatsnew --since 0.12.2` 读起来像差一版；pip 首跑因索引未同步漏装 0.13.0（同因不同症）。
- **状态**：已决
- **决定**：① 裸预览打印漂移清单摘要（`adoptable: N missing, M drifted`）并跨引 `--upgrade`（逐文件 diff）与 `--adopt <file> --preview`（单文件）。② HIGHLIGHTS 标题对齐轮子版本；**tag 覆盖守卫测试**：每个 ≥0.12.0 的已发布 tag 必须有对应 HIGHLIGHTS 段落，版本错位即红——从"事后对齐"变"机械防再犯"。③ CONTRIBUTING 发布节记档 PyPI 索引滞后约一分钟、首跑可能漏装、重试再疑。
- **被否**：whatsnew 运行时给错位段落加注——那是给错位打补丁而不是消灭错位；守卫测试覆盖 0.12.0 之前的 tag——HIGHLIGHTS 诞生于 0.12.0，之前的段落不存在是事实不是缺陷。
