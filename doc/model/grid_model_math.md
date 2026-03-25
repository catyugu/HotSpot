# HotSpot 网格模型数学文档

## 1. 引言 - 网格模型概述

HotSpot 提供了两种热模型：块模型（block model）和网格模型（grid model）。块模型将每个功能单元视为一个独立的热节点，计算效率高但精度有限。网格模型则将芯片划分为均匀的3D网格单元，能够更精细地捕捉温度分布。

### 1.1 网格模型的核心特征

- **均匀网格划分**：将计算域划分为 $N_x \times N_y \times N_z$ 个网格单元
- **默认分辨率**：64×64 网格平面分辨率（可通过配置修改）
- **多层3D堆叠**：支持不同层具有不同网格密度和功能单元布局
- **详细3D建模**：`detailed_3D_used` 选项启用时，每个网格单元可有独立的电阻和电容值

### 1.2 与块模型的主要区别

| 特征 | 块模型 | 网格模型 |
|------|--------|----------|
| 节点定义 | 每个功能单元一个节点 | 每个网格单元一个节点 |
| 温度分布 | 均匀假设 | 空间变化捕获 |
| 3D支持 | 有限 | 完整3D堆叠 |
| 计算成本 | 较低 | 较高 |
| 适用场景 | 快速估算 | 详细热分析 |

---

## 2. 3D离散化方法

### 2.1 计算域划分

将芯片划分为三维矩形网格：

```
Cell (i, j, k) 表示第 k 层的网格单元 (i, j)
其中：
  i = 0, 1, ..., N_rows-1（行索引，从顶部到底部）
  j = 0, 1, ..., N_cols-1（列索引，从左到右）
  k = 0, 1, ..., N_layers-1（层索引）
```

每个网格单元具有以下几何属性：

```
- 平面尺寸：dx = width / cols, dy = height / rows
- 层厚度：dz[k] = layers[k].thickness
- 体积：V = dx * dy * dz[k]
```

### 2.2 网格数据结构

在 [src/temperature_grid.h](src/temperature_grid.h) 中定义的核心数据结构：

```c
/* 网格模型的温度向量类型 */
typedef struct grid_model_vector_t_st {
    double ***cuboid;  /* 3-D 温度/功率网格 */
    double *extra;     /* 额外节点（spread/sink） */
} grid_model_vector_t;

/* 单层结构 */
typedef struct layer_t_st {
    flp_t *flp;           /* 该层的floorplan */
    double thickness;     /* 层厚度 */
    double k;             /* 热导率 (1/电阻率) */
    double sp;            /* 比热容 */
    double rx, ry, rz;    /* x, y, z 方向热阻 */
    double c;             /* 热容 */
    blist_t ***b2gmap;     /* 块到网格映射 */
    glist_t *g2bmap;      /* 网格到块映射 */
} layer_t;
```

### 2.3 网格模型向量

网格温度向量存储为三维数组 `cuboid[layer][row][col]`：

```
温度向量访问：T[k][i][j] = cuboid[k][i][j]
层数：N_layers
每层行数：N_rows
每列数：N_cols
```

---

## 3. 有限差分公式

### 3.1 热传导方程

在均匀介质中，热传导遵循傅里叶定律：

```
q = -k ∇T
```

对于网格单元 $(i, j, k)$，能量守恒给出：

```
ρ c V ∂T/∂t = Q_internal + Σ Q_conduction
```

其中 $Q_{conduction}$ 是通过六个面与邻居单元的热传导。

### 3.2 六邻居传导模型

使用有限体积法离散化，每个单元考虑六个邻居（x+, x-, y+, y-, z+, z-）：

```
热传导速率公式：
Q_x+ = k * A_yz / dx * (T[i+1] - T[i])   // x 正方向
Q_x- = k * A_yz / dx * (T[i-1] - T[i])   // x 负方向
Q_y+ = k * A_xz / dy * (T[j+1] - T[j])   // y 正方向
Q_y- = k * A_xz / dy * (T[j-1] - T[j])   // y 负方向
Q_z+ = k * A_xy / dz * (T[k+1] - T[k])   // z 正方向（上层）
Q_z- = k * A_xy / dz * (T[k-1] - T[k])   // z 负方向（下层）
```

其中：
- $A_{yz} = dy \cdot dz$：x方向面的面积
- $A_{xz} = dx \cdot dz$：y方向面的面积
- $A_{xy} = dx \cdot dy$：z方向面的面积

### 3.3 热阻计算

