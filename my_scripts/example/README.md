# GROMACS Pipeline Example（WSL）

脚本 `gmx_split_docking.sh` 演示如何将对接得到的复合物分离为配体与受体两部分：

1. 使用 `gmx editconf` 将 PDB 转为 GRO
2. 用 `gmx select` 生成选择组 index
3. 用 `gmx trjconv` 分别导出配体与受体 PDB

输出写入仓库的 `out/` 目录，示例：

```bash
bash my_scripts/example/gmx_split_docking.sh -i res/hiv.pdb -r LIG
```

执行后在 `out/` 下会生成带时间戳的工作子目录，包含拆分结果。

