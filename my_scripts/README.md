my_scripts 脚本清单（WSL 专用）

说明
- 本目录用于存放项目自定义、可复用的脚本与数据，统一面向 WSL/Ubuntu 环境。
- 已移除全部 Windows PowerShell(.ps1) 脚本；请使用 bash 与 Python 脚本。

可用脚本（WSL/Ubuntu）
- install_cmake_wsl.sh：安装/升级 CMake（Kitware 源），并规避 Conda libcurl 警告。
- install_gromacs_wsl.sh：安装 GROMACS（apt 或源码构建，默认 2024.1）。
- install_amber_deps_wsl.sh：用 conda 安装 AmberTools(antechamber) 与 Open Babel。
- generate_hiv_mol2_wsl.sh：从 SMILES/结构文件生成标准 hiv.mol2（含 SUBSTRUCTURE）。
- cgenff_charmm2gmx.py：CGenFF 输出与 GROMACS 格式转换辅助。
- align_my_documents.py：对 my_docs/** 文档进行命名与日期规范化；并在 `my_docs/project_docs` 下强制 10 位数字前缀唯一（视为文档 ID）。若出现同时入库导致的同秒冲突：
  - 以“标题名”正向（升序）排序确定优先级；
  - 优先级最高者保留原秒级时间戳，其余按顺序依次向前回退 1 秒（-1s、-2s…，直至唯一）；
  - 同步更新 Markdown 头部为新规范：`- 作者：...`、`- 日期：YYYY-MM-DD`；兼容旧格式并自动迁移。

使用示例
- 安装 CMake：`bash my_scripts/install_cmake_wsl.sh`
- 安装 GROMACS：`bash my_scripts/install_gromacs_wsl.sh --method source --version 2024.1 -j 8`
- 安装 AmberTools + Open Babel：`bash my_scripts/install_amber_deps_wsl.sh --env amber`
- 生成 hiv.mol2：`bash my_scripts/generate_hiv_mol2_wsl.sh --smiles "C1=CC=CC=C1C(=O)N" --charge 0 --resname LIG --out hiv.mol2`

- 修复 CMake BLAS/NVPL 告警并配置 BLAS/LAPACK：
  - 使用 OpenBLAS（推荐）：`bash my_scripts/fix_cmake_blas_nvpl_wsl.sh --mode openblas`
  - 使用内置 BLAS/LAPACK：`bash my_scripts/fix_cmake_blas_nvpl_wsl.sh --mode internal`
  - 仅抑制 NVPL 查找：`bash my_scripts/fix_cmake_blas_nvpl_wsl.sh --mode suppress`

- 修复 ImageMagick convert 未授权/不可用（WSL）：
  - 默认修复并安装依赖：`bash my_scripts/fix_imagemagick_convert_wsl.sh`
  - 仅策略修复（不安装包）：`bash my_scripts/fix_imagemagick_convert_wsl.sh --no-apt`
  - 恢复修复前策略：`bash my_scripts/fix_imagemagick_convert_wsl.sh --restore`

- 修复 CMake 找不到 Python3 开发组件（WSL）：
  - 自动安装 Python 开发头/库并重新配置：`bash my_scripts/fix_cmake_python3_dev_wsl.sh`
  - 指定 Python 版本（例如 3.10）：`bash my_scripts/fix_cmake_python3_dev_wsl.sh --py 3.10`
  - 指定源码/构建目录：`bash my_scripts/fix_cmake_python3_dev_wsl.sh --source-dir . --build-dir cmake-build-release-wsl`

对齐知识库文档前缀（按文内日期逐秒递延）
- 规则：`- 日期：YYYY-MM-DD` 为真，前缀为当日 00:00:00 起按标题字典序逐秒递增；非递归；跳过 `kernel_reference/` 与 `LICENSE.md`
- 默认运行（my_docs/project_docs 与 my_project/.../docs）：
  - `python3 my_scripts/align_prefix_to_doc_date_v2.py`
- 指定目录（例如仅知识库）：
  - `python3 my_scripts/align_prefix_to_doc_date_v2.py --paths my_docs/project_docs`
- 预览改名（不落盘）：
  - `python3 my_scripts/align_prefix_to_doc_date_v2.py --paths my_docs/project_docs --dry-run`

对齐知识库文档头部（作者/日期/版本 与空行）
- 规则：
  - 头部三行紧随 H1：`- 作者：GaoZheng`、`- 日期：YYYY-MM-DD`、`- 版本：vx.y.z`
  - 三行之间不留空；头部块后留 1 行空行；若缺“版本”，首次补齐为 `v1.0.0`
- 运行：
  - `python3 my_scripts/align_my_documents.py`
  - 仅在知识库目录中补齐“版本：v1.0.0”并整理头部空行（不改动日期值）：
    - `python3 my_scripts/fix_project_docs_header_version.py`

数据
- data/charmm36-jul2021.ff：用于 CHARMM36 力场相关的示例与转换。

维护约定
- 本目录仅保留 WSL/bash 与 Python 脚本；不再接受 .ps1 新脚本。
- 新增脚本请配套最简 README 说明输入/输出、依赖与用法。
