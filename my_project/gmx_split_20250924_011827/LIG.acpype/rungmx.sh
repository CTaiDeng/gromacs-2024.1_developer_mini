# Copyright (C) 2025 GaoZheng
# SPDX-License-Identifier: GPL-3.0-only
# This file is part of this project.
# Licensed under the GNU General Public License version 3.
# See https://www.gnu.org/licenses/gpl-3.0.html for details.

echo 0 | gmx editconf -f LIG_GMX.gro -bt octahedron -d 10 -c -princ
gmx grompp -f em.mdp -c out.gro -p LIG_GMX.top -o em.tpr -v
gmx mdrun -ntmpi 1 -v -deffnm em
gmx grompp -f md.mdp -c em.gro -p LIG_GMX.top -o md.tpr -r em.gro
gmx mdrun -ntmpi 1 -v -deffnm md
