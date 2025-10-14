# AGENTS（my_docs 文档规范）

- 作者：GaoZheng
- 日期：2025-10-13

#### ***注：“O3理论/O3元数学理论/主纤维丛版广义非交换李代数(PFB-GNLA)”相关理论参见： [作者（GaoZheng）网盘分享](https://drive.google.com/drive/folders/1lrgVtvhEq8cNal0Aa0AjeCNQaRA8WERu?usp=sharing) 或 [作者（GaoZheng）开源项目](https://github.com/CTaiDeng/open_meta_mathematical_theory) 或 [作者（GaoZheng）主页](https://mymetamathematics.blogspot.com)，欢迎访问！***

## 目标与范围
- 目录范围：`my_docs` 下的 `dev_docs` 与 `project_docs`。
- 目标：统一文档结构与命名，支持自动化脚本处理，提升一致性与可读性。

## 文档结构规范（MUST）
- 固定头部，顺序不可缺：
  1) `# {标题}`（H1）
  2) `- 作者：{姓名}`（默认 GaoZheng）
  3) `- 日期：YYYY-MM-DD`（ISO 日期）
  4) O3 参考提示块：`#### ***注：...***`
  5) `## 摘要`（建议 180–240 字，脚本可自动生成/归一化）
- 头部各块之间与正文之间，保持单空行。
 - 摘要段落结束后必须加入水平分隔线 `---`；
   - 摘要内容与 `---` 之间仅保留 1 个空行；
   - `---` 与后续正文之间仅保留 1 个空行。

## 许可尾注规范（MUST）
- 适用范围：所有命名为 `10位Unix时间戳_*.md` 的文档（含 `my_docs/project_docs` 与 `my_project/*/docs`；`kernel_reference` 例外）。
- 尾注内容（末尾追加），并保持格式：
  - `---` 前后各保留 1 个空行；
  - 具体块：
    - `**许可声明 (License)**`
    - `Copyright (C) {year|year-year2} GaoZheng`
      - `{year}` = 文档创立年份（优先取文件名 10 位时间戳，否则取首次提交年/mtime）
      - 若后续修改年份 `{year2}` > `{year}`，显示为 `{year}-{year2}`
    - CC BY-NC-ND 4.0 中文链接说明行
- 自动化：由 `my_scripts/ensure_timestamp_doc_license_footer.py` 在提交前自动补全/规范（幂等）。

## 摘要处理优先级（MUST/SHOULD）
- [MUST] 若原文已有摘要，标准化为 `## 摘要` 标题，不改动内容。
- [SHOULD] 若存在“#### 摘要/摘要：”等非标准写法，脚本自动合并为 `## 摘要`。
- [SHOULD] 若缺失摘要，脚本自动生成一段简要摘要（约 180–240 字）。

## 命名与时间戳（MUST/SHOULD）
- [MUST] 文件名：`{10位Unix时间戳}_{中文标题}.md`，10 位前缀同时作为文档 ID。
- [MUST] `project_docs` 下若出现同秒冲突，按 `-1s` 依次回退直至唯一（由脚本保障）。
- [MUST] H1 标题中不得保留“时间戳_”前缀（脚本自动去除）。
- [SHOULD] 提交前由脚本自动对齐文件日期行与 ID 来源，保持稳定。

## 索引与展示（MUST/SHOULD）
- [MUST] `my_docs/README.md` 展示 `project_docs` 文件，默认按 10 位时间戳升序。
- [SHOULD] 摘要过长时在索引中换行展示；自动化由 `gen_my_docs_index.py` 完成。

## 临时文件管理（MUST）
- 临时文件示例：`tmp_gen_idx_before.txt`、`tmp_*.txt`、`*.tmp`、`*.bak` 等。
- 约束：
  - 不纳入提交；开发时可临时使用，用后删除。
  - 若需长期保留，应转为正式文档（含头部/结构/摘要）。
  - `.gitignore` 保持通配排除（如 `tmp_*`, `*.tmp`, `*.bak`）。

## 自动化脚本（需手动执行）
- `ensure_timestamp_doc_license_footer.py`
  - 为“10位时间戳_*.md”追加许可尾注（已声明 kernel_reference 例外）。
- `gen_my_docs_index.py`
  - 生成/刷新 根目录 `README.md`（UTF-8 with BOM）。
- `ensure_summaries.py`
  - 在缺失时补全 `## 摘要` 区块。
 - `align_dates_to_filename_prefix.py`
   - 将文内日期对齐为文件名前缀对应日期（默认 dry-run，需 `--apply` 生效）。
 - `align_prefix_to_doc_date_v2.py`
   - 将文件名前缀对齐为文内日期（强规则，非递归）：
     - 以文内 `- 日期：YYYY-MM-DD` 为基准取当天 `00:00:00` 秒。
     - 同一目录内若日期重复，则从当日第一秒起依次分配 `+0, +1, +2 ...` 秒（按文件名标题字典序升序）。
     - 作用于 `my_docs/project_docs` 与 `my_project/gmx_split_20250924_011827/docs`。

## 目录与权限
- `my_docs/project_docs`：项目知识库（可写）。
- `my_docs/project_docs/kernel_reference`：外部参考（只读，排除写入型脚本遍历）。

## 编码规范（重点）
- 为兼容 Windows 传统控制台编码，`my_docs/AGENTS.md` 与 根目录 `README.md` 使用 UTF-8 with BOM 保存。
- 其他 Markdown 文件建议使用 UTF-8；如需在控制台直接阅读，也可手动转换为 UTF-8 with BOM。

## 写入协议（重要）
- 当遇到如下指令时：
  - “将下文基于文档命名规范写入 my_docs\project_docs，先保持内容不变写入创建的文件，然后应用全部文档规范调整”
- 协议解释：
  - “保持内容不变”不包括对“标题（H1）与摘要（## 摘要）”的规范化调整。
  - 允许并优先执行：
    - 标题归一（去除时间戳前缀、确保置顶 H1）；
    - 摘要标准化为 `## 摘要`，并去除其标题后的空行；
    - 头部顺序与空行规范（H1 下一空行；作者与日期相邻无空行；日期与 O3 提示之间恰一空行）。

## 附加命名规范
- [MUST] 文件名与 H1 标题不得包含“标题：/标题:”前缀；脚本自动清理，已有文件将被批量迁移与重命名。

以上规范在仓库脚本持续演进下保持兼容与更新。





