# HotSpot 编译指南

## 1 环境要求

### 1.1 必需工具

| 工具 | 版本要求 | 说明 |
|------|----------|------|
| CMake | >= 3.15 | 构建系统 |
| C 编译器 | C99 标准 | GCC, Clang, MSVC 等 |

### 1.2 可选依赖

| 库 | 版本 | 说明 | 加速效果 |
|---|------|------|----------|
| BLAS | - | Basic Linear Algebra Subprograms | 2-5x |
| LAPACK | - | Linear Algebra Package | 2-5x |
| SuperLU | - | 稀疏矩阵求解库 | 显著 (稀疏矩阵) |

## 2 Windows 平台编译

### 2.1 使用 CMake GUI

1. 下载并安装 CMake (https://cmake.org/download/)
2. 打开 CMake GUI
3. 设置源码目录：`E:\code\cpp\HotSpot`
4. 设置构建目录：`E:\code\cpp\HotSpot\build`
5. 点击 "Configure" 选择编译器 (Visual Studio 或 MinGW)
6. 点击 "Generate" 生成项目文件
7. 打开生成的项目文件，编译解决方案

### 2.2 使用命令行

```powershell
# 创建构建目录
mkdir build
cd build

# 配置项目
cmake .. -G "Visual Studio 17 2022" -A x64

# 编译
cmake --build . --config Release

# 安装 (可选)
cmake --install . --config Release
```

### 2.3 使用 MSBuild

```powershell
msbuild HotSpot.sln /p:Configuration=Release /p:Platform=x64
```

## 3 Linux/Unix 平台编译

### 3.1 基本编译步骤

```bash
# 创建构建目录
mkdir build
cd build

# 配置项目
cmake ..

# 编译
make -j$(nproc)

# 安装 (可选)
sudo make install
```

### 3.2 指定安装路径

```bash
cmake .. -DCMAKE_INSTALL_PREFIX=/usr/local/hotspot
make
sudo make install
```

### 3.3 使用 Ninja 构建系统

```bash
cmake .. -G Ninja
ninja
```

## 4 macOS 平台编译

### 4.1 使用 Homebrew 安装依赖

```bash
brew install cmake openblas lapack
```

### 4.2 编译步骤

```bash
mkdir build
cd build

# 配置 (使用 Homebrew 的 BLAS/LAPACK)
cmake .. -DCMAKE_BUILD_TYPE=Release

# 编译
make -j$(sysctl -n hw.ncpu)
```

## 5 配置选项

CMake 提供多种配置选项：

### 5.1 基本选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `CMAKE_BUILD_TYPE` | Release | 构建类型 (Debug/Release) |
| `CMAKE_INSTALL_PREFIX` | /usr/local | 安装路径 |

### 5.2 性能优化选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `ENABLE_BLAS` | OFF | 启用 BLAS 加速 |
| `ENABLE_LAPACK` | OFF | 启用 LAPACK 加速 |
| `ENABLE_OPENMP` | OFF | 启用 OpenMP 并行化 |

### 5.3 特性选项

| 选项 | 默认值 | 说明 |
|------|--------|------|
| `ENABLE_GRID` | ON | 启用网格模型 |
| `ENABLE_BLOCK` | ON | 启用块级模型 |
| `ENABLE_MICROCHANNEL` | OFF | 启用微通道冷却 |

### 5.4 配置示例

```bash
# 启用所有优化
cmake .. \
    -DCMAKE_BUILD_TYPE=Release \
    -DENABLE_BLAS=ON \
    -DENABLE_LAPACK=ON \
    -DENABLE_OPENMP=ON

# 启用微通道冷却
cmake .. -DENABLE_MICROCHANNEL=ON
```

## 6 验证安装

### 6.1 检查编译产物

构建成功后，在 `build/bin/` 目录下应生成以下可执行文件：

```
build/bin/
|-- hotspot.exe        # 主仿真程序
|-- hotfloorplan.exe   # 平面规划工具
```

### 6.2 运行测试

```bash
cd build

# 运行示例测试
./bin/hotspot.exe -c ../template.config -f ../examples/example1/test.flp \
    -p ../examples/example1/test.ptrace -o test.ttrace

# 检查输出
cat test.ttrace
```

## 7 常见问题

### 7.1 CMake 找不到编译器

**问题：** CMake 报错 "Could not find CMake Determine Compiler"

**解决方案：**
- 确保已安装 C 编译器 (GCC, Clang, MSVC)
- 将编译器路径添加到环境变量 PATH
- 重新启动 CMake GUI 或终端

### 7.2 链接 BLAS/LAPACK 失败

**问题：** 链接时报错找不到 BLAS/LAPACK 符号

**解决方案：**
- 在 Linux 上安装开发包：`sudo apt install libblas-dev liblapack-dev`
- 在 macOS 上使用 Homebrew：`brew install openblas lapack`
- 或禁用 BLAS/LAPACK 选项：`-DENABLE_BLAS=OFF -DENABLE_LAPACK=OFF`

### 7.3 MSVC 编译警告

**问题：** 大量关于 `register` 关键字的警告

**解决方案：** 这是预RTL代码的兼容性问题，不影响功能。添加编译选项忽略警告：

```cmake
add_compile_options(/W3)
```

### 7.4 构建时间过长

**问题：** 编译时间很长

**解决方案：**
- 使用多核并行编译：`make -j$(nproc)`
- 使用 Ninja 构建系统：`cmake -G Ninja`
- 只编译必要的模块

## 8 交叉编译

### 8.1 Windows 交叉编译 (Linux)

```bash
# 安装交叉编译工具
sudo apt install mingw-w64

# 配置 CMake
cmake .. \
    -DCMAKE_SYSTEM_NAME=Windows \
    -DCMAKE_C_COMPILER=x86_64-w64-mingw32-gcc \
    -DCMAKE_RC_COMPILER=x86_64-w64-mingw32-windres
```

### 8.2 ARM 交叉编译 (Linux)

```bash
# 安装 ARM 工具链
sudo apt install gcc-arm-linux-gnueabihf

# 配置 CMake
cmake .. \
    -DCMAKE_SYSTEM_NAME=Linux \
    -DCMAKE_C_COMPILER=arm-linux-gnueabihf-gcc
```

## 9 卸载

```bash
cd build

# 卸载 (如果支持)
sudo make uninstall

# 或手动删除
rm -rf build
```

## 10 获取帮助

- CMake 官方文档：https://cmake.org/documentation/
- HotSpot 项目主页：https://lava.cs.virginia.edu/hotspot/
