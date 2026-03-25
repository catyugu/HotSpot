# temperature_grid.c / temperature_grid.h - 网格级热模型

## 文件位置

- 头文件: [`src/temperature_grid.h`](../../src/temperature_grid.h)
- 源文件: [`src/temperature_grid.c`](../../src/temperature_grid.c)

## 功能概述

网格级热模型是HotSpot的精细化热仿真方法，将芯片划分为可配置的网格（默认64x64），能够：
- 模拟芯片内部温度分布
- 支持3D堆叠IC（多层布局）
- 建模微流控冷却
- 提供比块模型更精细的温度预测

## 头文件重要定义

### 层配置常量

```c
#define LCF_NPARAMS 7  // 每层参数数量

// LCF文件字段索引
#define LCF_SNO      0  // 序列号
#define LCF_LATERAL 1  // 是否侧向传热
#define LCF_POWER   2  // 是否耗散功率
#define LCF_SP      3  // 比热容
#define LCF_RHO     4  // 电阻率
#define LCF_THICK   5  // 厚度
#define LCF_FLP     6  // 布局文件
```

### 向量类型

```c
#define V_POWER 0  // 功率向量
#define V_TEMP  1  // 温度向量
```

### 默认层配置

```c
#define DEFAULT_CHIP_LAYERS  2  // 默认芯片层数（不包括扩散器和散热器）
#define LAYER_SI            0  // 硅层
#define LAYER_INT           1  // 界面层

#define SEC_CHIP_LAYERS  2      // 二级热路径芯片层
#define LAYER_C4        0     // C4层
#define LAYER_METAL     1      // 金属层

#define DEFAULT_PACK_LAYERS  2  // 默认封装层数
#define LAYER_SP           0  // 扩散器层
#define LAYER_SINK         1  // 散热器层

#define SEC_PACK_LAYERS  3      // 二级封装层
#define LAYER_PCB       0      // PCB层
#define LAYER_SOLDER    1      // 焊球层
#define LAYER_SUB       2      // 基板层
```

### 占有率阈值

```c
#define OCCUPANCY_THRESHOLD 0.95  // 边界单元计算的有效占有率阈值
```

## 核心数据结构

### blist_t - 块到网格映射链表节点

```c
typedef struct blist_t_st {
    int idx;                    // 映射的块索引
    double occupancy;           // 该块面积占网格单元的比例
    struct blist_t_st *next;    // 下一个映射到同一单元的块
    
    // 异构3D参数
    int lock;                   // 是否锁定热阻值（占有率>阈值）
    int hasRes, hasCap;         // 是否有特定热阻/热容
    double rx, ry, rz;         // x/y/z方向热阻
    double capacitance;         // 热容
} blist_t;
```

### glist_t - 网格到块映射

```c
typedef struct glist_t_st {
    int i1, i2;  // y方向起止索引（不含i2）
    int j1, j2;  // x方向起止索引（不含j2）
} glist_t;
```

### layer_t - 单层结构

```c
typedef struct layer_t_st {
    flp_t *flp;              // 该层布局

    int no;                  // 序列号
    int has_lateral;         // 是否建模侧向传热
    int has_power;           // 是否耗散功率
    double k;                // 热导率 (1/resistivity)
    double thickness;        // 厚度
    double sp;              // 比热容

    /* 微流控参数 */
    int is_microchannel;    // 是否为微流控层
    microchannel_config_t *microchannel_config;

    /* 提取的信息 */
    double rx, ry, rz;      // x/y/z方向热阻
    double c;                // 热容

    /* 映射数据结构 */
    blist_t ***b2gmap;     // 块到网格映射（3D指针数组）
    glist_t *g2bmap;         // 网格到块映射
} layer_t;
```

### grid_model_t - 网格模型主结构

```c
typedef struct grid_model_t_st {
    thermal_config_t config;

    layer_t *layers;        // 层数组
    int n_layers;           // 总层数

    int rows, cols;         // 网格分辨率
    double width, height;   // 芯片尺寸

    package_RC_t pack;       // 封装参数

    int total_n_blocks;     // 所有层的功能单元总数
    int map_mode;           // 网格到块映射模式

    int r_ready, c_ready;   // 初始化标志
    int has_lcf;            // 是否指定了LCF文件

    grid_model_vector_t *last_steady;  // 最近计算的稳态温度
    grid_model_vector_t *last_trans;  // 最近计算的瞬态温度
    double *last_temp;              // 最近计算的块温度

    int base_n_units;       // 原始单元数（用于resize）

    int use_microchannels;
    microchannel_config_t *default_microchannel_config;

#if SUPERLU > 0
    SuperMatrix G;           // SuperLU稀疏矩阵
    diagonal_matrix_t *C;
#endif
} grid_model_t;
```

### grid_model_vector_t - 3D温度/功率向量

```c
typedef struct grid_model_vector_t_st {
    double ***cuboid;  // 3D网格: [layer][row][col]
    double *extra;      // 额外节点（封装）
} grid_model_vector_t;
```

