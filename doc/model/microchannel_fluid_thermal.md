# 微流控冷却流热耦合模型

## 1. 引言 - 微流控冷却概述

微流控冷却是一种利用流体在微观通道中流动来带走热量的先进散热技术。该技术广泛应用于高性能处理器、三维集成电路和数据中心散热等领域。

### 典型设计参数

| 参数 | 典型范围 |
|------|----------|
| 通道宽度 | 50-200 μm |
| 通道高度 | 50-300 μm |
| 泵送压力 | 1-10 kPa |
| 冷却液 | 水或介电液体 |

微流控冷却的核心优势在于其极高的单位面积散热能力和可调的流体动力学特性。通过在芯片内部或封装层集成微通道网络，热量可以被流体快速带走，从而维持器件工作在安全温度范围内。

---

## 2. 流体网络建模

### 2.1 网络离散化

HotSpot 将流体域离散为由流体单元格和固体单元格组成的网络结构。每个流体单元格代表一段通道体积，每个固体单元格代表与之相邻的固体区域。

```
INLET ─────► [FLUID] ─────► [FLUID] ─────► OUTLET
              │               │
              ▼               ▼
           [SOLID]        [SOLID]
              │               │
              ▼               ▼
```

### 2.2 质量守恒方程

在每个流体网络节点处，流体满足质量守恒定律。对于不可压缩流体：

```
Σ(ρ × v × A) = 0  at each node
```

其中：
- ρ 是流体密度 (kg/m³)
- v 是流体速度 (m/s)
- A 是通道横截面积 (m²)

### 2.3 网络拓扑

流体网络由以下基本元素组成：

1. **入口节点 (INLET)** - 流体进入位置
2. **出口节点 (OUTLET)** - 流体排出位置
3. **流体单元格** - 沿流动方向的离散控制体
4. **固体单元格** - 与流体进行热交换的固体区域
5. **壁面连接** - 流体与固体之间的热耦合界面

---

## 3. 压力-速度耦合

### 3.1 Poiseuille 流动

在矩形微通道中，层流流动遵循 Poiseuille 定律。对于低雷诺数层流，矩形通道的水力传导率可表示为：

```c
hydroC = (1 - 0.63*(w/h)) * w^3 * h / (12 * mu * L)
```

参数说明：
- `w` - 通道宽度 (m)
- `h` - 通道高度 (m)
- `mu` - 动力粘度 (Pa·s)
- `L` - 通道长度 (m)

### 3.2 压力-流速关系

水力传导率将压力差与体积流速关联起来：

```
Q = hydroC × ΔP
```

其中：
- Q 是体积流速 (m³/s)
- ΔP 是通道两端的压力差 (Pa)

### 3.3 压力求解

压力分布通过网络求解获得。`solve_pressure_circuit()` 函数负责构建并求解线性方程组：

```
[A] × P = b
```

其中 [A] 是由水力传导率组成的系数矩阵，P 是节点压力向量，b 是边界条件向量。

---

## 4. 热传递耦合

### 4.1 固-液界面热传递

热量通过固-液界面从固体传递给流体。热传递速率由牛顿冷却定律描述：

```
Q_transfer = htc × A × (T_solid - T_fluid)
```

其中：
- htc 是热传递系数 (W/m²·K)
- A 是接触面积 (m²)
- T_solid 是固体温度 (K)
- T_fluid 是流体温度 (K)

### 4.2 固体内部热传导

固体区域内部的热传导遵循傅里叶定律：

```
Q_cond = k × A / L × (T_hot - T_cold)
```

其中：
- k 是热导率 (W/m·K)
- A 是热流通过的横截面积 (m²)
- L 是热流方向的长度 (m)
- T_hot 和 T_cold 分别是高温端和低温端温度 (K)

### 4.3 热传递系数计算

热传递系数 htc 取决于流动状态和通道几何形状。对于层流，热传递系数可由 Nusselt 数推算：

```
htc = Nu × k_f / D_h
```

其中 D_h 是水力直径，Nu 对于充分发展的层流约为 3.0。

---

## 5. 能量守恒方程

### 5.1 流体单元格能量守恒

