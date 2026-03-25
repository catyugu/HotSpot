# temperature_block.c / temperature_block.h - 块级热模型

## 文件位置

- 头文件: [`src/temperature_block.h`](../../src/temperature_block.h)
- 源文件: [`src/temperature_block.c`](../../src/temperature_block.c)

## 功能概述

块级热模型是HotSpot的快速热仿真方法，将每个功能单元建模为单个热节点。该模型：
- 计算量小，适合快速早期设计探索
- 支持瞬态和稳态仿真
- 使用LUP分解求解线性方程组
- 使用4阶Runge-Kutta方法求解瞬态ODE

## 头文件定义

### 层索引

```c
#define NL      4   // 总层数
#define IFACE   1   // 界面层
#define HSP     2   // 扩散器层
#define HSINK   3   // 散热器层
// 硅层永远是0
```

### 块模型结构

```c
typedef struct block_model_t_st {
    flp_t *flp;              // 布局指针

    thermal_config_t config; // 配置副本

    /* 主矩阵 */
    double **b;             // 传导矩阵 B (对称正定)
    double **lu;            // B的LUP分解
    int *p;                  // LUP置换向量
    double *a;              // 对角热容向量
    double *inva;           // a的逆 (1/a[i])
    double **c;             // c = inva * b

    /* 封装参数 */
    package_RC_t pack;

    /* 中间向量和矩阵 */
    double *gx, *gy;              // x/y方向 lumped 传导
    double *gx_int, *gy_int;       // 界面层传导
    double *gx_sp, *gy_sp;         // 扩散器层传导
    double *gx_hs, *gy_hs;         // 散热器层传导
    double *g_amb;                 // 到环境的传导
    double *t_vector;              // 临时向量
    double **len, **g;             // 共享边长度, 传导
    int **border;                  // 边界标记

    int n_nodes;      // 总节点数 = NL*n_units + EXTRA
    int n_units;      // 功能单元数
    int base_n_units; // 原始功能单元数（用于resize）

    int r_ready;       // R模型是否已初始化
    int c_ready;       // C模型是否已初始化
} block_model_t;
```

## 核心函数

### alloc_block_model()

```c
block_model_t *alloc_block_model(thermal_config_t *config, flp_t *placeholder)
```

分配并初始化块模型内存。节点数计算：
```
n_nodes = NL * n_units + EXTRA = 4 * n_units + 12
```

分配的矩阵：
- `b`, `lu`: (n_nodes x n_nodes) 传导矩阵
- `g`: (n_nodes x n_nodes) 节点间传导
- `len`: (n_units x n_units) 共享边长度
- `a`, `inva`: (n_nodes) 热容向量
- `c`: (n_nodes x n_nodes) c = inva * b

### populate_R_model_block()

构建热传导矩阵B，使得 B * T = P（稳态方程）。

#### 传导计算

每个功能单元在各层中的传导（侧向）：
```c
gx[i] = 1.0 / getr(k_chip, width/2, height * t_chip)
gy[i] = 1.0 / getr(k_chip, height/2, width * t_chip)
```

其中 `getr()` 计算热阻：
```c
double getr(double conductivity, double thickness, double area) {
    return thickness / (conductivity * area);
}
```

#### B矩阵构建

非对角元素（节点间传导）：
```c
b[i][j] = b[j][i] = -1.0 / ((1.0/g[i][j]) + (1.0/g[j][i]))
```

对角元素（该节点到所有其他节点的传导之和）：
```c
b[i][i] = -sum(b[i][j]) for all j != i
```

对于散热器层的节点，还包括到环境的传导：
```c
b[i][i] += g_amb[i]  // i >= HSINK*n && i < NL*n
```

### populate_C_model_block()

构建热容矩阵A和C矩阵（用于瞬态求解）。

#### 热容计算

```c
double getcap(double sp_heat, double thickness, double area) {
    return C_FACTOR * sp_heat * thickness * area;
    // C_FACTOR = 0.333 (lumped parameter correction)
}
```

各层热容：
- 硅层: `a[i] = getcap(p_chip, t_chip, area)`
- 界面层: `a[IFACE*n+i] = getcap(p_interface, t_interface, area)`
- 扩散器层: `a[HSP*n+i] = getcap(p_spreader, t_spreader, area)`
- 散热器层: `a[HSINK*n+i] = getcap(p_sink, t_sink, area) + c_amb`

#### C矩阵计算

```c
diagmatmult(c, inva, b, n_nodes);
// c[i][j] = inva[i] * b[i][j]
```