在 [src/temperature_grid.c](src/temperature_grid.c) 中的 `populate_R_model_grid()` 函数计算热阻：

```c
/* 层特定热阻 */
if (model->layers[i].has_lateral) {
    model->layers[i].rx = getr(model->layers[i].k, cw, ch * thickness);
    model->layers[i].ry = getr(model->layers[i].k, ch, cw * thickness);
} else {
    model->layers[i].rx = LARGENUM;  // 无横向传导
    model->layers[i].ry = LARGENUM;
}
model->layers[i].rz = getr(model->layers[i].k, thickness, cw * ch);
```

`getr()` 函数计算热阻：

```c
double getr(double conductivity, double thickness, double area) {
    return thickness / (conductivity * area);
}
```

### 3.4 电阻查找函数

`find_res()` 函数（[src/temperature_grid.c:26](src/temperature_grid.c:26)）计算相邻网格单元间的等效热阻，处理多种情况：

```c
double find_res(grid_model_t *model, int n1, int i1, int j1, int n2, int i2, int j2) {
    // ...
    if (n1 == n2 && i1 != i2 && j1 == j2) {
        // 同层 x 方向邻居
        res = (model->layers[n1].rx / 2.0) + (model->layers[n2].rx / 2.0);
    } else if (n1 == n2 && i1 == i2 && j1 != j2) {
        // 同层 y 方向邻居
        res = (model->layers[n1].ry / 2.0) + (model->layers[n2].ry / 2.0);
    } else if (n1 < n2 && i1 == i2 && j1 == j2) {
        // z 方向（上层到下层）
        res = model->layers[n1].rz;
    }
    // ...
}
```

---

## 4. 块到网格的映射

### 4.1 映射数据结构

块到网格的双向映射是网格模型的核心：

```c
/* 块列表：映射到同一网格单元的多个块 */
typedef struct blist_t_st {
    int idx;              /* 块索引 */
    double occupancy;     /* 该块占网格单元的面积比例 */
    int lock;             /* 是否锁定（occupancy >= OCCUPANCY_THRESHOLD）*/
    double rx, ry, rz;    /* 该网格单元的等效电阻 */
    double capacitance;   /* 该网格单元的等效电容 */
    struct blist_t_st *next;
} blist_t;

/* 网格列表：某块覆盖的网格单元范围 */
typedef struct glist_t_st {
    int i1, i2;  /* y 方向起止索引 */
    int j1, j2;  /* x 方向起止索引 */
} glist_t;
```

### 4.2 b2gmap 和 g2bmap

```c
/* b2gmap: 每个网格单元包含哪些块及其占用率
 * b2gmap[i][j] = 指向覆盖网格单元(i,j)的块链表
 */
blist_t ***b2gmap;  // [row][col][block list]

/* g2bmap: 每个块占用哪些网格单元
 * g2bmap[block_id] = {i1, i2, j1, j2}
 */
glist_t *g2bmap;  // [block_id] -> grid cell range
```

### 4.3 映射建立过程

`set_bgmap()` 函数（[src/temperature_grid.c:341](src/temperature_grid.c:341)）建立块网格映射：

```c
void set_bgmap(grid_model_t *model, layer_t *layer) {
    // 对于每个功能单元
    for (u = 0; u < layer->flp->n_units; u++) {
        // 计算该单元占据的网格范围
        i1 = model->rows - tolerant_ceil(tu / ch);  // 顶部行索引
        i2 = model->rows - tolerant_floor(bu / ch); // 底部行索引
        j1 = tolerant_floor(lu / cw);                // 左部列索引
        j2 = tolerant_ceil(ru / cw);                // 右部列索引
        
        // 建立 g2bmap
        layer->g2bmap[u].i1 = i1;
        layer->g2bmap[u].i2 = i2;
        layer->g2bmap[u].j1 = j1;
        layer->g2bmap[u].j2 = j2;
        
        // 建立 b2gmap
        for (i = i1; i < i2; i++)
            for (j = j1; j < j2; j++)
                // 计算占用率并添加到链表
                blist_append(layer->b2gmap[i][j], ...);
    }
}
```

### 4.4 映射模式

在 [src/temperature.h](src/temperature.h) 中定义的映射模式：

```c
#define GRID_AVG     0  /* 所有覆盖单元的平均值 */
#define GRID_MIN     1  /* 所有覆盖单元的最小值 */
#define GRID_MAX     2  /* 所有覆盖单元的最大值 */
#define GRID_CENTER  3  /* 中心单元的值 */
```

