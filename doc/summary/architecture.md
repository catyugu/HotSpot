# HotSpot 系统架构概述

## 1 整体架构

HotSpot 是一个预RTL级别的热仿真器，采用模块化设计，主要由以下几个核心模块组成：

```
hotspot.exe                    # 主程序入口
hotfloorplan.exe               # 平面规划工具
     |
     +--temperature.c/h        # 温度计算核心接口
     |       |
     |       +--temperature_block.c/h   # 块级热模型
     |       |
     |       +--temperature_grid.c/h    # 网格级热模型
     |
     +--flp.c/h                # 平面规划管理
     |
     +--materials.c/h          # 材料热属性
     |
     +--microchannel.c/h       # 微通道冷却
     |
     +--util.c/h               # 工具函数
     |
     +--RCutil.c               # 矩阵求解工具
```

## 2 热模型分类

### 2.1 块级模型 (Block Model)

块级模型 [`temperature_block.c`](detail/temperature_block.md) 将芯片划分为粗粒度的功能块，每个块具有均匀的温度分布。适用于系统级热分析，计算速度快但精度较低。

**特点：**
- 计算复杂度：O(n)
- 内存占用：低
- 适用场景：早期设计探索、快速热评估

**相关源文件：**
- [`src/temperature_block.c`](detail/temperature_block.md) - 块级模型实现
- [`src/temperature_block.h`](detail/temperature_block.md) - 块级模型接口

### 2.2 网格模型 (Grid Model)

网格模型 [`temperature_grid.c`](detail/temperature_grid.md) 将芯片表面划分为细粒度的二维网格，每个网格单元独立计算温度。适用于详细热分析，计算速度较慢但精度高。

**特点：**
- 计算复杂度：O(n^2)
- 内存占用：高
- 适用场景：详细热分析、热点检测

**相关源文件：**
- [`src/temperature_grid.c`](detail/temperature_grid.md) - 网格级模型实现
- [`src/temperature_grid.h`](detail/temperature_grid.md) - 网格级模型接口

## 3 数据流架构

```
                    输入文件
                       |
           +-----------+-----------+
           |           |           |
        .flp       .ptrace      .lcf
      (平面规划)   (功耗追踪)   (层配置)
           |           |           |
           +-----------+-----------+
                       |
                  Flp + Power
                       |
                       v
              +----------------+
              |  temperature.c |
              |   核心求解器    |
              +----------------+
                       |
           +-----------+-----------+
           |                       |
           v                       v
    [稳态分析]              [瞬态分析]
    LUP分解求解            4阶Runge-Kutta
           |                       |
           v                       v
      .ttrace (温度追踪文件)
```

## 4 核心求解器

### 4.1 稳态求解器

稳态分析使用 LUP 分解方法求解线性方程组 `Ax = b`。

**实现位置：** [`RCutil.c`](detail/RCutil.md)

**算法流程：**
1. 构建热阻网络矩阵 A
2. LUP 分解：PA = LU
3. 前向代换：Ly = Pb
4. 后向代换：Ux = y

### 4.2 瞬态求解器

瞬态分析使用 4 阶 Runge-Kutta (RK4) 方法求解常微分方程。

**实现位置：** [`temperature_block.c`](detail/temperature_block.md) 和 [`temperature_grid.c`](detail/temperature_grid.md)

**算法流程：**
1. 初始化温度向量 T(t0)
2. 计算 k1 = f(T(t), t)
3. 计算 k2 = f(T(t) + k1*dt/2, t + dt/2)
4. 计算 k3 = f(T(t) + k2*dt/2, t + dt/2)
5. 计算 k4 = f(T(t) + k3*dt, t + dt)
6. 更新温度：T(t+dt) = T(t) + (k1 + 2*k2 + 2*k3 + k4) * dt / 6

## 5 文件格式

### 5.1 平面规划文件 (.flp)

定义芯片的功能块布局和尺寸。

**格式：** `name width height center_x center_y`

**示例：**
```
CPU     10.0   10.0   5.0    5.0
L2      5.0    5.0    15.0   5.0
Memory  20.0   10.0   10.0   20.0
```

