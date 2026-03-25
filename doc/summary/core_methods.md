# HotSpot 核心算法文档

## 1 概述

HotSpot 使用两种主要的数值计算方法来解决热问题：

1. **LUP 分解** - 求解稳态热平衡方程 `Ax = b`
2. **4 阶 Runge-Kutta (RK4)** - 求解瞬态热传导常微分方程

## 2 热阻-热容 (RC) 网络模型

### 2.1 热传导物理基础

热传导遵循傅里叶定律：

```
q = -k * A * (dT/dx)
```

其中：
- `q` - 热流量 (W)
- `k` - 热导率 (W/mK)
- `A` - 横截面积 (m^2)
- `dT/dx` - 温度梯度 (K/m)

### 2.2 热阻

热阻表示单位热流量引起的温升：

```
R_th = dT / q = L / (k * A)
```

**典型热阻值：**
| 材料 | 厚度 | 热阻 |
|------|------|------|
| 硅芯片 | 0.15 mm | 1.5e-6 K/W |
| TIM | 0.02 mm | 5.0e-6 K/W |
| 铜散热片 | 1 mm | 2.5e-6 K/W |

### 2.3 热容

热容表示单位温度变化所需的热量：

```
C_th = m * c = rho * V * c
```

其中：
- `m` - 质量 (kg)
- `c` - 比热容 (J/kgK)
- `rho` - 密度 (kg/m^3)
- `V` - 体积 (m^3)

### 2.4 RC 网络构建

HotSpot 将芯片封装结构建模为 RC 网络：

```
                    +--------+
                    | Ambient|
                    |   T_a  |
                    +---+----+
                        |
                       R_conv
                        |
                    +---+----+      14 package nodes
                    |   |    |      (package_0 ~ package_13)
    +--------+      |   +----+----+---+----+--
    |Heatsink|------R_sink
    +---+----+      |   |    |    |
        |          +---+    +----+
       C_sink           R_sp
        |                |
    +---+----+          +---+
    |Spreader|----------R_sp2|
    +---+----+              |
        |               +---+----+
       C_sp             |   TIM |
        |               +---+----+
        |                   |
    +---+----+          +---+----+
    |  Die  |          |  Chip  |
    +---+----+          +---+----+
        |                  |
       R_die              R_die2
```

## 3 LUP 分解求解器

### 3.1 算法原理

LUP 分解是 LU 分解的变体，通过置换矩阵 P 避免数值不稳定：

```
PA = LU
```

其中：
- `P` - 置换矩阵
- `L` - 下三角矩阵 (对角线为 1)
- `U` - 上三角矩阵

**求解步骤：**
1. LUP 分解：`PA = LU`
2. 前向代换：`Ly = Pb`
3. 后向代换：`Ux = y`

### 3.2 实现位置

**源文件：** [`src/RCutil.c`](detail/RCutil.md)

**主要函数：**

```c
// LUP 分解
int lup(double **a, int *p, int n)

// 前向代换
void forward_sub(double **l, double *b, double *y, int n)

// 后向代换  
void back_sub(double **u, double *y, double *x, int n)

// 完整求解
void solve_linear_system(double **a, double *b, double *x, int n)
```

### 3.3 代码实现

```c
// LUP 分解实现 (RCutil.c)
int lup(double **a, int *p, int n)
{
    int i, j, k, max_idx;
    double max_val, temp;

    for (i = 0; i < n; i++)
        p[i] = i;

    for (k = 0; k < n; k++) {
        // 寻找主元
        max_val = fabs(a[p[k]][k]);
        max_idx = k;
        
        for (i = k + 1; i < n; i++) {
            if (fabs(a[p[i]][k]) > max_val) {
                max_val = fabs(a[p[i]][k]);
                max_idx = i;
            }
        }
        
        // 置换
        if (max_idx != k) {
            temp = p[k];
            p[k] = p[max_idx];
            p[max_idx] = temp;
        }
        
        // 消元
        for (i = k + 1; i < n; i++) {
            a[p[i]][k] = a[p[i]][k] / a[p[k]][k];
            for (j = k + 1; j < n; j++) {
                a[p[i]][j] = a[p[i]][j] - a[p[i]][k] * a[p[k]][j];
            }
        }
    }
    return 1;
}
```

