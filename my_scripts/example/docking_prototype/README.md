小型“刚体重定位 + mdrun -rerun”示例（需 gmx CLI）。

演示在 GROMACS 中，使用 subprocess 实现随机位移/转动生成候选姿态，随后通过 `mdrun -rerun` 计算能量，并提取 Protein-Ligand 的短程静电与范德华项进行打分和排序。

准备工作
- 已安装 GROMACS（建议 2021+，推荐 2024.1），`gmx` 在 PATH 中。
- `topol.tpr` 中包含 `energygrps = Protein Ligand`。
- `start.gro` 与 TPR 原子顺序一致，包含 Protein + Ligand。
- `index.ndx` 至少包含 `[ Protein ]` 与 `[ Ligand ]` 两组。

示例最小 MDP 片段（仅用于生成 TPR）：
```
integrator  = steep
nsteps      = 0            ; 仅生成 tpr，rerun 时生效
nstlist     = 20
rlist       = 1.2
coulombtype = Cut-off
rcoulomb    = 1.2
vdwtype     = Cut-off
rvdw        = 1.2
constraints = h-bonds
pbc         = xyz
energygrps  = Protein Ligand
freezegrps  = Protein
freezedim   = Y Y Y
```

开始运行
1) 准备 `topol.tpr / start.gro / index.ndx`
2) 示例命令（WSL/Linux）：
```
python3 my_scripts/example/docking_prototype/dock_minimal.py \
  --tpr path/to/topol.tpr \
  --structure out/gmx_split_YYYYMMDD_HHMMSS/complex.gro \
  --ndx out/gmx_split_YYYYMMDD_HHMMSS/index.ndx \
  --workdir out/dock_run --n-poses 50 --trans 0.5 --rot 20 --jobs 4 --nt 1
```

参数说明（关键项）
- `--tpr`：包含 `Protein` 与 `Ligand` 分组的 TPR
- `--structure`：全体系起始坐标（与 TPR 原子顺序一致）
- `--ndx`：包含 `[ Ligand ]` 分组，用于对配体做刚体变换
- `--n-poses`：生成的候选数量
- `--trans`（nm）：每次变换的随机平移范围 [-trans, trans]
- `--rot`（度）：每次变换的随机转角范围 [-rot, rot]
- `--nt`：每次 mdrun 使用的线程数（建议 1）
- `--jobs`：并发候选数（默认 1）

输出
- 在 `--workdir` 下生成 `candidate_####.gro`、`pose_####.edr/.log`、`energy_####.xvg`、`scores.csv` 等
- 评分定义：`score = (Coul-SR:Protein-Ligand) + (LJ-SR:Protein-Ligand)`，值越小越优

注意事项
- 本示例仅演示刚体随机探索 + rerun 打分流程，若需进一步优化可将 `-rerun` 替换为常规 EM/MD 流程（grompp + mdrun）。
- 若存在 PBC 或索引组定义问题，可能导致分组跨越边界或能量项缺失，请先用 `gmx make_ndx` 与 `gmx energy` 自检。