这用于瞬态方程：`dT/dt + C*T = invA*P`

### steady_state_temp_block()

使用LUP分解求解稳态温度：

```c
void steady_state_temp_block(block_model_t *model, double *power, double *temp) {
    // 设置内部节点功率
    set_internal_power_block(model, power);
    
    // 使用LUP分解求解 B * temp = power
    lusolve(model->lu, model->n_nodes, model->p, power, temp, 1);
}
```

### set_internal_power_block()

设置封装内部节点的"虚拟"功率。这些节点不散发功率，但需要设置边界条件：

```c
void set_internal_power_block(block_model_t *model, double *power) {
    // 界面和扩散器层功率为0
    zero_dvector(&power[IFACE*n], n);
    zero_dvector(&power[HSP*n], n);
    
    // 散热器层: ambient * g_amb (等效于温度边界条件)
    for(i=0; i < n + EXTRA; i++)
        power[HSINK*n+i] = model->config.ambient * model->g_amb[i];
}
```

### slope_fn_block()

计算瞬态方程的斜率向量：
```c
void slope_fn_block(block_model_t *model, double *y, double *p, double *dy) {
    // dy = p - c*y
    // 其中 y = T, p = invA * power, c = invA * B
}
```

### compute_temp_block()

使用4阶Runge-Kutta方法求解瞬态温度：

```c
void compute_temp_block(block_model_t *model, double *power, double *temp, double time_elapsed) {
    // 计算 invA * power 存储在 t_vector
    diagmatvectmult(model->t_vector, model->inva, power, model->n_nodes);
    
    // 使用RK4进行ODE积分
    for (t = 0, new_h = MIN_STEP; t < time_elapsed && new_h >= MIN_STEP*DELTA; t += h) {
        h = new_h;
        new_h = rk4(model, temp, model->t_vector, model->n_nodes, &h,
                    temp, (slope_fn_ptr) slope_fn_block);
        new_h = MIN(new_h, time_elapsed - t - h);
    }
}
```

### delete_block_model()

释放所有动态分配的内存：
- 所有 dvector 和 dmatrix
- 所有 imatrix

## 热节点结构

```
每个功能单元有4个垂直节点：
┌─────────────────┐
│    HSINK (3)    │  ← 散热器层
├─────────────────┤
│     HSP (2)     │  ← 扩散器层
├─────────────────┤
│    IFACE (1)    │  ← 界面层
├─────────────────┤
│   SILICON (0)   │  ← 硅层（功率施加处）
└─────────────────┘

加上12个封装内部节点：
- 4个扩散器外围节点 (SP_N, SP_S, SP_E, SP_W)
- 4个散热器内周节点 (SINK_C_N, SINK_C_S, SINK_C_E, SINK_C_W)
- 4个散热器外周节点 (SINK_N, SINK_S, SINK_E, SINK_W)
```

## 节点编号

```
节点 0 到 n-1:              硅层（功能单元0到n-1）
节点 n 到 2n-1:             界面层
节点 2n 到 3n-1:            扩散器层
节点 3n 到 4n-1:            散热器层
节点 4n 到 4n+3:            扩散器外围节点
节点 4n+4 到 4n+7:          散热器内周节点
节点 4n+8 到 4n+11:         散热器外周节点
```

## LUP分解

B矩阵是对称正定矩阵（SPD），因为：
```
x^T * B * x = voltage^T * (B*x) = voltage^T * current = 总功耗 > 0 (for x != 0)
```

这允许使用更高效的Cholesky分解变体。代码使用LUP分解因为它更通用。

## 热阻网络示例

```
功能单元i和j之间的侧向热阻：
┌───────────────────────────────────┐
│                                   │
│           ┌───┐                 │
│      ─────│ gx[i] ├───          │
│           └───┘                 │
│      ┌─────────────┐           │
│      │   block i   │←───── power[i]
│      └─────────────┘           │
│                                   │
└───────────────────────────────────┘

垂直热阻（从硅到扩散器）：
R_vertical = R_si + R_interface + R_spreader
           = t_chip/(k_chip*area) + t_interface/(k_interface*area) + t_spreader/(k_spreader*area)
```

## 边界条件处理

当功能单元位于芯片边界时，相应的侧向传导会连接到封装内部节点：

```c
// 检查单元是否在北边界
if (unit.bottomy + unit.height == chip_height) {
    border[i][2] = 1;  // 北边界标记
    gn_sp += gy_sp[i]; // 累积北边界传导
    gn_hs += gy_hs[i];
}
```

然后通过封装内部节点的等效传导网络建模向环境的热流。