### 3.4 稳态求解

对于稳态分析，热平衡方程为：

```
G * T = P
```

其中：
- `G` - 热导矩阵 (W/K)
- `T` - 温度向量 (K)
- `P` - 功耗向量 (W)

使用 LUP 分解求解：

```c
// 稳态温度计算 (temperature_block.c)
void steady_state_temp(RC_model_t *model, double *power, double *temp)
{
    int n = model->block->n_nodes;
    double **a = model->block->R_mat;  // 热阻矩阵
    double *b = power;                  // 功耗向量
    
    // LUP 分解
    lup(a, model->block->perm, n);
    
    // 求解
    solve_linear_system(a, b, temp, n);
}
```

### 3.5 计算复杂度

| 分解步骤 | 复杂度 |
|----------|--------|
| LUP 分解 | O(n^3) |
| 前向代换 | O(n^2) |
| 后向代换 | O(n^2) |
| **总复杂度** | **O(n^3)** |

对于稀疏矩阵，可使用 SuperLU 加速到 O(n^2)。

## 4 4 阶 Runge-Kutta 方法

### 4.1 算法原理

RK4 是一种 4 阶精确的常微分方程数值解法。对于热传导问题：

```
dT/dt = f(T, t) = C^(-1) * (P - G * T)
```

其中：
- `T` - 温度向量
- `t` - 时间
- `C` - 热容矩阵
- `P` - 功耗向量
- `G` - 热导矩阵

**RK4 公式：**

```
k1 = f(T(t), t)
k2 = f(T(t) + k1*dt/2, t + dt/2)
k3 = f(T(t) + k2*dt/2, t + dt/2)
k4 = f(T(t) + k3*dt, t + dt)

T(t+dt) = T(t) + (k1 + 2*k2 + 2*k3 + k4) * dt / 6
```

### 4.2 实现位置

**块级模型：** [`src/temperature_block.c`](detail/temperature_block.md)

**网格模型：** [`src/temperature_grid.c`](detail/temperature_grid.md)

### 4.3 代码实现

```c
// RK4 瞬态计算 (temperature_block.c)
void compute_temp(RC_model_t *model, double *power, double *temp, double dt)
{
    double k1[N_MAX], k2[N_MAX], k3[N_MAX], k4[N_MAX];
    double T_temp[N_MAX];
    int i;
    
    // k1 = f(T(t), t)
    compute_power_diff(model, temp, power, k1);
    for (i = 0; i < model->block->n_nodes; i++)
        k1[i] = k1[i] / model->block->C_mat[i];
    
    // k2 = f(T(t) + k1*dt/2, t + dt/2)
    for (i = 0; i < model->block->n_nodes; i++)
        T_temp[i] = temp[i] + k1[i] * dt / 2;
    compute_power_diff(model, T_temp, power, k2);
    for (i = 0; i < model->block->n_nodes; i++)
        k2[i] = k2[i] / model->block->C_mat[i];
    
    // k3 = f(T(t) + k2*dt/2, t + dt/2)
    for (i = 0; i < model->block->n_nodes; i++)
        T_temp[i] = temp[i] + k2[i] * dt / 2;
    compute_power_diff(model, T_temp, power, k3);
    for (i = 0; i < model->block->n_nodes; i++)
        k3[i] = k3[i] / model->block->C_mat[i];
    
    // k4 = f(T(t) + k3*dt, t + dt)
    for (i = 0; i < model->block->n_nodes; i++)
        T_temp[i] = temp[i] + k3[i] * dt;
    compute_power_diff(model, T_temp, power, k4);
    for (i = 0; i < model->block->n_nodes; i++)
        k4[i] = k4[i] / model->block->C_mat[i];
    
    // T(t+dt) = T(t) + (k1 + 2*k2 + 2*k3 + k4) * dt / 6
    for (i = 0; i < model->block->n_nodes; i++) {
        temp[i] = temp[i] + (k1[i] + 2*k2[i] + 2*k3[i] + k4[i]) * dt / 6;
    }
}
```

### 4.4 辅助函数

