# HotSpot 配置参数参考

## 1 配置概述

HotSpot 支持两种配置方式：
1. **命令行参数**：`-<name> <value>`
2. **配置文件**：文本文件，每行一个参数

**优先级：** 命令行参数 > 配置文件 > 默认值

## 2 芯片规格参数

### 2.1 基本芯片参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-t_chip` | m | 0.00015 | 芯片厚度 |
| `-k_chip` | W/(mK) | 130.0 | 芯片热导率 |
| `-p_chip` | J/(m^3K) | 1630300 | 芯片体积热容 |
| `-material_chip` | - | silicon | 芯片材料 (可选) |

### 2.2 材料选择

可用材料定义在 `materials.c` 中：

| 材料名 | 热导率 W/(mK) | 热容 J/(m^3K) |
|--------|---------------|---------------|
| silicon | 130.0 | 1630300 |
| germanium | 60.0 | 1800000 |
| gaas | 44.0 | 1950000 |
| sic | 490.0 | 2950000 |

## 3 散热器参数

### 3.1 几何参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-s_sink` | m | 0.06 | 散热器边长 |
| `-t_sink` | m | 0.0069 | 散热器厚度 |
| `-material_sink` | - | aluminum | 散热器材料 |

### 3.2 热参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-k_sink` | W/(mK) | 400.0 | 散热器热导率 |
| `-p_sink` | J/(m^3K) | 3.55e6 | 散热器体积热容 |
| `-c_convec` | J/K | 140.4 | 对流热容 |
| `-r_convec` | K/W | 1.042 | 对流热阻 |

### 3.3 材料选择

| 材料名 | 热导率 W/(mK) | 热容 J/(m^3K) |
|--------|---------------|---------------|
| aluminum | 237.0 | 2.43e6 |
| copper | 400.0 | 3.55e6 |

## 4 散热片参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-s_spreader` | m | 0.03 | 散热片边长 |
| `-t_spreader` | m | 0.001 | 散热片厚度 |
| `-k_spreader` | W/(mK) | 400.0 | 散热片热导率 |
| `-p_spreader` | J/(m^3K) | 3.55e6 | 散热片体积热容 |
| `-material_spreader` | - | aluminum | 散热片材料 |

## 5 界面材料参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-t_interface` | m | 2.0e-05 | 界面材料厚度 |
| `-k_interface` | W/(mK) | 4.0 | 界面材料热导率 |
| `-p_interface` | J/(m^3K) | 4.0e6 | 界面材料体积热容 |

## 6 次级热传导路径参数

**注意：** 仅在网格模型中可用，不支持微流控冷却。

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-model_secondary` | 0/1 | 0 | 启用次级路径 |
| `-r_convec_sec` | K/W | 50.0 | PCB 对流热阻 |
| `-c_convec_sec` | J/K | 40.0 | PCB 对流热容 |

### 6.1 金属层参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-n_metal` | - | 8 | 金属层层数 |
| `-t_metal` | m | 100.0e-6 | 每层金属厚度 |

### 6.2 C4/底部填充参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-t_c4` | m | 0.0001 | C4/底部填充厚度 |
| `-s_c4` | m | 20.0e-6 | C4 焊盘边长 |
| `-n_c4` | - | 400 | C4 焊盘数量 |

### 6.3 封装基板参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-s_sub` | m | 0.021 | 基板边长 |
| `-t_sub` | m | 0.001 | 基板厚度 |

### 6.4 焊球参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-s_solder` | m | 0.021 | 焊球边长 |
| `-t_solder` | m | 0.00094 | 焊球厚度 |

### 6.5 PCB 参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-s_pcb` | m | 0.1 | PCB 边长 |
| `-t_pcb` | m | 0.002 | PCB 厚度 |

## 7 通用参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-ambient` | K | 318.15 | 环境温度 |
| `-init_temp` | K | 318.15 | 初始温度 |
| `-init_file` | - | (null) | 初始温度文件 |
| `-steady_file` | - | (null) | 稳态温度输出文件 |
| `-sampling_intvl` | s | 0.01 | 采样间隔 |
| `-base_proc_freq` | Hz | 3e9 | 处理器基础频率 |
| `-dtm_used` | 0/1 | 0 | 启用 DTM |
| `-model_type` | - | block | 模型类型 (block/grid) |
| `-leakage_used` | 0/1 | 0 | 启用温度-泄漏循环 |
| `-leakage_mode` | - | 0 | 泄漏计算模式 |

## 8 封装模型参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-package_model_used` | 0/1 | 0 | 启用封装模型 |
| `-package_config_file` | - | package.config | 封装配置文件 |

## 9 块级模型参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-block_omit_lateral` | 0/1 | 0 | 忽略侧面热阻 |

## 10 网格模型参数

### 10.1 网格分辨率

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-grid_rows` | - | 39 | 网格行数 |
| `-grid_cols` | - | 39 | 网格列数 |
| `-grid_layer_file` | - | (null) | 层配置文件 (.lcf) |
| `-grid_steady_file` | - | (null) | 网格稳态温度输出 |
| `-grid_transient_file` | - | (null) | 网格瞬态温度输出 |
| `-grid_map_mode` | - | avg | 网格-块映射模式 |

### 10.2 映射模式选项

| 模式 | 说明 |
|------|------|
| `avg` | 使用网格单元平均值 |
| `min` | 使用网格单元最小值 |
| `max` | 使用网格单元最大值 |
| `center` | 使用块中心网格单元 |

### 10.3 3D 参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-detailed_3D` | on/off | off | 异构 RC 模型 |

