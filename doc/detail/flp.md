# flp.c / flp.h - 布局管理模块

## 文件位置

- 头文件: [`src/flp.h`](../../src/flp.h)
- 源文件: [`src/flp.c`](../../src/flp.c)

## 功能概述

布局（floorplan）模块负责：
1. 解析和读写.flp布局文件
2. 布局数据结构的内存管理
3. 布局度量计算（面积、周长、线长等）
4. 布局优化（模拟退火）
5. 布局变换（平移、缩放、旋转）

## 头文件重要定义

### 常量

```c
#define MAX_UNITS     8192   // 最大功能单元数
#define MAX_MOVES     16     // 每次迭代的最大移动数

// 切割类型
#define CUT_NONE      -1
#define CUT_VERTICAL  -2
#define CUT_HORIZONTAL -3

// L2封装比例
#define WRAP_L2_RATIO  5     // L2臂宽高比

// RIM（边缘死区）标记
#define RIM_LEFT   1
#define RIM_RIGHT  2
#define RIM_TOP    4
#define RIM_BOTTOM 8
```

### 方向标记

```c
#define ROT_0    0x01   // 正常
#define ROT_90   0x02   // 逆时针90度
#define ROT_180  0x04   // 逆时针180度
#define ROT_270  0x08   // 逆时针270度
#define FLIP_0   0x10   // 关于Y轴翻转
#define FLIP_90  0x20   // 翻转+90度
#define FLIP_180 0x40   // 翻转+180度
#define FLIP_270 0x80   // 翻转+270度
#define ORIENTS_N 8     // 总方向数
```

## 核心数据结构

### unit_t - 功能单元

```c
typedef struct unit_t_st {
    char name[STR_SIZE];   // 单元名称
    double width;          // 宽度
    double height;         // 高度
    double leftx;          // 左下角X坐标
    double bottomy;         // 左下角Y坐标
    
    // 异构3D参数
    double specificheat;   // 比热容
    double resistivity;    // 电阻率
    int hasRes;            // 是否有特定电阻率
    int hasSh;             // 是否有特定比热容
} unit_t;
```

### flp_t - 布局结构

```c
typedef struct flp_t_st {
    unit_t *units;         // 功能单元数组
    int n_units;           // 单元数
    double **wire_density;  // 线密度矩阵
} flp_t;
```

### flp_config_t - 布局配置

```c
typedef struct flp_config_t_st {
    int wrap_l2;           // 是否封装L2
    char l2_label[STR_SIZE]; // L2标签

    int model_rim;         // 是否建模边缘死区
    double rim_thickness;  // 边缘厚度

    double compact_ratio;   // 忽略死区的面积阈值

    int n_orients;         // 形状曲线的方向数

    // 模拟退火参数
    double P0;             // 初始接受概率
    double Davg;          // 平均代价变化
    double Kmoves;        // 每步尝试的移动数
    double Rcool;         // 冷却比率
    double Rreject;       // 拒绝率阈值
    int Nmax;             // 最大迭代步数

    // 代价函数权重
    double lambdaA;       // 面积权重
    double lambdaT;       // 温度权重
    double lambdaW;       // 线长权重
} flp_config_t;
```

### flp_desc_t - 布局描述

```c
typedef struct flp_desc_t_st {
    unplaced_t *units;        // 未放置的单元
    double **wire_density;     // 线密度
    flp_config_t config;      // 配置
    int n_units;              // 单元数
} flp_desc_t;
```

## 核心函数

### read_flp()

```c
flp_t *read_flp(char *file, int read_connects, int initialize_connects)
```

解析.flp布局文件。三遍解析：

1. **第一遍**：计算单元数
   ```c
   count = flp_count_units(fp);
   ```

2. **第二遍**：填充单元信息
   ```c
   flp_populate_blks(flp, fp);
   ```
   文件格式：
   ```
   Name    Width    Height    LeftX    BottomY    [Cp]    [Res]
   ```

3. **第三遍**：填充连接信息（如果请求）
   ```c
   flp_populate_connects(flp, fp);
   ```
   连接格式：
   ```
   BlockName1    BlockName2    WireDensity
   ```

### dump_flp()

```c
void dump_flp(flp_t *flp, char *file, int dump_connects)
```

将布局写入文件：
```
Name    Width    Height    LeftX    BottomY
Unit1   0.010    0.005    0.000    0.000
Unit2   0.008    0.004    0.010    0.000
...
```

### 布局度量计算

```c
// 获取芯片总宽度
double get_total_width(flp_t *flp);

// 获取芯片总高度
double get_total_height(flp_t *flp);

// 获取总面积
double get_total_area(flp_t *flp);

// 获取核心区域面积（不包括L2和RIM）
double get_core_area(flp_t *flp, char *l2_label);

// 获取曼哈顿线长度量
double get_wire_metric(flp_t *flp);
```

