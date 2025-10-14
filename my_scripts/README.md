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

数据
- data/charmm36-jul2021.ff：用于 CHARMM36 力场相关的示例与转换。

维护约定
- 本目录仅保留 WSL/bash 与 Python 脚本；不再接受 .ps1 新脚本。
- 新增脚本请配套最简 README 说明输入/输出、依赖与用法。