## 核心函数

### alloc_grid_model()

```c
grid_model_t *alloc_grid_model(
    thermal_config_t *config,
    flp_t *flp_default,
    microchannel_config_t *microchannel_config,
    materials_list_t *materials_list,
    int do_detailed_3D,
    int use_microchannels
)
```

分配网格模型并初始化：
1. 解析层配置或使用默认层
2. 计算总层数和节点数
3. 分配层数组和映射结构

### populate_layers_grid()

根据LCF文件或默认配置填充层信息。

当指定LCF文件时，解析格式为：
```
layer_no
Y_or_N (has_lateral_heat_flow)
Y_or_N (has_power_dissipation)
material_name or specific_heat
resistivity
thickness
floorplan_file
```

### set_bgmap()

建立块到网格的双向映射：

```c
void set_bgmap(grid_model_t *model, layer_t *layer)
```

对于每个功能单元：
1. 计算该单元占据的网格单元范围
2. 计算每个网格单元的占有率
3. 如果启用异构3D，则分配特定热阻/热容

### populate_R_model_grid()

构建网格模型的热阻网络：

```c
void populate_R_model_grid(grid_model_t *model, flp_t *flp)
```

计算每层的热阻：
```c
if (has_lateral) {
    rx = getr(k, cell_width, cell_height * thickness);
    ry = getr(k, cell_height, cell_width * thickness);
}
rz = getr(k, thickness, cell_width * cell_height);

// 散热器到环境的附加热阻
if (is_heatsink_layer)
    rz += r_convec * (s_sink * s_sink) / (cell_width * cell_height);
```

### populate_C_model_grid()

```c
void populate_C_model_grid(grid_model_t *model, flp_t *flp)
```

计算每层的热容：
```c
c = getcap(sp, thickness, cell_width * cell_height);

// 散热器到环境的附加热容
if (is_heatsink_layer)
    c += C_FACTOR * c_convec * (cell_width * cell_height) / (s_sink * s_sink);
```

### xlate_vector_b2g()

将块级功率/温度向量转换为网格级：

```c
void xlate_vector_b2g(grid_model_t *model, double *b, grid_model_vector_t *g, int type)
```

对于网格中的每个单元，通过加权平均计算：
- 功率：按面积加权
- 温度：直接加权

### xlate_temp_g2b()

将网格级温度转换为块级温度：

根据映射模式：
- GRID_AVG: 平均值
- GRID_MIN: 最小值
- GRID_MAX: 最大值
- GRID_CENTER: 中心值（默认）

### steady_state_temp_grid()

网格模型稳态求解。默认使用迭代方法：

```c
for (iteration < max_iter) {
    for (each layer) {
        for (each cell) {
            // 计算6个方向的传导和
            csum = sum of conductances
            // 计算邻居温度加权和
            wsum = sum(T_neighbor / R_neighbor) + power
            // 新温度 = wsum / csum
            T_new = wsum / csum
        }
    }
    // 检查收敛
    if (max|T_new - T_old| < tolerance) break;
}
```

### compute_temp_grid()

网格模型瞬态求解（当启用SuperLU时使用后向欧拉法）：

```c
void compute_temp_grid(grid_model_t *model, double *power, double *temp, double time_elapsed)
```

## 块-网格映射详解

### 占有率计算

对于边界网格单元：
```c
// 计算与功能单元的重叠区域
overlap_width = MIN(block_right, cell_right) - MAX(block_left, cell_left)
overlap_height = MIN(block_top, cell_top) - MAX(block_bottom, cell_bottom)
overlap_area = overlap_width * overlap_height

occupancy = overlap_area / cell_area
```

### 异构3D建模

当启用`detailed_3D`时，每个网格单元可以有不同的热阻/热容：

```c
if (occupancy >= OCCUPANCY_THRESHOLD) {
    // 使用占据单元的热阻/热容
    rx = getr(1/resistivity, cell_width, cell_height * thickness);
    lock = TRUE;
} else {
    // 多个单元共享，各按占有率加权
    rx = 1 / ((1/rx + (1/R_other) * occupancy));
    lock = FALSE;
}
```

## 层配置示例（3D堆叠）

```
# example.lcf
0
Y
Y
silicon
0.01
0.00015
core.flp

0
Y
N
silicon
0.01
0.00002
interface.flp

0
N
N
silicon
0.01
0.0003
mem.flp
```

这定义了：
- 1层有功率耗散的硅层
- 1层界面层（无功率）
- 1层存储器层（无功率）

## 微流控冷却集成

微流控层通过特殊处理：

```c
if (layer->is_microchannel) {
    // 使用热传递系数而不是直接传导
    res = find_res_3D(...) + (1.0 / (htc * cell_width * cell_height));
}
```

微流控网络通过CSV文件定义，包含：
- 流体单元（1）
- 固体单元（0）
- TSV单元（-1）
- 入口（2）
- 出口（3）
