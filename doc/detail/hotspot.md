# hotspot.c / hotspot.h - 热仿真器主程序

## 文件位置

- 源文件: [`src/hotspot.c`](src/hotspot.c)
- 头文件: [`src/hotspot.h`](src/hotspot.h)

## 功能概述

这是 HotSpot 热仿真器的命令行主程序，负责：
1. 解析命令行参数和配置文件
2. 读取功率trace文件
3. 初始化热阻热容模型
4. 执行稳态和瞬态温度计算
5. 输出温度trace和稳态温度

## 全局配置结构

```c
typedef struct global_config_t_st {
    char flp_file[STR_SIZE];        // 布局文件路径
    char p_infile[STR_SIZE];        // 功率trace输入文件
    char materials_file[STR_SIZE];   // 材料属性文件
    char t_outfile[STR_SIZE];       // 温度trace输出文件
    char config[STR_SIZE];          // 配置文件路径
    char dump_config[STR_SIZE];     // 配置输出文件路径
    int use_microchannels;          // 是否使用微流控冷却
    char detailed_3D[STR_SIZE];     // 异构3D模型开关
} global_config_t;
```

## 命令行用法

```bash
./hotspot -f <floorplan.flp> -p <power.ptrace> [-o <output.ttrace>] \
          [-c <config>] [-d <dump_config>] [options]
```

### 必需参数

| 参数 | 说明 |
|------|------|
| `-f <file>` | 布局输入文件 (.flp格式) |
| `-p <file>` | 功率trace输入文件 (.ptrace格式) |

### 可选参数

| 参数 | 说明 |
|------|------|
| `-o <file>` | 瞬态温度trace输出文件，不指定则只输出稳态温度到stdout |
| `-c <file>` | 输入配置文件 |
| `-d <file>` | 输出配置参数到文件 |
| `-detailed_3D <on/off>` | 异构R-C赋值（需配合.lcf文件使用） |
| `-use_microchannels <0/1>` | 启用微流控冷却 |

## 主程序流程

### main() 函数流程图

```
1. 解析命令行参数
   └─ parse_cmdline() → str_pair table

2. 读取配置文件（如果指定）
   └─ read_str_pairs() → 追加到table

3. 合并配置（命令行优先于配置文件）
   └─ str_pairs_remove_duplicates()

4. 设置材料属性
   └─ default_materials() + materials_add_from_file()

5. 初始化热配置
   └─ default_thermal_config() + thermal_config_add_from_strs()

6. 读取布局文件
   └─ read_flp() 或从LCF文件

7. 分配并初始化RC模型
   └─ alloc_RC_model()

8. 构建热阻网络
   └─ populate_R_model()

9. 构建热容网络（瞬态模式）
   └─ populate_C_model()

10. 主仿真循环
    ├─ 读取功率trace
    ├─ 计算瞬态温度 compute_temp()
    └─ 输出温度trace

11. 计算稳态温度
    └─ steady_state_temp()

12. 输出稳态温度到文件/stdout
    └─ dump_temp()

13. 清理资源
```

## 关键函数

### global_config_from_strs()

```c
void global_config_from_strs(global_config_t *config, str_pair *table, int size)
```
将字符串名-值对表解析为全局配置结构体。

### read_names() / read_vals()

```c
int read_names(FILE *fp, char **names)    // 读取功能单元名称行
int read_vals(FILE *fp, double *vals)     // 读取功率值行
```
读取功率trace文件的格式：
```
Line 1: unit1_name\tunit2_name\tunit3_name\t...
Line 2: power1\tpower2\tpower3\t...
Line 3: power1\tpower2\tpower3\t...
...
```

### write_names() / write_vals()

```c
void write_names(FILE *fp, char **names, int size)  // 写功能单元名称
void write_vals(FILE *fp, double *vals, int size)   // 写温度值（摄氏度）
```
输出温度trace格式与输入功率trace格式相同。

## 功率到温度的计算流程

```c
// 1. 为每个时间步读取功率值
while ((num=read_vals(pin, vals)) != 0) {
    // 2. 按布局顺序排列功率
    for(i=0; i < n; i++)
        power[get_blk_index(flp, names[i])] = vals[i];
    
    // 3. 计算瞬态温度
    compute_temp(model, power, temp, sampling_intvl);
    
    // 4. 转换回trace顺序
    for(i=0; i < n; i++)
        vals[i] = temp[get_blk_index(flp, names[i])];
    
    // 5. 输出温度trace
    write_vals(tout, vals, n);
}

// 6. 计算并输出稳态温度
steady_state_temp(model, overall_power, steady_temp);
dump_temp(model, steady_temp, steady_file);
```

## 自然对流迭代

当启用封装模型时（`package_model_used=1`），主程序会进行自然对流迭代：

```c
if (natural) {
    while (!natural_convergence) {
        r_convec_old = model->config->r_convec;
        steady_state_temp(model, overall_power, steady_temp);
        avg_sink_temp = calc_sink_temp(model, steady_temp);
        natural = package_model(model->config, table, size, avg_sink_temp);
        populate_R_model(model, flp);  // 重新构建R模型
        // 检查收敛
        if (fabs(model->config->r_convec - r_convec_old) < NATURAL_CONVEC_TOL)
            natural_convergence = 1;
    }
}
```

## 温度-漏电流耦合迭代

当启用温度相关漏电流模型时：

```c
if (config->leakage_used) {
    for (leak_iter=0; (!leak_convg_true) && (leak_iter<=LEAKAGE_MAX_ITER); leak_iter++) {
        // 更新包含漏电流的总功率
        for(i=0; i < n; i++)
            power_new[i] = power[i] + calc_leakage(mode, h, w, temp[i]);
        
        // 重新计算温度
        steady_state_temp(model, power_new, temp);
        
        // 检查温度收敛
        d_max = max(|temp[i] - temp_old[i]|);
        if (d_max < LEAK_TOL)  // 0.01K
            leak_convg_true = 1;
    }
}
```

## 内存管理

主程序分配的主要数组：

| 数组 | 大小 | 说明 |
|------|------|------|
| `temp` | n_nodes | 瞬态温度向量 |
| `power` | n_nodes | 当前功率向量 |
| `steady_temp` | n_nodes | 稳态温度向量 |
| `overall_power` | n_nodes | 累积平均功率 |
| `names` | MAX_UNITS x STR_SIZE | 功能单元名称 |

## 错误处理

- 缺少必需参数 (`p_infile`) → fatal
- 文件打开失败 → fatal
- trace文件格式错误 → fatal
- 模型类型无效 → fatal
- 热失控检测 (>500K) → fatal

## 配置优先级

HotSpot使用以下优先级（高到低）：

1. 命令行参数
2. 配置文件中的值
3. 默认值

这通过 `str_pairs_remove_duplicates()` 函数实现，它保留每个名称第一次出现的值。

## 示例命令

```bash
# 基础稳态+瞬态仿真
./hotspot.exe -f ev6.flp -p gcc.ptrace -o temp.ttrace -c hotspot.config

# 仅稳态仿真
./hotspot.exe -f ev6.flp -p gcc.ptrace -c hotspot.config

# 使用网格模型
./hotspot.exe -f ev6.flp -p gcc.ptrace -model_type grid -grid_rows 128 -grid_cols 128

# 启用微流控冷却
./hotspot.exe -f 3d.flp -p power.ptrace -use_microchannels 1 -detailed_3D on
```
