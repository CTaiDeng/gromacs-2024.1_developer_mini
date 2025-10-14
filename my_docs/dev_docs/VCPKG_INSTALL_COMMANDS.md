## 摘要
vcpkg install commands ====================== Run these from the repository root:

vcpkg install commands
======================
Run these from the repository root:

.\vcpkg.exe install fftw3[core,threads]:x64-windows
.\vcpkg.exe install openblas:x64-windows lapack-reference:x64-windows

CMake configuration tips
------------------------
If ImageMagick is installed, point CMake to it when configuring GROMACS:

cmake -DGMX_IMAGE_CONVERT="C:/Program Files/ImageMagick-7.1.2-Q16-HDRI/magick.exe" ...

---

