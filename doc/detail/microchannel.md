# microchannel.c / microchannel.h - 微流控冷却模型

## 文件位置

- 头文件: [`src/microchannel.h`](src/microchannel.h)
- 源文件: [`src/microchannel.c`](src/microchannel.c)

## 功能概述

微流控冷却模型用于模拟芯片上的微通道散热结构。该模型将冷却液在微通道中的流动和传热过程进行建模：

- 离散流体单元格形成流动网络
- 固体单元格用于热传导计算
- 通过水动力电导实现压力-速度耦合
- 固液界面处的热传递系数（HTC）建模

微通道网络通过CSV文件定义，包含不同类型的单元格。模型支持：
- 理想泵和非理想泵（带内部阻力）
- 单相流体冷却
- 与网格热模型的集成

## 核心数据结构

### 单元格类型定义

```c
#define TSV      -1  // 通孔
#define SOLID     0  // 固体单元格（结构材料）
#define FLUID     1  // 流体单元格（内部流体）
#define INLET     2  // 入口流体单元格
#define OUTLET    3  // 出口流体单元格
```

### 微通道配置结构

```c
typedef struct microchannel_config_t_st {
    // 单个单元格尺寸（米）
    double cell_width;        // 单元格宽度
    double cell_height;       // 单元格高度
    double cell_thickness;     // 单元格厚度

    // 泵参数
    double pumping_pressure;   // 入口-出口压差（帕斯卡）
    double pump_internal_res; // 泵内部阻力（K/W）

    // 冷却液参数
    double inlet_temperature;  // 入口温度（开尔文）
    double coolant_capac;      // 体积热容（J/(m^3·K)）
    double coolant_res;        // 热阻率（m·K/W）
    double coolant_visc;       // 动力粘度（Pa·s）

    // 通道壁参数
    double wall_capac;         // 体积热容（J/(m^3·K)）
    double wall_res;           // 热阻率（m·K/W）

    // 界面热传递
    double htc;                // 热传递系数（W/(m^2·K)）

    // 网络文件
    char network_file[STR_SIZE];       // CSV格式微通道网络文件
    char floorplan_file[STR_SIZE+3];   // 生成的flp文件

    // 网络维度
    int num_rows;              // 行数
    int num_columns;           // 列数
    int n_fluid_cells;         // 流体单元格数量

    // 内部数据结构
    int **cell_types;          // 单元格类型数组
    int **mapping;             // 单元格到压力电路节点的映射
    double **A;                // 稀疏压力矩阵
    double *b;                 // 压力方程右端向量
    int nnz;                   // 非零元素数量
} microchannel_config_t;
```

### 辅助宏定义

```c
#define IS_FLUID_CELL(uconf, i, j)  (uconf->cell_types[i][j] == FLUID || \
                                     uconf->cell_types[i][j] == INLET || \
                                     uconf->cell_types[i][j] == OUTLET)

#define IS_INLET_CELL(uconf, i, j)  (uconf->cell_types[i][j] == INLET)

#define IS_OUTLET_CELL(uconf, i, j) (uconf->cell_types[i][j] == OUTLET)
```

## 核心函数

### 配置管理

#### default_microchannel_config()

```c
microchannel_config_t default_microchannel_config(void)
```

返回默认配置的微通道参数。默认值：

| 参数 | 默认值 | 说明 |
|------|--------|------|
| cell_width | 100e-6 | 100微米 |
| cell_height | 100e-6 | 100微米 |
| cell_thickness | 100e-6 | 100微米 |
| pumping_pressure | 5000 | 5kPa |
| pump_internal_res | 0 | 理想泵 |
| inlet_temperature | 300 | 300K |
| coolant_capac | 4172638 | 水 |
| coolant_res | 1.647717911 | 水 |
| coolant_visc | 0.000889 | 水 |
| wall_capac | 1635660 | 硅 |
| wall_res | 0.0076923077 | 硅 |
| htc | 27132 | W/(m^2·K) |

#### microchannel_config_add_from_strs()

```c
void microchannel_config_add_from_strs(microchannel_config_t *config,
                                       materials_list_t *materials_list,
                                       str_pair *table, int size)
```

从字符串对表中解析并添加配置参数。支持直接指定参数值或通过材料名称间接指定：

```c
// 直接指定
pumping_pressure  10000
htc               30000

// 通过材料名称指定（自动查找材料属性）
wall_material     silicon
coolant_material  water
```

支持的材料参数查询：
- `wall_material`: 查询墙体的热导率和体积热容
- `coolant_material`: 查询冷却液的热导率、体积热容和动力粘度

#### microchannel_config_to_strs()

```c
int microchannel_config_to_strs(microchannel_config_t *config,
                                 str_pair *table, int max_entries)
```

将配置转换为字符串对表格式，便于输出和调试。

### 网络构建

#### microchannel_build_network()

```c
void microchannel_build_network(microchannel_config_t *config)
```

构建微通道网络的主要入口函数。执行步骤：

1. 解析CSV网络文件，构建cell_types数组
2. 生成配套的flp格式文件（用于热仿真）
3. 调用build_pressure_matrix()构建压力方程
4. 调用solve_pressure_circuit()求解压力分布

