# wire.c / wire.h - 互连延迟模型

## 文件位置

- 头文件: [`src/wire.h`](../../src/wire.h)
- 源文件: [`src/wire.c`](../../src/wire.c)

## 功能概述

互连延迟模块负责将导线长度转换为延迟估计值。该模块实现了基于 Elmore 延迟模型的互连延迟计算，用于芯片设计中的性能规划。

主要功能：
1. 根据工艺节点（130nm/100nm/70nm/50nm）选择合适的互连参数
2. 支持全局金属层和中间金属层的延迟计算
3. 提供线长度到延迟时间的转换接口

### 理论基础

该模块的延迟模型基于以下两篇论文：

1. **Brayton 等人的规划理论**
   - R. H. J. M. Otten and R. K. Brayton, "Planning for performance," DAC '98
   - 提供了延迟与线长关系的数学基础

2. **Banerjee 等人的互连升温研究**
   - K. Banerjee and A. Mehrotra, "Global (interconnect) warming," IEEE Circuits and Devices Magazine
   - 提供了关键线长（lcrit）和最优线宽（sopt）的计算方法

3. **工艺参数来源**
   - V. Agarwal, S. W. Keckler, and D. Burger, "The effect of technology scaling on microarchitectural structures,"
   - 提供了不同工艺节点下的电阻、电容参数

## 头文件重要定义

### 工艺节点定义

```c
/* 当前建模的工艺节点 */
#define TECHNODE130
```

支持的工艺节点：`TECHNODE180`、`TECHNODE130`、`TECHNODE100`、`TECHNODE70`、`TECHNODE50`

### 金属层类型

```c
#define WIRE_GLOBAL   0   // 全局金属层
#define WIRE_INTER     1   // 中间金属层
```

### 延迟模型参数

```c
/*
 * repeater 插入的摆幅假设：
 * 通常假设 50% 摆幅，此时 a = 0.4, b = 0.7
 */
#define WIRE_A         0.4
#define WIRE_B         0.7
```

### 130nm 工艺节点参数

```c
#if defined(TECHNODE130)
    #define WIRE_R_G     61.0    // 全局层电阻 (mohm/um)
    #define WIRE_C_G     0.359   // 全局层电容 (fF/um)
    #define WIRE_R_I     188.0   // 中间层电阻 (mohm/um)
    #define WIRE_C_I     0.336   // 中间层电容 (fF/um)
    #define WIRE_LCRIT_G 2.4     // 全局层临界长度 (mm)
    #define WIRE_SOPT_G  146.0   // 全局层最优线宽 (无量纲)
```

### 延迟计算常量

```c
/*
 * 延迟（秒）/米
 * 基于 Brayton 等人的 Equation 2 和 Theorem 2
 * 推导：设 cp = co，代入 sqrt(ro*co) 得到
 */
#define WIRE_DELAY_G   (WIRE_LCRIT_G * WIRE_R_G * WIRE_C_G * 1.0e-9 * \
                        (2.0 * WIRE_A + sqrt (2.0 * WIRE_A * WIRE_B)))
#define WIRE_DELAY_I   (WIRE_LCRIT_I * WIRE_R_I * WIRE_C_I * 1.0e-9 * \
                        (2.0 * WIRE_A + sqrt (2.0 * WIRE_A * WIRE_B)))
```

## 核心函数

### wire_length2delay()

```c
double wire_length2delay(double length, int layer);
```

**功能**：将导线长度转换为延迟时间

**参数**：
- `length` - 导线长度（单位：与 WIRE_DELAY_* 常量一致）
- `layer` - 金属层类型（WIRE_GLOBAL 或 WIRE_INTER）

**返回值**：延迟时间（秒）

**实现**：

```c
double wire_length2delay(double length, int layer)
{
    if (layer == WIRE_GLOBAL)
        return WIRE_DELAY_G * length;
    else if (layer == WIRE_INTER)
        return WIRE_DELAY_I * length;
    else
        fatal("unknown metal layer\n");
    return 0.0;
}
```

**使用示例**：

```c
#include "wire.h"

// 计算 2mm 全局导线的延迟
double delay = wire_length2delay(2.0, WIRE_GLOBAL);

// 计算 1mm 中间层导线的延迟
double delay2 = wire_length2delay(1.0, WIRE_INTER);
```

## 互连延迟模型说明

### Elmore 延迟模型

基本的 Elmore 延迟公式：

```
delay = R * C_total
     = (R_sheet * length / width) * (C_cap * length)
     = R_sheet * C_cap * length^2 / width
```

其中：
- `R_sheet` - 方块电阻（ohms/square）
- `C_cap` - 单位长度电容（F/m）
- `length` - 导线长度
- `width` - 导线宽度

### 临界长度 lcrit

临界长度是指导线延迟等于驱动器上升时间的导线长度。超过此长度需要插入 repeater。

```
lcrit = sqrt(2 * t_r / (R_sheet * C_cap))
```

其中 `t_r` 是上升时间。

### 最优线宽 sopt

最优线宽是使总延迟（导线延迟 + 驱动器延迟）最小的线宽：

```
sopt = sqrt(2 * t_r * R_sheet / C_cap) / R_driver
```

### 多工艺节点参数表

| 工艺节点 | WIRE_R_G (mohm/um) | WIRE_C_G (fF/um) | WIRE_LCRIT_G (mm) | WIRE_SOPT_G |
|----------|-------------------|------------------|-------------------|-------------|
| 180nm    | 36.0              | 0.350            | 3.0               | 179.0       |
| 130nm    | 61.0              | 0.359            | 2.4               | 146.0       |
| 100nm    | 103.0             | 0.361            | 2.12              | 96.0        |
| 70nm     | 164.0             | 0.360            | 1.2               | 82.0        |
| 50nm     | 321.0             | 0.358            | 0.99              | 48.0        |

### 中间层参数计算

中间层（intermediate layer）的临界长度和最优线宽由全局层参数推导得出，利用以下不变关系：

```
lcrit * sqrt(R * C) = 常数
sopt * sqrt(R / C) = 常数
```

计算公式：

```c
#define WIRE_LCRIT_I  (WIRE_LCRIT_G * \
                        sqrt((WIRE_R_G / WIRE_R_I) * (WIRE_C_G / WIRE_C_I)))
#define WIRE_SOPT_I   (WIRE_SOPT_G * \
                        sqrt((WIRE_R_G / WIRE_R_I) / (WIRE_C_G / WIRE_C_I)))
```

## 集成与使用

该模块主要与布局规划器集成，用于优化过程中的导线延迟估计：

```c
// 布局评估时计算线延迟代价
double evaluate_wire_delay(flp_t *flp) {
    double total_delay = 0.0;
    
    for (i = 0; i < n_units; i++) {
        for (j = i+1; j < n_units; j++) {
            if (wire_density[i][j] > 0) {
                double length = get_manhattan_dist(flp, i, j);
                double delay = wire_length2delay(length, WIRE_GLOBAL);
                total_delay += wire_density[i][j] * delay;
            }
        }
    }
    return total_delay;
}
```

### 与布局优化的关系

在模拟退火布局优化中，导线延迟是代价函数的组成部分：

```
代价 = lambdaA * 面积 + lambdaT * 温度 + lambdaW * 导线延迟
```

其中 `lambdaW` 是导线延迟的权重因子。
