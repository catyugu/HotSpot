# temperature.h / temperature.c - 温度计算核心接口

## 文件位置

- 头文件: [`src/temperature.h`](src/temperature.h)
- 源文件: [`src/temperature.c`](src/temperature.c)

## 功能概述

这是HotSpot热仿真引擎的核心接口层，提供了：
1. 热配置管理 (`thermal_config_t`)
2. 封装RC参数 (`package_RC_t`)
3. RC模型工厂 (`alloc_RC_model`)
4. 稳态/瞬态温度计算的统一接口

## 头文件重要定义

### 模型类型

```c
#define BLOCK_MODEL     0   // 块级模型（每个功能单元一个节点）
#define GRID_MODEL      1   // 网格模型（细粒度网格）
```

### 网格-块映射模式

```c
#define GRID_AVG       0   // 平均值映射
#define GRID_MIN       1   // 最小值映射
#define GRID_MAX       2   // 最大值映射
#define GRID_CENTER    3   // 中心值映射（默认）
```

### 内部节点定义

```c
#define EXTRA 12  // 额外节点数：4个扩散器节点 + 4个散热器内周节点 + 4个散热器外周节点

// 扩散器外围节点 (SP = Spreader)
#define SP_W  0   // 西
#define SP_E  1   // 东
#define SP_N  2   // 北
#define SP_S  3   // 南

// 散热器内周节点 (SINK_C = Center Sink)
#define SINK_C_W 4
#define SINK_C_E 5
#define SINK_C_N 6
#define SINK_C_S 7

// 散热器外周节点
#define SINK_W  8
#define SINK_E  9
#define SINK_N  10
#define SINK_S  11
```

### 二级封装节点（3D IC）

```c
#define EXTRA_SEC 16  // 二级热路径的额外节点

// 封装基板节点
#define SUB_W  12
#define SUB_E  13
#define SUB_N  14
#define SUB_S  15

// 焊球节点
#define SOLDER_W 16
#define SOLDER_E 17
#define SOLDER_N 18
#define SOLDER_S 19

// PCB内周节点
#define PCB_C_W 20
#define PCB_C_E 21
#define PCB_C_N 22
#define PCB_C_S 23

// PCB外周节点
#define PCB_W   24
#define PCB_E   25
#define PCB_N   26
#define PCB_S   27
```

### 物理常数（可配置）

这些参数现在可以在配置文件中设置，不再是硬编码常量。

```c
// 主要材料常数（已移至配置文件）
// RHO_SI, RHO_CU, RHO_INT 等

// 二级路径常数
#define RHO_METAL      0.0025
#define RHO_DIELECTRIC 1.0
#define RHO_C4         0.8
#define RHO_UNDERFILL  0.03
#define RHO_SUB        0.5
#define RHO_SOLDER     0.06
#define RHO_PCB        0.333
```

### 拟合因子

```c
#define C_FACTOR 0.333  // 从传统的1/2改为1/3，以匹配Floworks的块结果
```

### 温度-漏电流迭代常数

```c
#define LEAKAGE_MAX_ITER 100  // 最大热-漏电流迭代次数
#define LEAK_TOL         0.01 // 温度收敛判据（K）
#define TEMP_HIGH        500.0 // 热失控阈值（K）
```

## 热配置结构 thermal_config_t

