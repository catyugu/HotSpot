# hotfloorplan.c / hotfloorplan.h - 温度感知布局优化工具

## 文件位置

- 源文件: [`src/hotfloorplan.c`](../../src/hotfloorplan.c)
- 头文件: [`src/hotfloorplan.h`](../../src/hotfloorplan.h)

## 功能概述

hotfloorplan 是一个温度感知的布局规划工具，通过模拟退火算法优化功能块的放置位置，以最小化峰值温度、面积和线长的加权和。

### 与 hotspot 的区别

| 工具 | 功能 | 输入 | 输出 |
|------|------|------|------|
| hotspot | 对固定布局进行热仿真 | 已放置的 .flp 布局文件 | 温度分布 |
| hotfloorplan | 优化布局以降低温度 | 未放置的布局描述文件 | 优化后的 .flp 文件 |

hotspot 用于评估现有布局的热性能，而 hotfloorplan 用于生成热性能更好的布局。

## 核心数据结构

### global_config_t

```c
typedef struct global_config_t_st {
    char flp_desc[STR_SIZE];      // 布局描述输入文件
    char power_in[STR_SIZE];       // 功率输入文件
    char materials_file[STR_SIZE]; // 材料属性文件
    char flp_out[STR_SIZE];        // 布局输出文件
    char config[STR_SIZE];         // 配置文件路径
    char dump_config[STR_SIZE];    // 配置输出文件路径
} global_config_t;
```

### flp_config_t（来自 [`flp.h`](../../src/flp.h)）

```c
typedef struct flp_config_t_st {
    int wrap_l2;                  // 是否封装 L2
    char l2_label[STR_SIZE];       // L2 标签

    int model_rim;                // 是否建模边缘死区
    double rim_thickness;          // 边缘厚度

    double compact_ratio;          // 忽略死区的面积阈值

    int n_orients;                // 形状曲线的方向数

    // 模拟退火参数
    double P0;                    // 初始接受概率 (默认 0.99)
    double Davg;                  // 平均代价变化 (默认 1.0)
    double Kmoves;                // 每步尝试的移动数 (默认 7.0)
    double Rcool;                 // 冷却比率 (默认 0.99)
    double Rreject;               // 拒绝率阈值 (默认 0.99)
    int Nmax;                    // 最大迭代步数 (默认 1000)

    // 代价函数权重
    double lambdaA;              // 面积权重 (默认 5.0e+6)
    double lambdaT;              // 温度权重 (默认 1.0)
    double lambdaW;              // 线长权重 (默认 350)
} flp_config_t;
```

## 主程序流程

### main() 函数流程

```
1. 解析命令行参数
   └─ parse_cmdline() → str_pair table

2. 读取配置文件（如果指定）
   └─ read_str_pairs() → 追加到 table

3. 合并配置（命令行优先于配置文件）
   └─ str_pairs_remove_duplicates()

4. 设置材料属性
   └─ default_materials() + materials_add_from_file()

5. 初始化热配置和布局配置
   └─ default_thermal_config() + default_flp_config()
   └─ thermal_config_add_from_strs() + flp_config_add_from_strs()

6. 读取未放置的布局描述
   └─ read_flp_desc()

7. 创建占位布局
   └─ flp_placeholder()

8. 分配并初始化 RC 模型
   └─ alloc_RC_model()

9. 读取功率值
   └─ read_power()

10. 运行布局优化（模拟退火）
    └─ floorplan()

11. 输出结果
    ├─ print_flp_fig()      // FIG 格式可视化
    ├─ print_flp_stats()    // 统计信息
    ├─ print_wire_delays()  // 连线延迟
    └─ dump_flp()           // .flp 文件

12. 清理资源
    └─ delete_RC_model() + free_flp_desc() + free_flp()
```

### 完整代码流程