CSV网络文件格式：每行包含逗号分隔的单元格类型（0=固体，1=流体，2=入口，3=出口）。

示例：
```
0, 0, 0, 0, 0, 0, 0, 0
0, 2, 1, 1, 1, 1, 3, 0
0, 1, 1, 1, 1, 1, 1, 0
0, 3, 1, 1, 1, 1, 2, 0
0, 0, 0, 0, 0, 0, 0, 0
```

#### build_pressure_matrix()

```c
void build_pressure_matrix(microchannel_config_t *config)
```

构建压力方程的稀疏矩阵A和右端向量b。

**压力方程建立**：

对于每个流体单元格，压力方程为：
```
P_i * G_sum - Σ(P_j * G_ij) = 0
```
其中G_ij是单元格i和j之间的水动力电导。

**边界条件**：

- 入口单元格（理想泵）：`P_i = pumping_pressure`
- 出口单元格：`P_i = 0`
- 非理想泵：在入口和泵节点之间添加额外电阻

矩阵A的结构：
- 对角元素：`A[i][i] = -Σ G_ij`（流向邻居的电导之和）
- 非对角元素：`A[i][j] = G_ij`（邻居间的电导）

#### solve_pressure_circuit()

```c
void solve_pressure_circuit(microchannel_config_t *config)
```

求解压力电路方程。当启用SuperLU时使用稀疏矩阵求解器，否则使用高斯消元法。

### 流动计算

#### hydroC()

```c
double hydroC(microchannel_config_t *config)
```

计算相邻流体单元格之间的水动力电导（泊肃叶流）。

**矩形通道公式**：

当通道高度h大于宽度w时（h > w）：
```c
hydroC = (1 - 0.63*(w/h)) * w^3 * h / (12 * viscosity * L)
```

当通道宽度w大于高度h时（w > h）：
```c
hydroC = (1 - 0.63*(h/w)) * h^3 * w / (12 * viscosity * L)
```

当h == w（圆形通道近似）：
```c
hydroC = 0.42229 * h^4 / (12 * viscosity * L)
```

其中：
- w = cell_width（通道宽度）
- h = cell_thickness（通道高度）
- L = cell_height（通道长度）
- viscosity = coolant_visc（动力粘度）

#### flow_rate()

```c
double flow_rate(microchannel_config_t *config,
                 int cell1_i, int cell1_j,
                 int cell2_i, int cell2_j)
```

计算两个相邻流体单元格之间的体积流率：

```c
Q = (P1 - P2) * hydroC
```

其中P1和P2是两个单元格的压力，hydroC是水动力电导。

### 内存管理

#### copy_microchannel()

```c
void copy_microchannel(microchannel_config_t *dst, microchannel_config_t *src)
```

复制用户定义的微通道参数（用于配置继承）。

#### free_microchannel()

```c
void free_microchannel(microchannel_config_t *config)
```

释放微通道配置的所有动态分配内存：
- cell_types数组
- A矩阵（压力方程系数矩阵）
- b向量（压力方程右端向量）
- mapping数组（单元格到节点的映射）

## 物理模型说明

### 水动力模型

微通道内的流体流动基于泊肃叶流（Poiseuille flow）假设。流体在矩形截面通道中的压降与流速呈线性关系：

```
ΔP = Q * R_hydro
```

其中R_hydro = 1/hydroC是流体阻力。

**压力电路类比**：

| 流体量 | 电路量 |
|--------|--------|
| 压力 P (Pa) | 电压 V |
| 体积流率 Q (m^3/s) | 电流 I |
| 水动力电导 hydroC | 电导 G = 1/R |
| 泵 | 电压源 |
| 泵内部阻力 | 串联电阻 |

### 热传递模型

**固液界面热阻**：

固液界面处的热阻计算为：
```c
R_interface = 1 / (htc * cell_area)
```

其中cell_area = cell_width * cell_height。

**冷却液热阻**：

冷却液的热阻：
```c
R_coolant = coolant_res * cell_thickness / cell_area
```

**墙体热阻**：

通道壁的热阻：
```c
R_wall = wall_res * cell_thickness / cell_area
```

### 网络文件格式

微通道网络通过CSV文件定义。文件格式：

```
cell_type_1_1, cell_type_2_1, cell_type_3_1, ...
cell_type_1_2, cell_type_2_2, cell_type_3_2, ...
...
```

单元格类型编码：
- `-1`: TSV（通孔，用于3D堆叠）
- `0`: SOLID（固体，结构材料）
- `1`: FLUID（内部流体）
- `2`: INLET（流体入口）
- `3`: OUTLET（流体出口）

### 与网格热模型的集成

微通道冷却作为网格热模型的一个特殊层集成。集成过程：

1. 解析微通道网络文件，构建cell_types
2. 生成对应的flp格式文件
3. 将微通道层添加到网格模型的层列表中
4. 在热传递计算中，考虑冷却液的对流效应

微通道层的热耦合通过固液界面的HTC实现。冷却液温度沿流动方向逐渐升高，体现流体吸热过程。