```c
// 计算功率差 (热导 * 温度)
// power_diff = P - G * T
void compute_power_diff(RC_model_t *model, double *temp, 
                        double *power, double *power_diff)
{
    int i, j;
    double sum;
    int n = model->block->n_nodes;
    
    for (i = 0; i < n; i++) {
        sum = 0;
        for (j = 0; j < n; j++) {
            if (i != j)  // 跳过自热阻
                sum += model->block->G_mat[i][j] * (temp[i] - temp[j]);
        }
        power_diff[i] = power[i] - sum;
    }
}
```

### 4.5 计算复杂度

| 步骤 | 复杂度 |
|------|--------|
| 计算 k1-k4 | O(n^2) 每步 |
| 4 步 RK4 | O(4 * n^2) = O(n^2) |
| 总瞬态步数 | O(steps * n^2) |

## 5 Jacobi 迭代法

### 5.1 算法原理

Jacobi 迭代是求解线性方程组的迭代方法，适用于稀疏矩阵：

```
Ax = b
x^(k+1) = D^(-1) * (b - (L+U) * x^(k))
```

其中 D, L, U 分别是 A 的对角、下三角、上三角部分。

### 5.2 实现位置

**源文件：** [`src/RCutil.c`](detail/RCutil.md)

### 5.3 代码实现

```c
// Jacobi 迭代求解 (RCutil.c)
int jacobi(double **a, double *b, double *x, int n, int max_iter, double tol)
{
    double x_new[N_MAX];
    double sum;
    int i, j, iter;
    
    for (iter = 0; iter < max_iter; iter++) {
        for (i = 0; i < n; i++) {
            sum = 0;
            for (j = 0; j < n; j++) {
                if (i != j)
                    sum += a[i][j] * x[j];
            }
            x_new[i] = (b[i] - sum) / a[i][i];
        }
        
        // 检查收敛
        for (i = 0; i < n; i++) {
            if (fabs(x_new[i] - x[i]) > tol) {
                break;
            }
        }
        if (i == n)  // 收敛
            break;
            
        // 更新
        for (i = 0; i < n; i++)
            x[i] = x_new[i];
    }
    
    return iter;
}
```

### 5.4 收敛条件

Jacobi 迭代收敛的条件是矩阵 A 是严格对角占优的：

```
|a_ii| > sum(|a_ij|) for j != i
```

## 6 时间步长选择

### 6.1 固定时间步长

默认使用固定时间步长，由 `dt` 参数控制：

```c
thermal_config.dt = 1e-4;  // 0.1 ms
thermal_config.sampling_intvl = 1e-3;  // 1 ms
```

### 6.2 稳定性条件

对于显示 RK 方法，步长受稳定性限制：

```
dt < 2 * C_min / lambda_max
```

其中：
- `C_min` - 最小热容
- `lambda_max` - 最大特征值 (热导矩阵)

### 6.3 精度考虑

- 瞬态仿真精度与 dt 成正比
- 建议 dt <= 感兴趣的最短时间常数的 1/10

## 7 矩阵稀疏性优化

### 7.1 稀疏矩阵存储

HotSpot 使用密集矩阵存储，但热阻矩阵本质是稀疏的 (每个节点只与邻居相连)。

**优化策略：**
- 忽略自热阻 (对角线元素)
- 使用稀疏矩阵库 (SuperLU)
- 预条件共轭梯度法

### 7.2 SuperLU 加速

启用 SuperLU 可以显著加速稀疏矩阵求解：

```cmake
cmake .. -DENABLE_SUPERLU=ON
```

## 8 算法选择指南

| 场景 | 推荐算法 |
|------|----------|
| 稳态分析 | LUP 分解 |
| 瞬态分析 | RK4 |
| 稀疏大系统 | SuperLU |
| 快速估算 | Jacobi 迭代 |
| 实时仿真 | 自适应步长 RK |

## 9 数值稳定性

### 9.1 LUP 分解稳定性

- 部分主元选择保证数值稳定
- 对病态矩阵可能需要全主元

### 9.2 RK4 稳定性

- 条件稳定，步长受限于系统时间常数
- 适合热传导问题 (时间常数通常较大)

### 9.3 常见数值问题

| 问题 | 症状 | 解决方案 |
|------|------|----------|
| 刚性问题 | 步长极小 | 使用隐式方法 |
| 数值振荡 | 温度震荡 | 减小步长 |
| 长时间积累误差 | 能量不守恒 | 验证能量平衡 |
