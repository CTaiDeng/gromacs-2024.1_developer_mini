# AGENTS 指南（派生约束｜最高规范）

本文件为本仓库（GROMACS 派生版）的最高级协作规范（“最高宪法”）。其约束适用于本目录树内的所有工作（人类与智能助手）。更深层目录如另有 `AGENTS.md`，以更深层为准覆盖本文件冲突处。

## 沟通与语言
- 默认使用简体中文沟通与答复。

## 派生与合规模块（必须遵守）
- 非官方声明：本仓库为 GROMACS 的非官方派生版，与上游无隶属或担保关系。
- 许可遵循：本仓库整体采用 GPL-3.0；上游版权与致谢保留。
- 文件要求：根目录必须存在 `LICENSE`、`CITATION.cff`、`README`；`README` 顶部需包含：
  - 沟通语言说明（中文或等价英文；中文包含“中文/简体/沟通/交流”等关键词其一；英文等价如 “Simplified Chinese”/“communicates by default” 等）
  - 派生/非官方声明（中文或等价英文；中文包含“派生/衍生/非官方”等关键词其一；英文等价如 “non‑official”、“unofficial”、“derivative/fork” 等）
- 禁止“官方”误导：文档与提交信息不得宣称“官方/official”身份；若难以避免（如上游原文），需在显著位置（README 顶部）加以非官方声明进行冲抵。
- 二进制分发合规：若对外分发二进制，需满足 GPL-3.0 的源代码提供与同许可证分发义务（须附带或提供完整对应源代码的获取方式；衍生作品在 GPL-3.0 下分发）。

## Git 提交流程约束（强制）
- Hooks 不进行任何对文档或代码的自动修改/提醒（pre-commit 为 no-op）。
- 严禁任何 Git Hooks 对知识库进行写入型操作（包括但不限于重命名、改内容、批量格式化）：
  - 知识库路径：`my_docs/project_docs`（其中 `kernel_reference` 子目录为只读外部参考）。
  - 知识库的任何变更只能通过“明确指令的脚本执行”或“人工手动操作”。
  - 允许的 Hooks 行为仅限于与提交元数据相关的非侵入性处理（例如生成提交信息）；不得触碰仓库文件。
- 合规与格式化通过“手动指令”执行：
  - 文档尾注：`python3 my_scripts/ensure_timestamp_doc_license_footer.py`
  - 文档对齐：`python3 my_scripts/align_prefix_to_doc_date_v2.py`
  - 文档头部样式（作者/日期/版本）对齐：`python3 my_scripts/align_my_documents.py`
  - 头注整合：`python3 my_scripts/compliance/add_gpl3_headers.py <files/dirs>`
  - 其他审查脚本按需手动运行。

## 开发者操作建议
- 启用钩子与模板：
  - `git config core.hooksPath .githooks`
  - `git config commit.template .githooks/.git-commit-template.txt`
- 提交信息建议使用 `my_scripts/gen_commit_msg_googleai.py` 自动生成（无 Key 也可离线摘要）。

## 源代码头注规范（MUST）
- 许可头注：统一采用 GPL-3.0，头部需包含：
  - `SPDX-License-Identifier: GPL-3.0-only`
  - 版权行：
    - `Copyright (C) 2010- The GROMACS Authors`
    - `Copyright (C) 2025 GaoZheng`
  - GPL-3.0 许可说明（自由软件/无担保/许可证链接）。
- 自动化工具：
  - PowerShell：`my_scripts/compliance/add_gpl3_headers.ps1`
  - Python：`my_scripts/compliance/add_gpl3_headers.py`
  - 二者仅作用于源码文件（不会处理 Markdown），保留 shebang 与编码行，支持整合已有 GROMACS LGPL 头注为统一格式。

## 文档与目录约定（知识库/外部参考）
- `my_docs/project_docs`：项目知识库（受仓库脚本维护，允许写入）。
- `my_docs/project_docs/kernel_reference`：外部知识参考（只读）。约束如下：
  - 不纳入 `my_scripts/gen_my_docs_index.py` 的索引输出；
  - 不参与写入型自动化脚本（如 `align_my_documents.py`、`ensure_summaries.py`）的遍历与改写；
  - 文档尾部许可声明添加脚本 `my_scripts/ensure_timestamp_doc_license_footer.py` 明确不适用该目录；
  - 提交信息生成脚本 `my_scripts/gen_commit_msg_googleai.py` 在生成摘要时忽略该路径的改动；
  - 统一由 `my_scripts/docs_whitelist.json` 管理白名单/排除项，默认已包含该排除路径。

## 文档时间戳规范（强制）
- 适用范围（非递归）：
  - `my_docs/project_docs`
  - `my_project/gmx_split_20250924_011827/docs`
- 文件命名前缀（10 位秒级时间戳）必须以文档内日期为基准：
  - 从文内 `- 日期：YYYY-MM-DD` 读取日期；对应当日本地时间 `00:00:00` 的 Unix 秒作为基准。
  - 若同一目录内存在相同日期的多个文档（重复日期）：从该日期的“当日第一秒”起依次分配 `00:00:00, 00:00:01, 00:00:02, ...`（按文件名标题字典序升序分配）。
  - 该规范仅约束上述两个目录，且不遍历子目录；`kernel_reference` 不适用。
- 手动对齐脚本：`my_scripts/align_prefix_to_doc_date_v2.py`（见 my_docs/AGENTS.md 的“自动化脚本（需手动执行）”）。

## 文档头部样式（强制）
- 适用范围（非递归）：
  - `my_docs/project_docs`（不含子目录 `kernel_reference`）
- 头部紧随首个 H1 标题之后的三行项目：
  - `- 作者：GaoZheng`
  - `- 日期：YYYY-MM-DD`
  - `- 版本：vx.y.z`（小写 `v` + 三段语义版本号；首次创建默认为 `v1.0.0`）
- 约束：
  - 上述三行之间不得留空行；头部块之后留一行空行。
  - 若缺少“版本”行，首次补齐为 `- 版本：v1.0.0`；若已存在符合格式的版本行，保持不变。
- 手动对齐脚本：
  - `python3 my_scripts/align_my_documents.py`（对齐作者/日期/版本行与头部空行）

- AI 助手知识库引用范围：当未明确指定路径而笼统提及“知识库”时，默认包含 `my_docs/project_docs` 及其全部递归子目录（包含只读子目录 `kernel_reference`）；但仍须遵守其只读属性与上述索引/写入排除规则。如需临时排除此子目录，请在指令或脚本中显式注明。

## 例外与裁量
- 若确有合理理由（例如上游文档保留），可在 README 顶部保持非官方声明以对冲相关表述。
- 对合规检查有误报时，优先提交修正 PR 至 `my_scripts/check_derivation_guard.py`；紧急情况下可临时 `--no-verify`，并在后续补齐整改。
- 操作授权原则（最高）
  - 对 `my_docs/project_docs` 的任何“写入型”改动（含重命名、内容更新、批量脚本处理），必须在指令中显式给出目标文档的仓库相对路径（例如：`my_docs/project_docs/1760284819_论纤维丛的静态统一性：作为点集拓扑与离散拓扑之桥梁的传统微分几何.md`）。
  - 未显式指明相对路径的泛化指令（如“修改知识库/同步知识库”）无权更改 `my_docs/project_docs` 下的文档。
  - 本原则优先级最高；`kernel_reference` 目录仍为只读并排除一切写入型脚本。