```c
int main(int argc, char **argv) {
    flp_desc_t *flp_desc;
    flp_t *flp;
    RC_model_t *model;
    double *power;
    thermal_config_t thermal_config;
    flp_config_t flp_config;
    global_config_t global_config;
    materials_list_t materials_list;
    str_pair table[MAX_ENTRIES];
    int size, compacted;

    // 1. 解析命令行参数
    if (!(argc >= 7 && argc % 2)) {
        usage(argc, argv);
        return 1;
    }
    size = parse_cmdline(table, MAX_ENTRIES, argc, argv);
    global_config_from_strs(&global_config, table, size);

    // 2. 读取配置文件
    if (strcmp(global_config.config, NULLFILE))
        size += read_str_pairs(&table[size], MAX_ENTRIES, global_config.config);
    size = str_pairs_remove_duplicates(table, size);

    // 3. 设置材料属性
    default_materials(&materials_list);
    if(strncmp(global_config.materials_file, NULLFILE, STR_SIZE))
        materials_add_from_file(&materials_list, global_config.materials_file);

    // 4. 初始化配置
    thermal_config = default_thermal_config();
    flp_config = default_flp_config();
    thermal_config_add_from_strs(&thermal_config, &materials_list, table, size);
    flp_config_add_from_strs(&flp_config, table, size);

    // 5. 读取布局描述
    flp_desc = read_flp_desc(global_config.flp_desc, &flp_config);

    // 6. 创建占位布局
    flp = flp_placeholder(flp_desc);

    // 7. 分配 RC 模型
    model = alloc_RC_model(&thermal_config, flp, NULL, &materials_list, 0, 0);

    // 8. 读取功率
    power = hotspot_vector(model);
    read_power(model, power, global_config.power_in);

    // 9. 运行布局优化
    compacted = floorplan(flp, flp_desc, model, power);

    // 10. 输出结果
    print_flp_fig(flp);                          // FIG 格式
    if (flp_config.wrap_l2 && ...)
        print_flp_stats(flp, model, ...);       // 统计信息
    print_wire_delays(flp, thermal_config.base_proc_freq);
    dump_flp(flp, global_config.flp_out, FALSE);

    // 11. 清理
    free_flp_desc(flp_desc);
    delete_RC_model(model);
    free_dvector(power);
    free_flp(flp, compacted, TRUE);

    return 0;
}
```

## 布局优化算法

### 代价函数

模拟退火过程最小化以下代价：

```
cost = λA * A + λT * T_max + λW * W
```

其中：
- `A` 是布局总面积
- `T_max` 是热仿真计算的峰值温度
- `W` 是基于曼哈顿距离的估计线长
- `λA`, `λT`, `λW` 是各分量的权重

### 代价评估实现

```c
double flp_evaluate_metric(flp_t *flp, RC_model_t *model, double *power,
                           double lambdaA, double lambdaT, double lambdaW) {
    double tmax, area, wire_length;
    double *temp;

    temp = hotspot_vector(model);
    populate_R_model(model, flp);
    steady_state_temp(model, power, temp);
    tmax = find_max_temp(model, temp);
    area = get_total_area(flp);
    wire_length = get_wire_metric(flp);
    free_dvector(temp);

    return (lambdaA * area + lambdaT * tmax + lambdaW * wire_length);
}
```

### 模拟退火过程

```c
// 初始温度
T = -Davg / log(P0);

// 终止温度（当拒绝率超过 Rreject 时停止）
Tcold = -Davg / log((1.0 - Rreject) / 2.0);

while (T >= Tcold && steps < Nmax) {
    n = Kmoves * flp->n_units;
    i = downs = rejects = 0;

    while ((i < 2 * n) && (downs < n)) {
        next = make_random_move(expr);  // 随机布局变换

        // 评估新布局
        new_cost = flp_evaluate_metric(flp, model, tpower,
                                        cfg.lambdaA, cfg.lambdaT, cfg.lambdaW);

        // Metropolis 准则
        if (new_cost < cost ||
            rand_fraction() < exp(-(new_cost - cost) / T)) {
            // 接受移动
            cost = new_cost;
            if (new_cost < best_cost)
                best_cost = new_cost;
        } else {
            // 拒绝移动
            rejects++;
        }
        i++;
    }

    // 冷却
    T *= Rcool;
    steps++;
}
```

### 布局表示

算法使用归一化波兰表达式（NPE）表示布局：

- 使用二叉树表示布局的切片结构
- 每个内部节点是垂直切割（CUT_VERTICAL）或水平切割（CUT_HORIZONTAL）
- 每个叶节点是一个功能块
- 死块用于填充切片之间的空间

### 随机移动操作

```c
NPE_t *make_random_move(NPE_t *expr) {
    // 1. 交换两个相邻的操作数
    // 2. 改变一个运算符的类型
    // 3. 旋转一个叶节点（如果允许）
}
```

