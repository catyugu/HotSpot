# HotSpot 快速入门

## 1 环境准备

### 1.1 系统要求

| 要求 | 最低配置 | 推荐配置 |
|------|----------|----------|
| 操作系统 | Windows / Linux / macOS | Windows / Linux / macOS |
| CMake | 3.15+ | 3.15+ |
| C 编译器 | C99 | GCC 9+ / Clang 10+ / MSVC 2019+ |
| 磁盘空间 | 100 MB | 200 MB |
| 内存 | 1 GB | 4 GB+ (用于大网格) |

### 1.2 可选依赖

| 库 | 用途 | 安装建议 |
|---|------|----------|
| BLAS | 矩阵加速 | 建议安装 |
| LAPACK | 线性代数 | 建议安装 |
| Python | 图像生成 | 建议安装 |
| Perl | 图像生成 | 可选 |

## 2 编译 HotSpot

### 2.1 Windows (Visual Studio)

```powershell
# 打开 Developer Command Prompt
mkdir build
cd build
cmake .. -G "Visual Studio 17 2022" -A x64
cmake --build . --config Release
```

### 2.2 Linux / macOS

```bash
mkdir build
cd build
cmake .. -DCMAKE_BUILD_TYPE=Release
make -j$(nproc)
```

### 2.3 验证安装

```bash
# 确认可执行文件生成
ls build/bin/
# 应显示: hotspot.exe, hotfloorplan.exe
```

## 3 运行第一个仿真

### 3.1 准备输入文件

需要准备两个文件：
- **平面规划文件** (.flp) - 定义芯片布局
- **功耗追踪文件** (.ptrace) - 定义功耗变化

### 3.2 使用示例文件

HotSpot 提供了现成的示例：

```bash
cd examples/example1
```

该目录包含：
- `ev6.flp` - EV6 处理器平面规划
- `gcc.ptrace` - GCC 编译功耗追踪

### 3.3 运行仿真

```bash
# 在项目根目录执行
cd E:\code\cpp\HotSpot

# 基本命令格式
build\bin\hotspot.exe -f examples/example1/ev6.flp -p examples/example1/gcc.ptrace
```

### 3.4 查看结果

默认情况下，稳态温度输出到 stdout：

```
Computing steady-state temperatures...
steady state temperatures: (in K)
CPU     350.23
L2      345.67
Memory  320.15
...
```

## 4 完整示例：稳态 + 瞬态分析

### 4.1 创建工作目录

```bash
mkdir my_simulation
cd my_simulation
```

### 4.2 创建平面规划文件 (test.flp)

```
# 格式: name width height center_x center_y
CPU     10.0   10.0   5.0    5.0
L2      5.0    5.0    15.0   5.0
Memory  20.0   10.0   10.0   20.0
```

### 4.3 创建功耗文件 (test.ptrace)

```
# 格式: time block1_power block2_power ...
0.0     50.0   10.0   5.0
0.001   75.0   15.0   7.0
0.002   60.0   12.0   6.0
```

### 4.4 运行稳态分析

```bash
hotspot.exe -f test.flp -p test.ptrace -steady_file steady.txt
```

### 4.5 运行瞬态分析

```bash
# 使用稳态结果作为初始温度
hotspot.exe -f test.flp -p test.ptrace \
    -init_file steady.txt \
    -o transient.ttrace
```

### 4.6 查看输出

生成的 `transient.ttrace` 文件内容：

```
time    CPU     L2      Memory
0.0     300.15  298.15  295.15
0.001   305.22  303.87  297.34
0.002   310.45  308.22  299.56
```

## 5 使用网格模型

### 5.1 为什么使用网格模型

- 更精确的温度分布
- 可以看到功能块内部的温度梯度
- 适合详细热分析

### 5.2 运行网格模型

```bash
hotspot.exe -f test.flp -p test.ptrace \
    -model_type grid \
    -steady_file steady.txt \
    -grid_steady_file grid_steady.txt
```

### 5.3 控制网格精度

```bash
# 高精度 (128x128)
hotspot.exe -f test.flp -p test.ptrace \
    -model_type grid \
    -grid_rows 128 -grid_cols 128

# 低精度 (32x32) - 更快
hotspot.exe -f test.flp -p test.ptrace \
    -model_type grid \
    -grid_rows 32 -grid_cols 32
```

## 6 生成热分布图像

### 6.1 准备工作

需要安装 Python 和 matplotlib：

```bash
pip install matplotlib numpy
```

### 6.2 生成图像

```bash
# 分割网格输出为层级文件
python scripts/split_grid_steady.py grid_steady.txt 4 64 64

# 生成热分布图
python scripts/grid_thermal_map.py test.flp \
    layer0.grid.steady output.png
```

## 7 常见问题

### 7.1 报错 "required parameter p_infile missing"

**原因：** 未指定功耗文件

**解决：** 添加 `-p` 参数：
```bash
hotspot.exe -f test.flp -p test.ptrace
```

### 7.2 温度值异常高/低

**检查项：**
- 功耗单位是否为瓦特 (W)
- 环境温度设置
- 散热器配置

### 7.3 仿真时间过长

**解决方案：**
- 使用块级模型 (`-model_type block`)
- 减小网格尺寸
- 减少 .ptrace 文件的时间步数
- 启用 BLAS/LAPACK 加速

### 7.4 内存不足

**解决方案：**
- 减小网格尺寸
- 使用块级模型
- 减少仿真层数

## 8 下一步

- 阅读 [executables.md](../summary/executables.md) 了解完整选项
- 阅读 [examples.md](../summary/examples.md) 学习 6 个完整示例
- 阅读 [configuration.md](configuration.md) 了解配置参数
- 阅读 [compilation.md](compilation.md) 了解高级编译选项

## 9 参考命令速查

```bash
# 基本稳态
hotspot.exe -f <flp> -p <ptrace>

# 瞬态 + 输出到文件
hotspot.exe -f <flp> -p <ptrace> -o <ttrace>

# 网格模型
hotspot.exe -f <flp> -p <ptrace> -model_type grid

# 3D IC 仿真
hotspot.exe -c <lcf> -p <ptrace> -model_type grid -detailed_3D on

# 热感知平面规划
hotfloorplan.exe -f <desc> -p <power> -o <flp>
```