### 线长度量

```c
double get_wire_metric(flp_t *flp) {
    double w = 0.0;
    for (i=0; i < n_units; i++)
        for (j=0; j < n_units; j++)
            if (flp->wire_density[i][j])
                w += wire_density[i][j] * get_manhattan_dist(flp, i, j);
    return w;
}

double get_manhattan_dist(flp_t *flp, int i, int j) {
    x1 = unit[i].leftx + unit[i].width/2;
    y1 = unit[i].bottomy + unit[i].height/2;
    x2 = unit[j].leftx + unit[j].width/2;
    y2 = unit[j].bottomy + unit[j].height/2;
    return fabs(x2-x1) + fabs(y2-y1);
}
```

### 相邻性判断

```c
// 水平相邻
int is_horiz_adj(flp_t *flp, int i, int j) {
    // 检查两个单元是否共享垂直边界
}

// 垂直相邻
int is_vert_adj(flp_t *flp, int i, int j) {
    // 检查两个单元是否共享水平边界
}

// 获取共享边界长度
double get_shared_len(flp_t *flp, int i, int j) {
    if (is_horiz_adj(flp, i, j))
        return overlap in y-direction;
    if (is_vert_adj(flp, i, j))
        return overlap in x-direction;
    return 0;
}
```

### 布局变换

```c
// 平移
void flp_translate(flp_t *flp, double x, double y);

// 缩放
void flp_scale(flp_t *flp, double factor);

// 旋转/翻转
void flp_change_orient(flp_t *flp, double xorig, double yorig,
                     double width, double height, orient_t target);
```

### 布局封装

```c
// 封装L2
void flp_wrap_l2(flp_t *flp, flp_desc_t *flp_desc);

// 封装RIM边缘
int flp_wrap_rim(flp_t *flp, double rim_thickness);
```

### 布局优化 - 模拟退火

```c
int floorplan(flp_t *flp, flp_desc_t *flp_desc,
              RC_model_t *model, double *power)
```

代价函数：
```c
double flp_evaluate_metric(flp_t *flp, RC_model_t *model, double *power,
                         double lambdaA, double lambdaT, double lambdaW) {
    // 计算当前布局的峰值温度
    temp = hotspot_vector(model);
    populate_R_model(model, flp);
    steady_state_temp(model, power, temp);
    tmax = find_max_temp(model, temp);
    
    // 代价 = λA*A + λT*T + λW*W
    return lambdaA * get_total_area(flp) + 
           lambdaT * tmax + 
           lambdaW * get_wire_metric(flp);
}
```

退火过程：
```c
T = -Davg / log(P0);  // 初始温度
Tcold = -Davg / log((1-Rreject)/2);  // 终止温度

while (T >= Tcold && steps < Nmax) {
    for (i=0; i < 2*n && downs < n; i++) {
        next = make_random_move(expr);  // 随机移动
        new_cost = flp_evaluate_metric(...);
        
        if (new_cost < cost || rand() < exp(-(new_cost-cost)/T)) {
            // 接受移动
            cost = new_cost;
        }
    }
    T *= Rcool;  // 冷却
}
```

### 创建网格化布局

```c
flp_t *flp_create_grid(flp_t *flp, int ***map)
```

将非均匀布局转换为均匀网格，用于与网格热模型配合使用。

```c
void xlate_power_blkgrid(flp_t *flp, flp_t *grid,
                         double *bpower, double *gpower, int **map)
```

将块级功率转换到网格级功率（保持功率密度不变）。

## 布局文件格式

### 基本格式 (.flp)

```
Name    Width    Height    LeftX    BottomY    [Cp]    [Res]
alu1    0.010    0.005    0.000    0.000
alu2    0.008    0.004    0.010    0.000
cache   0.020    0.015    0.000    0.005
L2      0.015    0.010    0.010    0.009

# 连接信息（可选）
alu1    alu2    0.5
alu1    cache   0.3
cache   L2      0.8
```

### 带异构参数的格式

```
Name    Width    Height    LeftX    BottomY    Cp          Res
alu1    0.010    0.005    0.000    0.000    1635660    0.01
alu2    0.008    0.004    0.010    0.000    1635660    0.01
```

## 热模型集成

布局与热模型通过以下接口集成：

```c
// 评估给定布局的热代价
double flp_evaluate_metric(flp_t *flp, RC_model_t *model, 
                         double *power, double lambdaA, 
                         double lambdaT, double lambdaW);

// 调整热模型节点数
void resize_thermal_model(RC_model_t *model, int n_units);
```

## 内存管理

```c
void free_flp(flp_t *flp, int compacted, int free_connects)
```

释放布局相关的所有内存：
- `units` 数组
- `wire_density` 矩阵
- 布局结构本身