**详细说明：** [`doc/detail/flp.md`](detail/flp.md)

### 5.2 功耗追踪文件 (.ptrace)

记录各功能块随时间变化的功耗。

**格式：** `time name power`

**示例：**
```
0.0    CPU     50.0
0.0    L2      10.0
0.001  CPU     75.0
0.001  L2      15.0
```

### 5.3 温度追踪文件 (.ttrace)

输出各功能块随时间变化的温度。

**格式：** `time name1 name2 ...`

**示例：**
```
0.0    CPU     300.15  L2     298.15
0.001  CPU     305.22  L2     299.87
```

## 6 物理层结构

HotSpot 模拟的物理层从芯片核心到环境包括：

```
+------------------+     厚度 (m)    热导率 (W/mK)
+------------------+----------------
|   芯片核心 (Die)  |   0.00015     100.0 (硅)
+------------------+
|   界面材料 (TIM)  |   0.00002     4.0
+------------------+
|   散热片 (Spreader)|  0.001      400.0 (铜)
+------------------+
|   散热器 (Heatsink)| 0.0067      200.0 (铝)
+------------------+
|   环境 (Ambient)  |   -          -
+------------------+

封装节点 (14个)：
- 4个侧面包封节点 (package_0~3)
- 4个角落封装节点 (package_4~7)
- 4个底部封装节点 (package_8~11)
- 2个顶部封装节点 (package_12~13)
```

**详细说明：** [`doc/detail/materials.md`](detail/materials.md)

## 7 构建系统

### 7.1 构建工具

**要求：** CMake 3.15+

**编译命令：**
```bash
mkdir build
cd build
cmake ..
cmake --build . --config Release
```

**输出：**
- `hotspot.exe` - 主仿真程序
- `hotfloorplan.exe` - 平面规划工具

### 7.2 可选依赖

| 库 | 用途 | 加速效果 |
|---|------|----------|
| BLAS | 矩阵运算 | ~2-5x |
| LAPACK | 线性代数 | ~2-5x |
| SuperLU | 稀疏矩阵求解 | 显著 (稀疏矩阵) |

## 8 模块依赖关系

```
util.c/h
   |-- 基础工具函数
   |-- 文件读写
   |-- 内存管理

flp.c/h
   |-- util.c/h
   |-- 平面规划解析

materials.c/h
   |-- 材料热属性定义
   |-- 层结构配置

temperature.c/h
   |-- flp.c/h
   |-- materials.c/h
   |-- temperature_block.c/h (条件编译)
   |-- temperature_grid.c/h (条件编译)
   |-- RCutil.c

temperature_block.c/h
   |-- temperature.h
   |-- flp.h
   |-- materials.h

temperature_grid.c/h
   |-- temperature.h
   |-- flp.h
   |-- materials.h

microchannel.c/h
   |-- temperature.h
   |-- flp.h
   |-- materials.h

hotspot.c/h
   |-- temperature.h
   |-- flp.h
   |-- util.h

hotfloorplan.c/h
   |-- flp.h
   |-- util.h
   |-- shape.h
   |-- wire.h
   |-- npe.h
```

## 9 配置参数

主要配置参数定义在 `hotspot.h` 中：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `SINK_R` | 0.1 | 散热器热阻 (K/W) |
| `SINK_C` | 140.0 | 散热器热容 (J/K) |
| `AMBIENT` | 313.15 | 环境温度 (K) |
| `MIN_DIE_TEMP` | 200.0 | 最小允许温度 (K) |
| `MAX_DIE_TEMP` | 400.0 | 最大允许温度 (K) |
| `dt` | 0.0001 | 瞬态时间步长 (s) |

详细配置说明： [`doc/tutorial/configuration.md`](tutorial/configuration.md)

## 10 扩展能力

### 10.1 微通道冷却

支持微通道散热结构模拟，详见 [`doc/detail/microchannel.md`](detail/microchannel.md)。

### 10.2 3D IC 支持

通过 `package.config` 配置层叠结构，支持 3D 集成电路热分析。

### 10.3 自适应时间步长

瞬态分析支持自适应时间步长调整，根据温度变化率动态调整 dt。
