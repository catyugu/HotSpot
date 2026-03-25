# flp_desc.c - 布局描述模块

## 文件位置

- 源文件: [`src/flp_desc.c`](../../src/flp_desc.c)
- 声明: [`src/flp.h`](../../src/flp.h)（布局描述类型和函数声明）

## 功能概述

布局描述模块负责解析和管理**未放置**的功能单元布局描述。与 [`flp.c`](../../src/flp.c) 的区别在于：

| 特性 | flp.c | flp_desc.c |
|------|-------|------------|
| 状态 | 已放置（已确定坐标） | 未放置（待规划） |
| 形状 | 固定宽高 | 形状曲线（允许灵活长宽比） |
| 用途 | 温度仿真输入 | 模拟退火规划输入 |

布局描述文件（.desc）包含：
1. 功能单元的面积约束
2. 最小和最大长宽比范围
3. 是否可旋转标志
4. 单元间的连线密度（可选）

hotfloorplan 工具读取描述文件后，通过模拟退火算法放置单元并选择合适的长宽比，输出标准的 .flp 布局文件。

## 核心数据结构

### unplaced_t - 未放置单元

```c
typedef struct unplaced_t_st {
    char name[STR_SIZE];       // 单元名称
    int rotable;               // 是否可旋转
    double area;               // 面积
    double min_aspect;         // 最小长宽比（高/宽）
    double max_aspect;         // 最大长宽比（高/宽）
    shape_t *shape;            // 形状曲线
} unplaced_t;
```

形状曲线（shape_t）定义了该单元所有可能的宽高组合：

```c
typedef struct shape_t_st {
    double *x;      // 宽度数组
    double *y;      // 高度数组
    int *left_pos;  // 左子树方向位置
    int *right_pos; // 右子树方向位置
    double *median; // 分界点
    int size;       // 曲线点数
} shape_t;
```

### flp_desc_t - 布局描述结构

```c
typedef struct flp_desc_t_st {
    unplaced_t *units;         // 未放置单元数组
    double **wire_density;      // 连线密度矩阵
    flp_config_t config;       // 布局配置参数
    int n_units;               // 单元数量
} flp_desc_t;
```

### flp_config_t - 布局配置

```c
typedef struct flp_config_t_st {
    int wrap_l2;               // 是否封装L2
    char l2_label[STR_SIZE];   // L2标签

    int model_rim;             // 是否建模边缘死区
    double rim_thickness;      // 边缘厚度

    double compact_ratio;      // 忽略死区的面积阈值

    int n_orients;             // 形状曲线的离散方向数

    // 模拟退火参数
    double P0;                 // 初始接受概率
    double Davg;              // 平均代价变化
    double Kmoves;            // 每步尝试的移动数
    double Rcool;             // 冷却比率
    double Rreject;           // 拒绝率阈值
    int Nmax;                 // 最大迭代步数

    // 代价函数权重
    double lambdaA;           // 面积权重
    double lambdaT;           // 温度权重
    double lambdaW;           // 线长权重
} flp_config_t;
```

## 核心函数

### read_flp_desc()

```c
flp_desc_t *read_flp_desc(char *file, flp_config_t *config)
```

三遍解析布局描述文件：

**第一遍**：统计单元数量
```c
int desc_count_units(FILE *fp)
```
扫描文件，统计满足格式 `Name Area MinAR MaxAR Rotable` 的行数。

**第二遍**：填充单元信息
```c
void desc_populate_blks(flp_desc_t *flp_desc, FILE *fp)
```
- 解析每行：名称、面积、最小长宽比、最大长宽比、是否可旋转
- 验证参数合法性（最小≤最大，正数）
- 为每个单元生成形状曲线
- 特殊处理：若启用 `wrap_l2`，L2 单元使用特殊封装逻辑

```c
flp_desc->units[i].shape = shape_from_aspect(
    area, min, max, rotable, 
    flp_desc->config.n_orients
);
```

**第三遍**：填充连接信息
```c
void desc_populate_connects(flp_desc_t *flp_desc, FILE *fp)
```
解析连线密度条目 `Name1 Name2 WireDensity`，填充 `wire_density` 矩阵。

### free_flp_desc()

```c
void free_flp_desc(flp_desc_t *flp_desc)
```

释放布局描述的所有内存：
- 每个单元的形状曲线
- 连线密度矩阵
- 单元数组
- 描述结构本身

### desc_get_blk_index()

```c
int desc_get_blk_index(flp_desc_t *flp_desc, char *name)
```

根据名称查找单元索引。若未找到，调用 `fatal()` 终止程序。

### 调试输出函数

```c
// 打印单个未放置单元信息
void print_unplaced(unplaced_t *unit)

// 打印单元信息
void print_flp_desc(flp_desc_t *flp_desc)

// 打印连线密度矩阵
void desc_print_wire_density(flp_desc_t *flp_desc)
```

## 布局描述文件格式

### 基本格式（.desc）

```
# 注释行以 # 开头
# 格式：Name    Area    MinAR    MaxAR    Rotable

# 示例
alu     1e-4    0.5     2.0     1
cache   2e-4    0.3     3.0     0
reg     5e-5    1.0     1.0     1
L2      3e-4    0.8     1.2     0

# 连线密度（可选）
# 格式：BlockName1    BlockName2    WireDensity
alu     cache   0.5
alu     reg     0.3
cache   L2      0.8
```

### 字段说明

| 字段 | 类型 | 说明 |
|------|------|------|
| Name | 字符串 | 功能单元名称 |
| Area | double | 单元面积（平方米） |
| MinAR | double | 最小长宽比（高/宽） |
| MaxAR | double | 最大长宽比（高/宽） |
| Rotable | int | 0=不可旋转，1=可旋转 |

### 形状曲线生成

函数 `shape_from_aspect()` 根据面积和长宽比范围生成形状曲线：

```c
shape_t *shape_from_aspect(
    double area,      // 面积
    double min,       // 最小长宽比
    double max,       // 最大长宽比
    int rotable,      // 是否可旋转
    int n_orients     // 离散方向数
)
```

对于不可旋转单元，形状曲线只包含给定范围内的高度。对于可旋转单元，曲线包含旋转后的情况（交换宽高）。

形状曲线是分段线性函数，定义了该单元所有可能的宽高组合，供模拟退火算法选择。

## 工作流程

```
1. 用户编写 .desc 文件
   ├── 定义功能单元及其面积约束
   ├── 指定长宽比范围
   └── 可选：指定连线密度

2. hotfloorplan 读取描述
   └── read_flp_desc() 解析文件

3. 模拟退火规划
   ├── 构造切片树（slicing tree）
   ├── 在形状曲线上选择每单元的宽高
   └── 优化布局位置

4. 输出 .flp 文件
   └── dump_flp() 保存结果
```

## 与 flp.c 的协作

[`flp.c`](../../src/flp.c) 中的 `flp_placeholder()` 函数从布局描述创建空布局结构：

```c
flp_t *flp_placeholder(flp_desc_t *flp_desc)
```

该函数分配 `flp_t` 结构并将 `flp_desc` 中的基本信息复制过来，但不分配实际的坐标信息（这些由退火过程填充）。

布局优化完成后，调用 `flp_wrap_l2()` 和 `flp_wrap_rim()` 添加封装单元。