`xlate_vector_b2g()` 函数执行功率/温度的块到网格转换：

```c
void xlate_vector_b2g(grid_model_t *model, double *b, grid_model_vector_t *g, int type) {
    for each layer l:
        for each block u:
            for i = g2bmap[u].i1 to g2bmap[u].i2:
                for j = g2bmap[u].j1 to g2bmap[u].j2:
                    // 按占用率加权分配
                    g->cuboid[l][i][j] += occupancy * b[unit_idx];
}
```

`xlate_temp_g2b()` 函数执行反向转换，根据映射模式聚合温度：

```c
void xlate_temp_g2b(grid_model_t *model, double *b, grid_model_vector_t *g) {
    for each block u:
        temps = collect all g->cuboid[l][i][j] within block u
        switch (model->map_mode):
            case GRID_AVG:    b[u] = average(temps); break;
            case GRID_MIN:    b[u] = min(temps); break;
            case GRID_MAX:    b[u] = max(temps); break;
            case GRID_CENTER: b[u] = center_cell_temp; break;
}
```

---

## 5. Jacobi迭代与多网格方法

### 5.1 稳态求解

稳态温度满足 $G \cdot T = P \cdot R$，其中 $G$ 是热导矩阵，$T$ 是温度向量，$P$ 是功率向量，$R$ 是热阻。

在 [src/temperature.c](src/temperature.c) 中的 `steady_state_temp_grid()` 函数实现迭代求解：

```c
void steady_state_temp_grid(grid_model_t *model, double *power, double *temp) {
    grid_model_vector_t *T = new_grid_model_vector(model);
    grid_model_vector_t *P = new_grid_model_vector(model);
    
    // 块功率转换到网格
    xlate_vector_b2g(model, power, P, V_POWER);
    
    // 迭代求解
    for (iter = 0; iter < max_iter; iter++) {
        for (k = 0; k < model->n_layers; k++)
            for (i = 1; i < model->rows - 1; i++)
                for (j = 1; j < model->cols - 1; j++) {
                    // 计算对角系数
                    diag = /* 热导矩阵对角元素 */;
                    
                    // 计算邻居贡献
                    neighbors = /* 六邻居热传导之和 */;
                    
                    // Jacobi 迭代更新
                    T_new[k][i][j] = (P[k][i][j] + neighbors) / diag;
                }
        
        // 检查收敛
        if (norm(T_new - T) < tolerance)
            break;
        
        swap(T, T_new);
    }
    
    // 网格温度转换回块温度
    xlate_temp_g2b(model, temp, T);
}
```

### 5.2 Jacobi 迭代公式

对于内部网格单元 $(i, j, k)$：

```
T_new[i][j][k] = (P[i][j][k] + Σ G_neighbor * T_neighbor) / G_diag
```

其中 $G$ 是热导矩阵元素，$G_{diag}$ 是对角元素。

### 5.3 多层3D热阻处理

当启用 `detailed_3D_used` 时（[src/temperature_grid.c:392](src/temperature_grid.c:392)），每个网格单元可以有不同的电阻值：

```c
if (model->config.detailed_3D_used) {
    // 如果 occupancy >= OCCUPANCY_THRESHOLD (95%)
    // 锁定该网格单元的电阻值
    if (occupancy >= OCCUPANCY_THRESHOLD) {
        ptr->lock = TRUE;
        ptr->rx = getr(1/res, cw, ch * thickness);
        ptr->ry = getr(1/res, ch, cw * thickness);
        ptr->rz = getr(1/res, thickness, cw * ch);
    } else {
        // 多块共享时，电阻并联
        ptr->rx = 1 / ((1 / ptr->rx) + ((1 / getr(...)) * occupancy));
        ptr->ry = 1 / ((1 / ptr->ry) + ((1 / getr(...)) * occupancy));
        ptr->rz = 1 / ((1 / ptr->rz) + ((1 / getr(...)) * occupancy));
    }
}
```

### 5.4 收敛判据

```c
#define LEAK_TOL  0.01    /* 温度收敛阈值 (K) */
#define LEAKAGE_MAX_ITER 100  /* 最大迭代次数 */
```

当连续两次迭代的温度差值小于 `LEAK_TOL` 或迭代次数超过 `LEAKAGE_MAX_ITER` 时停止。

---

## 6. 边界条件

### 6.1 芯片顶部边界

芯片顶部的热量通过扩散或微通道散逸：

