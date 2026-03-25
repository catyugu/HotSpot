# HotSpot 可执行文件使用指南

## 1 概述

HotSpot 项目编译后生成两个主要可执行文件：

| 可执行文件 | 功能 | 源码位置 |
|-----------|------|----------|
| `hotspot.exe` | 热仿真器主程序 | [`src/hotspot.c`](detail/hotspot.md) |
| `hotfloorplan.exe` | 热感知平面规划工具 | [`src/hotfloorplan.c`](detail/hotfloorplan.md) |

## 2 hotspot.exe - 热仿真器

### 2.1 功能说明

hotspot.exe 是 HotSpot 的核心热仿真程序，从功耗追踪文件读取功耗数据，计算相应的温度值并输出到温度追踪文件。

**主要功能：**
- 稳态热分析
- 瞬态热分析
- 块级模型 (Block Model) 和网格模型 (Grid Model) 支持
- 3D IC 热仿真
- 微通道冷却仿真
- 自然对流散热分析

### 2.2 命令行用法

```
Usage: hotspot.exe -f <file> -p <file> [-o <file>] [-c <file>] [-d <file>] [options]
```

### 2.3 必需参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `-f <file>` | 平面规划输入文件 (.flp) | `-f test.flp` |
| `-p <file>` | 功耗追踪输入文件 (.ptrace) | `-p power.ptrace` |

**注意：** 当使用 `-c` 指定层配置文件 (.lcf) 时，`-f` 参数被忽略。

### 2.4 可选参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-o <file>` | 温度追踪输出文件 (.ttrace) | 仅输出稳态温度到 stdout |
| `-c <file>` | 配置文件 | 无 |
| `-d <file>` | 配置导出文件 | 不导出 |
| `-detailed_3D <on/off>` | 异构 RC 模型 | off |
| `-use_microchannels <0/1>` | 启用微通道冷却 | 0 |
| `-materials_file <file>` | 材料属性文件 | 使用默认材料 |

### 2.5 配置参数选项

可通过配置文件或命令行指定的参数：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `-model_type <type>` | block | 热模型类型：`block` 或 `grid` |
| `-ambient <temp>` | 313.15 | 环境温度 (K) |
| `-dt <interval>` | 1e-4 | 瞬态时间步长 (s) |
| `-sampling_intvl <interval>` | 1e-3 | 采样间隔 (s) |
| `-init_temp <temp>` | 300.0 | 初始温度 (K) |
| `-base_proc_freq <freq>` | 1e9 | 处理器基础频率 (Hz) |
| `-steady_file <file>` | - | 稳态温度输出文件 |
| `-grid_steady_file <file>` | - | 网格稳态温度输出文件 |
| `-grid_transient_file <file>` | - | 网格瞬态温度输出文件 |
| `-grid_layer_file <file>` | - | 层配置文件 (.lcf) |
| `-package_model_used <0/1>` | 0 | 启用封装模型 |
| `-r_convec <value>` | - | 对流热阻 (K/W) |
| `-grid_rows <num>` | 64 | 网格行数 |
| `-grid_cols <num>` | 64 | 网格列数 |

### 2.6 使用示例

**示例 1：基本稳态分析**

```bash
hotspot.exe -f test.flp -p power.ptrace
```

**示例 2：瞬态分析**

```bash
hotspot.exe -f test.flp -p power.ptrace -o temp.ttrace -c hotspot.config
```

**示例 3：使用网格模型**

```bash
hotspot.exe -f test.flp -p power.ptrace -o temp.ttrace -model_type grid
```

**示例 4：3D IC 仿真**

```bash
hotspot.exe -c layer.lcf -p power.ptrace -o temp.ttrace -detailed_3D on
```

**示例 5：微通道冷却仿真**

```bash
hotspot.exe -c layer.lcf -p power.ptrace -o temp.ttrace \
    -detailed_3D on -use_microchannels 1
```

**示例 6：导出配置**

```bash
hotspot.exe -f test.flp -p power.ptrace -d dump.config
```

### 2.7 输出格式

**稳态温度输出 (stdout)：**

```
steady state temperatures: (in K)
CPU     350.23
L2      345.67
Memory  320.15
```

**温度追踪文件 (.ttrace)：**

```
time    CPU     L2      Memory
0.0     300.15  298.15  295.15
0.001   305.22  303.87  297.34
0.002   310.45  308.22  299.56
```

### 2.8 错误处理

常见错误及解决方案：

| 错误信息 | 原因 | 解决方案 |
|----------|------|----------|
| `required parameter p_infile missing` | 未指定功耗文件 | 使用 `-p` 参数指定 .ptrace 文件 |
| `Either LCF or FLP file must be specified` | 未指定平面规划或层配置文件 | 使用 `-f` 或 `-c` 参数 |
| `no power numbers in trace file` | 功耗文件为空或格式错误 | 检查 .ptrace 文件格式 |
| `-do_detailed_3D can only be used with -model_type grid` | 3D 选项未与网格模型同时使用 | 添加 `-model_type grid` |