```c
typedef struct thermal_config_t_st {
    /* 芯片规格 */
    double t_chip;           // 芯片厚度 (m)
    double k_chip;          // 芯片热导率 (W/(m-K))
    double p_chip;          // 芯片比热容 (J/(m^3-K))
    double thermal_threshold; // DTM温度阈值 (K)

    /* 散热器规格 */
    double c_convec;        // 对流电容 (J/K)
    double r_convec;        // 对流电阻 (K/W)
    double s_sink;          // 散热器边长 (m)
    double t_sink;          // 散热器厚度 (m)
    double k_sink;          // 散热器热导率 (W/(m-K))
    double p_sink;          // 散热器比热容 (J/(m^3-K))

    /* 扩散器规格 */
    double s_spreader;      // 扩散器边长 (m)
    double t_spreader;      // 扩散器厚度 (m)
    double k_spreader;      // 扩散器热导率 (W/(m-K))
    double p_spreader;      // 扩散器比热容 (J/(m^3-K))

    /* 界面材料规格 */
    double t_interface;     // 界面材料厚度 (m)
    double k_interface;     // 界面材料热导率 (W/(m-K))
    double p_interface;     // 界面材料比热容 (J/(m^3-K))

    /* 二级热路径规格 */
    int model_secondary;    // 是否启用二级路径
    double r_convec_sec;    // 二级对流电阻
    double c_convec_sec;    // 二级对流电容
    int n_metal;            // 金属层数
    double t_metal;         // 金属层厚度
    double t_c4;             // C4凸点厚度
    double s_c4;             // C4凸点间距
    int n_c4;               // C4凸点数量
    double s_sub;            // 基板尺寸
    double t_sub;            // 基板厚度
    double s_solder;         // 焊球尺寸
    double t_solder;         // 焊球厚度
    double s_pcb;             // PCB尺寸
    double t_pcb;             // PCB厚度

    /* 其他参数 */
    double ambient;          // 环境温度 (K)
    char init_file[STR_SIZE]; // 初始温度文件
    double init_temp;         // 默认初始温度 (K)
    char steady_file[STR_SIZE]; // 稳态温度输出文件
    double sampling_intvl;    // 采样间隔 (s)
    double base_proc_freq;    // 基准处理器频率 (Hz)
    int dtm_used;            // 是否使用DTM

    /* 模型选择 */
    char model_type[STR_SIZE]; // "block" 或 "grid"

    /* 温度-漏电流耦合 */
    int leakage_used;
    int leakage_mode;

    /* 封装模型 */
    int package_model_used;
    char package_config_file[STR_SIZE];

    /* 块模型参数 */
    int block_omit_lateral;   // 是否省略侧向热阻

    /* 网格模型参数 */
    int grid_rows;            // 网格行数
    int grid_cols;            // 网格列数
    char grid_layer_file[STR_SIZE]; // 层配置文件
    char grid_steady_file[STR_SIZE]; // 网格稳态温度文件
    char grid_map_mode[STR_SIZE]; // 映射模式
    char grid_transient_file[STR_SIZE]; // 网格瞬态温度文件

    int detailed_3D_used;     // 是否使用异构3D模型
} thermal_config_t;
```

## 封装RC参数结构 package_RC_t

```c
typedef struct package_RC_t_st {
    /* 侧向热阻 - 扩散器 */
    double r_sp1_x, r_sp1_y;
    /* 侧向热阻 - 散热器内周 */
    double r_hs1_x, r_hs1_y;
    double r_hs2_x, r_hs2_y;
    /* 侧向热阻 - 散热器外周 */
    double r_hs;

    /* 垂直热阻 - 扩散器 */
    double r_sp_per_x, r_sp_per_y;
    /* 垂直热阻 - 散热器内周 */
    double r_hs_c_per_x, r_hs_c_per_y;
    /* 垂直热阻 - 散热器外周 */
    double r_hs_per;

    /* 垂直热容 - 扩散器 */
    double c_sp_per_x, c_sp_per_y;
    /* 垂直热容 - 散热器内周 */
    double c_hs_c_per_x, c_hs_c_per_y;
    /* 垂直热容 - 散热器外周 */
    double c_hs_per;

    /* 到环境的垂直RC - 内周 */
    double r_amb_c_per_x, c_amb_c_per_x;
    double r_amb_c_per_y, c_amb_c_per_y;
    /* 到环境的垂直RC - 外周 */
    double r_amb_per, c_amb_per;

    /* 二级路径侧向热阻 */
    double r_sub1_x, r_sub1_y;
    double r_solder1_x, r_solder1_y;
    double r_pcb1_x, r_pcb1_y;
    double r_pcb2_x, r_pcb2_y;
    double r_pcb;

    /* 二级路径垂直热阻 */
    double r_sub_per_x, r_sub_per_y;
    double r_solder_per_x, r_solder_per_y;
    double r_pcb_c_per_x, r_pcb_c_per_y;
    double r_pcb_per;

    /* 二级路径垂直热容 */
    double c_sub_per_x, c_sub_per_y;
    double c_solder_per_x, c_solder_per_y;
    double c_pcb_c_per_x, c_pcb_c_per_y;
    double c_pcb_per;

    /* PCB到环境的RC */
    double r_amb_sec_c_per_x, c_amb_sec_c_per_x;
    double r_amb_sec_c_per_y, c_amb_sec_c_per_y;
    double r_amb_sec_per, c_amb_sec_per;
} package_RC_t;
```

## RC模型联合体 RC_model_t

```c
typedef struct RC_model_t_st {
    union {
        struct block_model_t_st *block;  // 块模型指针
        struct grid_model_t_st *grid;    // 网格模型指针
    };
    int type;               // BLOCK_MODEL 或 GRID_MODEL
    thermal_config_t *config; // 配置指针
} RC_model_t;
```

## 核心接口函数

### 模型生命周期

```c
// 分配RC模型（工厂函数）
RC_model_t *alloc_RC_model(
    thermal_config_t *config, 
    flp_t *placeholder,
    microchannel_config_t *microchannel_config,
    materials_list_t *materials_list,
    int do_detailed_3D,
    int use_microchannels
);

// 销毁RC模型
void delete_RC_model(RC_model_t *model);
```