每个流体单元格满足瞬态能量守恒：

```
ρ_f × c_pf × V × dT_f/dt = 
    Σ(Q_in) - Σ(Q_out) + Σ(Q_wall)
```

各项含义：
- ρ_f - 流体密度 (kg/m³)
- c_pf - 流体比热容 (J/kg·K)
- V - 控制体体积 (m³)
- dT_f/dt - 流体温度随时间变化率 (K/s)
- Σ(Q_in) - 来自上游流体的热输入 (W)
- Σ(Q_out) - 向下游流体的热输出 (W)
- Σ(Q_wall) - 来自壁面的热输入 (W)

### 5.2 固体单元格能量守恒

每个固体单元格满足瞬态能量守恒：

```
ρ_s × c_ps × V × dT_s/dt = 
    Q_power + Σ(Q_fluid_from_walls) + Σ(Q_from_neighbors)
```

各项含义：
- ρ_s - 固体密度 (kg/m³)
- c_ps - 固体比热容 (J/kg·K)
- V - 控制体体积 (m³)
- dT_s/dt - 固体温度随时间变化率 (K/s)
- Q_power - 器件功耗产生的热量 (W)
- Σ(Q_fluid_from_walls) - 来自相邻流体单元格的热量 (W)
- Σ(Q_from_neighbors) - 来自相邻固体单元格的热传导 (W)

### 5.3 耦合求解策略

流热耦合方程组通过以下步骤求解：

1. 给定压力边界条件，求解压力分布
2. 根据压力梯度计算流速
3. 根据流速计算对流热传递
4. 耦合求解固体和流体能量方程
5. 更新温度场
6. 检查收敛性，若未收敛则返回步骤 1

---

## 6. 与源代码的对应关系

### 6.1 网络构建

`microchannel_build_network()` 函数负责初始化微通道网络结构。该函数：
- 分配流体和固体单元格内存
- 建立网络拓扑连接
- 初始化边界条件

源码位置：[src/microchannel.c](../../src/microchannel.c)

### 6.2 压力求解

`solve_pressure_circuit()` 函数构建并求解压力方程组。该函数：
- 构建系数矩阵 [A]
- 设置边界条件向量 b
- 调用线性方程组求解器

源码位置：[src/microchannel.c](../../src/microchannel.c)

### 6.3 水力传导率计算

`hydroC()` 函数计算矩形通道的水力传导率。实现对应公式：

```c
hydroC = (1 - 0.63*(w/h)) * w^3 * h / (12 * mu * L)
```

源码位置：[src/microchannel.c](../../src/microchannel.c)

### 6.4 流动速率计算

`flow_rate()` 函数根据压力差计算体积流速：

```c
Q = hydroC * delta_P
```

源码位置：[src/microchannel.c](../../src/microchannel.c)

### 6.5 热耦合集成

`microchannel_thermal()` 函数将微流控冷却模块与温度计算模块集成。该函数：
- 计算流体与固体之间的热交换
- 更新流体和固体温度
- 处理能量守恒方程的耦合求解

源码位置：[src/temperature_grid.c](../../src/temperature_grid.c)

### 6.6 函数调用层次

```
hotspot_main()
    │
    ├── temperature.c: compute_temp()
    │       │
    │       └── temperature_grid.c: temperature_grid()
    │               │
    │               └── temperature_grid.c: microchannel_thermal()
    │                       │
    │                       ├── microchannel.c: solve_pressure_circuit()
    │                       │
    │                       └── microchannel.c: hydroC() / flow_rate()
    │
    └── microchannel.c: microchannel_build_network()
```

---

## 参考文献

1. Tuckerman D B, Pease R F W. High-performance heat sinking for VLSI[J]. IEEE Electron Device Letters, 1981, 2(5): 126-129.
2. Liu D, Garimella S V. Analysis and optimization of the thermal performance of microchannel heat sinks[J]. International Journal of Numerical Methods for Heat & Fluid Flow, 2005.
3. Kandlikar S G, Garimella S, Li D, et al. Heat transfer and fluid flow in minichannels and microchannels[M]. Elsevier, 2005.