## 3 hotfloorplan.exe - 平面规划工具

### 3.1 功能说明

hotfloorplan.exe 是一个热感知的平面规划工具，读取功能块的面积、长宽比和连接信息，结合功耗数据输出优化后的平面规划。

**主要功能：**
- 热感知布局优化
- 连线延迟计算
- L2 缓存包装支持

### 3.2 命令行用法

```
Usage: hotfloorplan.exe -f <file> -p <file> -o <file> [-c <file>] [-d <file>] [options]
```

### 3.3 必需参数

| 参数 | 说明 | 示例 |
|------|------|------|
| `-f <file>` | 功能块描述文件 | `-f ev6.desc` |
| `-p <file>` | 平均功耗文件 | `-p avg.p` |
| `-o <file>` | 平面规划输出文件 | `-o result.flp` |

### 3.4 可选参数

| 参数 | 说明 | 默认值 |
|------|------|--------|
| `-c <file>` | 配置文件 | 无 |
| `-d <file>` | 配置导出文件 | 不导出 |
| `-materials_file <file>` | 材料属性文件 | 使用默认材料 |

### 3.5 使用示例

**基本用法：**

```bash
hotfloorplan.exe -f ev6.desc -p avg.p -o result.flp
```

**指定配置文件：**

```bash
hotfloorplan.exe -f ev6.desc -p avg.p -o result.flp -c hotspot.config
```

**导出配置：**

```bash
hotfloorplan.exe -f ev6.desc -p avg.p -o result.flp -d dump.config
```

### 3.6 输出格式

**FIG 格式输出 (stdout)：**

```
# FIG output for tofig.pl
```

**统计信息 (stdout)：**

```
Floorplan Statistics:
Total area: X.XX mm^2
Max temperature: XXX.XX K
...
```

**连线延迟信息 (stdout)：**

```
printing wire delay between blocks for global and intermediate metal layers:
(in X.X GHz cycles)
name1   name2   global   intermediate
CPU     L2      0.123    0.045
```

## 4 配置文件格式

配置文件为文本格式，每行一个参数：

```
# 注释行
model_type block
ambient 313.15
dt 0.0001
sampling_intvl 0.001
```

### 4.1 模板配置文件

项目提供两个模板配置：

| 文件 | 用途 |
|------|------|
| `template.config` | 默认热仿真配置 |
| `package.config` | 封装模型配置 |

## 5 文件格式详解

### 5.1 平面规划文件 (.flp)

详细格式说明见 [`doc/detail/flp.md`](detail/flp.md)。

**格式：**
```
name    width   height  center_x  center_y
CPU     10.0    10.0    5.0      5.0
L2      5.0     5.0     15.0     5.0
```

### 5.2 功耗追踪文件 (.ptrace)

**格式：**
```
time    block1_power  block2_power  ...
0.0     50.0         10.0         ...
0.001   75.0         15.0         ...
```

### 5.3 层配置文件 (.lcf)

用于 3D IC 仿真，定义每层的物理和热属性。

## 6 模型选择指南

### 6.1 块级模型 vs 网格模型

| 特性 | 块级模型 | 网格模型 |
|------|----------|----------|
| 计算速度 | 快 | 慢 |
| 内存占用 | 低 | 高 |
| 温度精度 | 块平均值 | 空间分布 |
| 适用场景 | 早期探索 | 详细分析 |

**建议：** 除非需要详细的温度分布或功能块数量很多导致块模型过慢，否则使用块级模型。

### 6.2 选择标准

- 功能块温度均匀分布假设可接受 → 块级模型
- 需要功能块内部温度梯度信息 → 网格模型
- 功能块数量很多 (>100) → 网格模型
- 快速迭代设计探索 → 块级模型

## 7 性能优化

### 7.1 加速选项

| 选项 | 说明 | 加速效果 |
|------|------|----------|
| `-ENABLE_BLAS=ON` | 启用 BLAS | 2-5x |
| `-ENABLE_LAPACK=ON` | 启用 LAPACK | 2-5x |
| `-DENABLE_OPENMP=ON` | 启用 OpenMP | 多核并行 |

### 7.2 内存优化

- 网格模型内存占用与 `grid_rows * grid_cols` 成正比
- 适当减小网格尺寸可显著降低内存使用
- 瞬态分析需要额外内存存储时间序列

### 7.3 计算时间估算

| 模型 | 功能块数 | 网格尺寸 | 计算时间 |
|------|----------|----------|----------|
| 块级 | 10 | N/A | <1s |
| 块级 | 100 | N/A | ~10s |
| 网格 | 10 | 64x64 | ~30s |
| 网格 | 100 | 64x64 | ~5min |