### 模型初始化

```c
// 构建热阻网络
void populate_R_model(RC_model_t *model, flp_t *flp);

// 构建热容网络
void populate_C_model(RC_model_t *model, flp_t *flp);
```

### 温度计算

```c
// 稳态温度计算
void steady_state_temp(RC_model_t *model, double *power, double *temp);

// 瞬态温度计算
void compute_temp(RC_model_t *model, double *power, double *temp, double time_elapsed);
```

### 向量操作

```c
// 分配包含内部节点的温度向量
double *hotspot_vector(RC_model_t *model);

// 设置温度向量所有值为val
void set_temp(RC_model_t *model, double *temp, double val);

// 转储温度向量到文件
void dump_temp(RC_model_t *model, double *temp, char *file);

// 读取温度向量从文件
void read_temp(RC_model_t *model, double *temp, char *file, int clip);

// 复制温度向量
void copy_temp(RC_model_t *model, double *dst, double *src);
```

### 功率操作

```c
// 转储功率向量到文件
void dump_power(RC_model_t *model, double *power, char *file);

// 读取功率向量从文件
void read_power(RC_model_t *model, double *power, char *file);
```

### 温度查询

```c
// 查找最大温度
double find_max_temp(RC_model_t *model, double *temp);

// 查找平均温度
double find_avg_temp(RC_model_t *model, double *temp);

// 计算散热器平均温度（自然对流模型）
double calc_sink_temp(RC_model_t *model, double *temp);
```

### 模型调试

```c
// 打印模型调试信息
void debug_print_model(RC_model_t *model);
```

## 源文件核心实现

### default_thermal_config()

返回默认热配置。关键默认值：

| 参数 | 默认值 | 单位 |
|------|--------|------|
| t_chip | 0.15e-3 | m |
| k_chip | 100.0 | W/(m-K) |
| p_chip | 1.75e6 | J/(m^3-K) |
| ambient | 318.15 | K (45C) |
| s_sink | 60e-3 | m |
| s_spreader | 30e-3 | m |
| sampling_intvl | 3.333e-6 | s |
| grid_rows/cols | 64 | - |

### thermal_config_add_from_strs()

将字符串名-值对表解析为热配置结构体。支持以下参数名称：

- 芯片: `t_chip`, `k_chip`, `p_chip`, `material_chip`
- 散热器: `c_convec`, `r_convec`, `s_sink`, `t_sink`, `k_sink`, `p_sink`, `material_sink`
- 扩散器: `s_spreader`, `t_spreader`, `k_spreader`, `p_spreader`, `material_spreader`
- 界面: `t_interface`, `k_interface`, `p_interface`, `material_interface`
- 环境: `ambient`, `init_temp`
- 模型: `model_type`, `block_omit_lateral`
- 网格: `grid_rows`, `grid_cols`, `grid_layer_file`, `grid_map_mode`

### populate_package_R() / populate_package_C()

为封装模型计算热阻和热容值。这些函数根据芯片尺寸和材料属性计算：

- 扩散器侧向/垂直热阻
- 散热器侧向/垂直热阻
- 对流热阻/热容
- 二级路径（基板、焊球、PCB）的RC值

### calc_leakage()

```c
double calc_leakage(int mode, double h, double w, double temp)
```

简单的温度相关漏电流模型：
```
leakage_power = alpha * h * w * exp(beta * (temp - T_base))
```

其中：
- alpha = 1.5e+4
- beta = 0.036
- T_base = 383.15 K (110C)

## 配置示例

```
# 芯片配置
-t_chip 0.00015
-k_chip 100.0
-p_chip 1750000.0

# 散热器配置
-s_sink 0.06
-t_sink 0.0069
-k_sink 400.0
-r_convec 0.1
-c_convec 140.4

# 扩散器配置
-s_spreader 0.03
-t_spreader 0.001
-k_spreader 400.0

# 界面材料
-t_interface 0.00002
-k_interface 4.0

# 环境
-ambient 318.15

# 模型选择
-model_type block
```

## 与块模型/网格模型的接口

temperature.c作为统一接口层，根据model->type调用相应的实现：

```c
void steady_state_temp(RC_model_t *model, double *power, double *temp) {
    if (model->type == BLOCK_MODEL)
        steady_state_temp_block(model->block, power, temp);
    else if (model->type == GRID_MODEL)
        steady_state_temp_grid(model->grid, power, temp);
}

void compute_temp(RC_model_t *model, double *power, double *temp, double time_elapsed) {
    if (model->type == BLOCK_MODEL)
        compute_temp_block(model->block, power, temp, time_elapsed);
    else if (model->type == GRID_MODEL)
        compute_temp_grid(model->grid, power, temp, time_elapsed);
}
```
