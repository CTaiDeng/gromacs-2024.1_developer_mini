# Git Hooks 调整记录（经验与复现）

本记录总结本仓库近期对 Git 钩子的调整与落地经验，便于快速复用与团队协作。遵循仓库 AGENTS 指南：不在钩子中进行任何自动修改/格式化；合规与格式化通过手动脚本执行。

## 变更摘要
- `pre-commit`：保持 no-op（不做任何自动修改或校验），符合仓库“钩子不自动更改”的最高规范。
- `prepare-commit-msg`：
  - 当提交信息为空（去除注释与空白）时，自动填充占位符 `update`；
  - 若提交信息为 `update`，尝试调用 `my_scripts/gen_commit_msg_googleai.py` 生成更合适的提交信息；
  - 生成失败或未产生输出时，保留为 `update`；
  - 统一提交语言默认中文（`COMMIT_MSG_LANG=zh`）。
- Python 解释器优先级：
  - Windows（.bat）版本优先使用仓库本地虚拟环境：`.venv\\Scripts\\python.exe`；
  - Bash 版本优先 `.venv/Scripts/python.exe`（Windows Git Bash 等）或 `.venv/bin/python`，再回落到系统 `python3`/`python`。
- 本地 Git 配置：
  - `core.hooksPath` 指向 `.githooks`；
  - `commit.template` 指向 `.githooks/.git-commit-template.txt`（模板默认内容为 `update`）。

## 启用与复现步骤
1) 配置仓库级 Git 选项（已设置，可重复执行）：
```
git config --local core.hooksPath .githooks
git config --local commit.template .githooks/.git-commit-template.txt
```
2) 确认本地虚拟环境存在（可选，但推荐）：
   - Windows: `.venv\\Scripts\\python.exe`
   - Linux/macOS: `.venv/bin/python`
3) 准备提交信息生成脚本（可选）：`my_scripts/gen_commit_msg_googleai.py`
   - 无需 API Key 也可离线摘要；如需云能力，可在环境中提供：`GEMINI_API_KEY`/`GOOGLE_API_KEY`/`GOOGLEAI_API_KEY`。

## 工作原理（prepare-commit-msg）
- 读取 Git 传入的消息文件；若实际内容为空，写入 `update`。
- 若当前内容为 `update`，尝试调用提交信息生成脚本：
  - Windows：优先使用 `.venv\\Scripts\\python.exe`；否则回落到 `py -3`/`python3`/`python`。
  - Bash：依次尝试 `.venv/Scripts/python.exe`、`.venv/bin/python`、`python3`、`python`、`py -3`。
- 若生成器输出非空，则覆盖消息文件；否则保持 `update`。
- 跳过 `merge`/`squash` 场景。

## 验证方式
- 最小验证：
  - 执行 `git commit`（不手动填写信息），提交消息文件应至少包含一行 `update`。
- 生成器验证：
  - 将第一行保留为 `update` 或留空，然后 `git commit`；若脚本可运行并返回内容，最终提交信息应被替换为脚本输出。
- 调试输出：
  - 设置环境变量 `COMMIT_MSG_DEBUG=1` 可让钩子在失败时输出更多信息（Bash 版本对标准错误更宽松）。

## 故障排查
- “钩子未生效”：
  - `git config --local --get core.hooksPath` 应返回 `.githooks`。
- “未使用虚拟环境 Python”：
  - 确认 `.venv` 路径是否存在对应解释器；Windows 路径为 `.venv\\Scripts\\python.exe`。
- “生成器未输出/失败”：
  - 脚本路径：`my_scripts/gen_commit_msg_googleai.py` 是否存在且可执行；
  - 如需联机能力，检查 `GEMINI_API_KEY`/`GOOGLE*_API_KEY` 是否配置；
  - 临时保底：保留 `update` 直接提交。

## 合规与约束
- 严格遵守仓库 AGENTS 指南：
  - Hooks 不进行任何自动修改/提醒（pre-commit 为 no-op）。
  - 合规脚本与格式化通过“手动指令”执行，例如：
    - `python3 my_scripts/ensure_timestamp_doc_license_footer.py`
    - `python3 my_scripts/align_prefix_to_doc_date_v2.py`
    - `python3 my_scripts/compliance/add_gpl3_headers.py <files/dirs>`
- 文档与知识库目录（如 `my_docs/project_docs`）的写入有额外授权与时间戳规范要求；本次变更仅涉及钩子与配置，不触达上述目录。

## 相关文件
- `.githooks/pre-commit`
- `.githooks/pre-commit.bat`
- `.githooks/prepare-commit-msg`
- `.githooks/prepare-commit-msg.bat`
- `.githooks/.git-commit-template.txt`

若需在 README 增加“钩子与提交规范”章节或将本文链接到 README 顶部导航，请告知。