## 输出格式

### FIG 格式输出

`print_flp_fig()` 输出布局的可视化数据：

```
FIG starts
leftx bottomy leftx topy rightx topy rightx bottomy leftx bottomy
BlockName
...
FIG ends
```

每行描述一个矩形块及其名称，可由 `scripts/tofig.pl` 脚本转换为 XFIG 格式。

### 统计信息输出

`print_flp_stats()` 输出：

```
printing summary statistics about the floorplan
total area:        <总面积>
total width:       <总宽度>
total height:      <总高度>
core area:         <核心面积>
occupied area:     <占用面积>
area utilization:  <面积利用率百分比>
core width:        <核心宽度>
core height:       <核心高度>
core aspect ratio: <核心宽高比>
wire length metric:<线长度量>
peak temperature:  <峰值温度>
avg temperature:   <平均温度>
```

### 连线延迟输出

`print_wire_delays()` 输出块间的连线延迟：

```
printing wire delay between blocks for global and intermediate metal layers:
(in <frequency> GHz cycles)
name1   name2   global   intermediate
alu1    alu2    0.123    0.456
alu1    cache   0.789    1.234
...
```

### .flp 文件格式

`dump_flp()` 输出的布局文件：

```
Name    Width    Height    LeftX    BottomY
alu1    0.010    0.005    0.000    0.000
alu2    0.008    0.004    0.010    0.000
cache   0.020    0.015    0.000    0.005
...
```

## 命令行用法

```bash
./hotfloorplan -f <floorplan.desc> -p <power.p> -o <output.flp> \
                [-c <config>] [-d <dump.config>] [options]
```

### 必需参数

| 参数 | 说明 |
|------|------|
| `-f <file>` | 布局描述输入文件 (.desc 格式) |
| `-p <file>` | 功率输入文件 (.p 格式) |
| `-o <file>` | 布局输出文件 (.flp 格式) |

### 可选参数

| 参数 | 说明 |
|------|------|
| `-c <file>` | 输入配置文件 |
| `-d <file>` | 输出配置参数到文件 |
| `-materials_file <file>` | 材料属性文件 |

### 配置选项

可以在配置文件中或命令行设置：

```
# 模拟退火参数
P0          0.99       # 初始接受概率
Davg        1.0        # 平均代价变化
Kmoves      7.0        # 每步移动数
Rcool       0.99       # 冷却比率
Rreject     0.99       # 拒绝率阈值
Nmax        1000       # 最大迭代次数

# 代价函数权重
lambdaA     5.0e+6     # 面积权重
lambdaT     1.0        # 温度权重
lambdaW     350        # 线长权重

# L2 封装
wrap_l2     1          # 是否封装 L2
l2_label    L2         # L2 标签
```

## 布局描述文件格式

`.desc` 文件格式：

```
# 格式：名称 面积 最小宽高比 最大宽高比 可旋转(0/1)
alu1    0.000050   0.5   2.0   1
alu2    0.000040   0.5   2.0   1
cache   0.000300   0.8   1.2   0
L2      0.000150   1.0   1.0   0

# 连接信息：块1 块2 线密度
alu1    alu2    0.5
alu1    cache   0.3
cache   L2      0.8
```

## 示例

```bash
# 运行温度感知布局优化
./hotfloorplan.exe -f ev6.desc -p avg.p -o optimized.flp -c hotspot.config

# 使用更高的温度权重
./hotfloorplan.exe -f ev6.desc -p avg.p -o thermal_opt.flp -lambdaT 5.0

# 输出配置以便后续使用
./hotfloorplan.exe -f ev6.desc -p avg.p -o optimized.flp -d my_config.config
```

## 注意事项

1. **网格模型性能**：如果使用网格模型 (`-model_type grid`)，优化会非常慢。3D 芯片模式不支持布局优化。

2. **L2 封装**：如果布局描述文件的最后一个块名称匹配 `l2_label`（默认 "L2"），该块会被自动封装在芯片周围。

3. **收敛性**：模拟退火在拒绝率超过 `Rreject` 阈值时提前停止，或达到 `Nmax` 最大迭代次数。

4. **权重调整**：默认权重针对典型用例设计。如需更注重温度优化，可增大 `lambdaT`；如需更注重面积，可增大 `lambdaA`。