```c
// 如果上层是微通道层
if (model->layers[n].is_microchannel) {
    htc = model->layers[n].microchannel_config->htc;
    if (IS_FLUID_CELL(config, i, j)) {
        // 流体单元使用对流换热系数
        res = find_res_3D(...) + (1.0 / (htc * ch * cw));
    }
}
```

### 6.2 芯片底部边界

芯片底部通过封装连接到环境：

```c
// 底部是散热器
if (i == hsidx) {
    // 热阻加上对流热阻
    model->layers[i].rz += model->config.r_convec * 
        (model->config.s_sink * model->config.s_sink) / (cw * ch);
}
```

### 6.3 封装模型

封装层（spread、sink、substrate等）使用简化的集总参数模型。`populate_package_R()` 和 `populate_package_C()` 函数建立封装热阻热容网络。

---

## 7. 与源代码的对应关系

### 7.1 主要函数映射

| 功能 | 函数名 | 源文件 |
|------|--------|--------|
| 网格模型分配 | `alloc_grid_model()` | [src/temperature_grid.c:896](src/temperature_grid.c:896) |
| R矩阵构建 | `populate_R_model_grid()` | [src/temperature_grid.c:950](src/temperature_grid.c:950) |
| C矩阵构建 | `populate_C_model_grid()` | [src/temperature_grid.c:1065](src/temperature_grid.c:1065) |
| 块到网格映射 | `set_bgmap()` | [src/temperature_grid.c:341](src/temperature_grid.c:341) |
| 块功率到网格 | `xlate_vector_b2g()` | [src/temperature_grid.c](src/temperature_grid.c) |
| 网格温度到块 | `xlate_temp_g2b()` | [src/temperature_grid.c](src/temperature_grid.c) |
| 稳态求解 | `steady_state_temp_grid()` | [src/temperature.c](src/temperature.c) |
| 瞬态求解 | `compute_temp_grid()` | [src/temperature.c](src/temperature.c) |

### 7.2 关键数据结构

| 数据结构 | 定义位置 | 用途 |
|----------|----------|------|
| `grid_model_t` | [src/temperature_grid.h:138](src/temperature_grid.h:138) | 完整网格热模型 |
| `layer_t` | [src/temperature_grid.h:101](src/temperature_grid.h:101) | 单层网格配置 |
| `blist_t` | [src/temperature_grid.h:63](src/temperature_grid.h:63) | 块列表（b2gmap节点） |
| `glist_t` | [src/temperature_grid.h:86](src/temperature_grid.h:86) | 网格列表（g2bmap节点） |
| `grid_model_vector_t` | [src/temperature_grid.h:129](src/temperature_grid.h:129) | 网格温度/功率向量 |

### 7.3 配置参数

网格模型配置通过 `thermal_config_t` 结构（[src/temperature.h:141](src/temperature.h:141)）管理：

```c
/* 网格模型特定参数 */
int grid_rows;              /* 网格行数 */
int grid_cols;              /* 网格列数 */
char grid_layer_file[];     /* 层配置文件 */
char grid_map_mode[];       /* 映射模式 */
int detailed_3D_used;       /* 详细3D建模标志 */
```

### 7.4 模型初始化流程

```
alloc_grid_model()
    |
    +-- populate_layers_grid()
    |       |
    |       +-- parse_layer_file() 或 populate_default_layers()
    |       +-- append_package_layers()
    |
    +-- populate_R_model_grid()
    |       |
    |       +-- set_bgmap()          // 建立块-网格映射
    |       +-- populate_package_R() // 封装热阻
    |       +-- 计算每层 rx, ry, rz
    |
    +-- populate_C_model_grid()
            |
            +-- populate_package_C() // 封装热容
            +-- 计算每层 c
```

---

## 附录：热阻和热容计算公式

### 热阻

```c
double getr(double conductivity, double thickness, double area) {
    return thickness / (conductivity * area);
}
```

对于不同方向：
- $R_x = t / (k \cdot A_x) = t / (k \cdot dy \cdot dz)$
- $R_y = t / (k \cdot A_y) = t / (k \cdot dx \cdot dz)$
- $R_z = t / (k \cdot A_z) = t / (k \cdot dx \cdot dy)$

### 热容

```c
double getcap(double sp_heat, double thickness, double area) {
    return sp_heat * thickness * area;
}
```

即 $C = \rho c_p \cdot V$，其中 $\rho$ 是密度，$c_p$ 是比热容。

---

*本文档描述 HotSpot 6.0 网格模型的数学基础和实现细节。*