## 11 微流控冷却参数

### 11.1 基本参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-use_microfluidic_cooling` | 0/1 | 0 | 启用微流控冷却 |
| `-use_microchannels` | 0/1 | 0 | 启用微通道 (同 use_microfluidic_cooling) |
| `-pumping_pressure` | Pa | 52000 | 泵送压力 |
| `-pump_internal_res` | Pa s/m^3 | 0 | 泵内阻 |
| `-inlet_temperature` | K | 298.15 | 入口冷却液温度 |

### 11.2 冷却液参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-coolant_material` | - | water | 冷却液材料 |
| `-coolant_capac` | J/(m^3K) | 4172638 | 冷却液体积热容 |
| `-coolant_res` | mK/W | 1.6477 | 冷却液热阻率 |
| `-coolant_visc` | Pa s | 8.89e-4 | 冷却液动力粘度 |

### 11.3 通道壁参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-wall_material` | - | silicon | 通道壁材料 |
| `-wall_capac` | J/(m^3K) | 1630300 | 通道壁体积热容 |
| `-wall_res` | mK/W | 0.0077 | 通道壁热阻率 |

### 11.4 传热参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-htc` | W/(m^2K) | 27132 | 传热系数 |

## 12 平面规划参数

### 12.1 L2 缓存参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-wrap_l2` | 0/1 | 1 | 包装 L2 缓存 |
| `-l2_label` | - | L2 | L2 缓存单元名称 |

### 12.2 边缘参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-model_rim` | 0/1 | 0 | 建模边缘死区 |
| `-rim_thickness` | m | 5e-5 | 边缘厚度 |

### 12.3 其他参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-compact_ratio` | - | 0.005 | 忽略死区面积阈值 |
| `-n_orients` | - | 300 | 形状方向数 |

### 12.4 退火参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-P0` | - | 0.99 | 初始接受概率 |
| `-Davg` | - | 1 | 平均代价变化 |
| `-Kmoves` | - | 7 | 每步移动数 |
| `-Rcool` | - | 0.99 | 冷却率 |
| `-Rreject` | - | 0.99 | 拒绝率阈值 |
| `-Nmax` | - | 1000 | 最大退火步数 |

### 12.5 权重参数

| 参数 | 单位 | 默认值 | 说明 |
|------|------|--------|------|
| `-lambdaA` | - | 5.0e6 | 面积项权重 |
| `-lambdaT` | - | 1 | 温度项权重 |
| `-lambdaW` | - | 350 | 线长项权重 |

## 13 材料属性文件

可以使用自定义材料属性文件：

```
# 格式
material_name
  k <热导率>
  p <体积热容>
```

**示例 (example.materials):**
```
silicon
  k 130.0
  p 1630300
copper
  k 400.0
  p 3.55e6
```

## 14 层配置文件 (.lcf)

用于 3D IC 仿真，定义每层的属性：

```
# 格式
layer <层号> <类型>
  thickness <厚度>
  conductivity <热导率>
  sp_heat <体积热容>
  [power <1/0>]
  [microchannel <1/0>]
```

**示例:**
```
layer 0 silicon
  thickness 0.00015
  conductivity 130.0
  sp_heat 1630300
  power 1

layer 1 silicon
  thickness 0.00015
  conductivity 130.0
  sp_heat 1630300
  power 1
```

## 15 配置示例

### 15.1 基本配置 (template.config)

```ini
# 热模型参数
-t_chip 0.00015
-k_chip 130.0
-p_chip 1630300

# 散热器
-r_convec 1.042
-c_convec 140.4
-s_sink 0.06
-t_sink 0.0069

# 散热片
-s_spreader 0.03
-t_spreader 0.001

# 界面材料
-t_interface 2.0e-05
-k_interface 4.0

# 通用
-ambient 318.15
-init_temp 318.15
-sampling_intvl 0.01
-model_type block
```

### 15.2 网格模型配置

```ini
# 网格参数
-model_type grid
-grid_rows 64
-grid_cols 64
-grid_map_mode avg
-grid_steady_file grid_steady.txt
```

### 15.3 3D 配置

```ini
# 3D 参数
-model_type grid
-grid_layer_file layer.lcf
-detailed_3D on
```

### 15.4 微流控配置

```ini
# 微流控参数
-model_type grid
-grid_layer_file layer.lcf
-detailed_3D on
-use_microchannels 1
-pumping_pressure 52000
-inlet_temperature 298.15
-coolant_material water
```

## 16 命令行使用示例

```bash
# 使用配置文件
hotspot.exe -c template.config -f test.flp -p test.ptrace

# 覆盖特定参数
hotspot.exe -c template.config -f test.flp -p test.ptrace \
    -ambient 323.15 -model_type grid -grid_rows 64

# 输出稳态温度
hotspot.exe -f test.flp -p test.ptrace \
    -steady_file steady.txt

# 3D 微流控仿真
hotspot.exe -c layer.lcf -p test.ptrace \
    -model_type grid -detailed_3D on -use_microchannels 1 \
    -grid_steady_file grid_steady.txt
```

## 17 默认值速查

| 参数 | 默认值 |
|------|--------|
| `-t_chip` | 0.00015 m |
| `-k_chip` | 130.0 W/(mK) |
| `-ambient` | 318.15 K |
| `-init_temp` | 318.15 K |
| `-sampling_intvl` | 0.01 s |
| `-model_type` | block |
| `-grid_rows` | 39 |
| `-grid_cols` | 39 |
| `-r_convec` | 1.042 K/W |
| `-c_convec` | 140.4 J/K |
