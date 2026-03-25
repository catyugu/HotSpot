# HotSpot 示例指南

## 1 示例概览

HotSpot 提供了 6 个完整的示例，涵盖从基础到高级的功能：

| 示例 | 名称 | 主要特性 |
|------|------|----------|
| example1 | 基础热仿真 | 块级模型、稳态/瞬态分析 |
| example2 | 网格模型 | 网格热模型、图像生成 |
| example3 | 多层平面规划 | 多层 2D 布局 |
| example4 | 3D IC 仿真 | 3D 堆叠、TSV、详细 3D 模式 |
| example5 | 微通道冷却 |  microfluidic 散热 |
| example6 | 热感知平面规划 | HotFloorplan 工具 |

## 2 示例 1：基础热仿真

### 2.1 路径

```
examples/example1/
```

### 2.2 功能

学习 HotSpot 的基本使用方法，包括：
- 块级热模型
- 稳态温度分析
- 瞬态温度追踪
- 封装模型

### 2.3 输入文件

| 文件 | 说明 |
|------|------|
| `ev6.flp` | EV6 处理器平面规划 |
| `gcc.ptrace` | GCC 编译任务的功耗追踪 |
| `example.config` | 仿真配置 |
| `example.materials` | 材料属性 |
| `package.config` | 封装模型配置 |

### 2.4 运行命令

```bash
cd examples/example1

# 第一次运行：使用默认初始温度计算稳态
../../hotspot -c example.config -f ev6.flp -p gcc.ptrace \
    -materials_file example.materials -model_type block \
    -steady_file outputs/gcc.steady -o outputs/gcc.ttrace

# 使用稳态温度作为初始温度重新运行
cp outputs/gcc.steady gcc.init
../../hotspot -c example.config -init_file gcc.init -f ev6.flp \
    -p gcc.ptrace -materials_file example.materials \
    -model_type block -o outputs/gcc.ttrace
```

### 2.5 运行封装模型

```bash
../../hotspot -c example.config -f ev6.flp -p gcc.ptrace \
    -package_model_used 1 -package_config_file package.config \
    -steady_file outputs/gcc_detailed_package.steady
```

### 2.6 输出文件

| 文件 | 说明 |
|------|------|
| `outputs/gcc.steady` | 稳态温度 |
| `outputs/gcc.ttrace` | 瞬态温度追踪 |
| `gcc.init` | 初始温度文件 |

## 3 示例 2：网格模型

### 3.1 路径

```
examples/example2/
```

### 3.2 功能

学习网格热模型的使用，包括：
- 网格模型配置
- 网格与块温度的映射模式
- 生成热分布图像
- 次级热传导路径

### 3.3 输入文件

| 文件 | 说明 |
|------|------|
| `ev6.flp` | EV6 处理器平面规划 |
| `gcc.ptrace` | GCC 编译任务的功耗追踪 |
| `example.config` | 仿真配置 |
| `example.materials` | 材料属性 |

### 3.4 运行命令

```bash
cd examples/example2

# 网格模型稳态仿真
../../hotspot -c example.config -f ev6.flp -p gcc.ptrace \
    -materials_file example.materials -model_type grid \
    -steady_file outputs/gcc.steady -grid_steady_file outputs/gcc.grid.steady

# 使用稳态温度作为初始温度运行瞬态
cp outputs/gcc.steady gcc.init
../../hotspot -c example.config -init_file gcc.init -f ev6.flp \
    -p gcc.ptrace -materials_file example.materials -model_type grid \
    -o outputs/gcc.ttrace -grid_transient_file outputs/gcc.grid.ttrace
```

### 3.5 生成热分布图像

```bash
# 分割网格稳态文件为层级文件
python ../../scripts/split_grid_steady.py outputs/gcc.grid.steady 4 64 64

# 生成 SVG 图像 (需要 Perl)
../../scripts/grid_thermal_map.pl ev6.flp outputs/gcc_layer0.grid.steady > outputs/gcc.svg

# 生成 PNG 图像 (需要 Python)
python ../../scripts/grid_thermal_map.py ev6.flp outputs/gcc_layer0.grid.steady outputs/gcc.png
```

### 3.6 网格映射模式

HotSpot 支持 4 种网格到块的温度映射模式：

| 模式 | 说明 |
|------|------|
| `min` | 使用网格单元的最小温度 |
| `max` | 使用网格单元的最大温度 |
| `avg` | 使用网格单元的平均温度 |
| `center` | 使用块中心的网格单元温度 |

在 `example.config` 中配置：
```
grid_map_mode avg
```

### 3.7 次级热传导路径

```bash
../../hotspot -c example.config -materials_file example.materials \
    -f ev6.flp -p gcc.ptrace -model_type grid \
    -model_secondary 1 -grid_steady_file outputs/gcc.grid.steady
```

## 4 示例 3：多层平面规划

### 4.1 路径

```
examples/example3/
```

### 4.2 功能

学习如何模拟多层 2D 布局：
- 多层平面规划
- 跨层热传导
- 热分布可视化

### 4.3 输入文件

| 文件 | 说明 |
|------|------|
| `floorplan1.flp`, `floorplan2.flp` | 多层平面规划 |
| `example.ptrace` | 多层功耗追踪 |
| `example.lcf` | 层配置文件 |
| `example.config` | 仿真配置 |

### 4.4 运行命令

```bash
cd examples/example3

# 稳态仿真
../../hotspot -c example.config -p example.ptrace \
    -materials_file example.materials -grid_layer_file example.lcf \
    -model_type grid -detailed_3D on \
    -steady_file outputs/example.steady \
    -grid_steady_file outputs/example.grid.steady

# 瞬态仿真
cp outputs/example.steady example.init
../../hotspot -c example.config -p example.ptrace \
    -materials_file example.materials -grid_layer_file example.lcf \
    -init_file example.init -model_type grid -detailed_3D on \
    -o outputs/example.ttrace \
    -grid_transient_file outputs/example.grid.ttrace
```

## 5 示例 4：3D IC 仿真

### 5.1 路径

```
examples/example4/
```

### 5.2 功能

学习 3D 集成电路热仿真：
- 3D 堆叠结构
- TSV (硅通孔) 建模
- 多层热传导
- 详细 3D 模式

### 5.3 输入文件

| 文件 | 说明 |
|------|------|
| `ev6_3D.lcf` | 3D 层配置 |
| `ev6_3D_core_layer.flp` | 核心层平面规划 |
| `ev6_3D_cache_1.flp`, `ev6_3D_cache_2.flp` | 缓存层平面规划 |
| `ev6_3D_TIM.flp` | 热界面材料层 |
| `ev6_3D_TIM_TSV.flp` | TSV 热界面材料层 |
| `ev6_3D.ptrace` | 3D 功耗追踪 |
| `ev6_3D.pdf` | 层布局图 |

### 5.4 结构说明

本示例模拟 4 核 EV6 处理器 + 分割 L2 缓存的 3D 结构：

```
层顺序 (从热sink向下的方向):
----------------------------------------
Layer 5: ev6_3D_core_layer (核心层, 高功耗)
Layer 4: ev6_3D_TIM (热界面材料)
Layer 3: ev6_3D_cache_2 (缓存层 2)
Layer 2: ev6_3D_TIM_TSV (TSV 热界面材料)
Layer 1: ev6_3D_cache_1 (缓存层 1)
Layer 0: (基底)
----------------------------------------
```

### 5.5 运行命令

```bash
cd examples/example4

# 3D 稳态仿真
../../hotspot -c example.config -p ev6_3D.ptrace \
    -materials_file example.materials -grid_layer_file ev6_3D.lcf \
    -model_type grid -detailed_3D on \
    -steady_file outputs/example.steady \
    -grid_steady_file outputs/example.grid.steady

# 3D 瞬态仿真
cp outputs/example.steady example.init
../../hotspot -c example.config -p ev6_3D.ptrace \
    -materials_file example.materials -grid_layer_file ev6_3D.lcf \
    -init_file example.init -model_type grid -detailed_3D on \
    -o outputs/example.transient \
    -grid_transient_file outputs/example.grid.ttrace
```

## 6 示例 5：微通道冷却

### 6.1 路径

```
examples/example5/
```

### 6.2 功能

学习微通道液冷散热仿真：
- 微通道冷却结构
- 微通道几何配置
- 3D 堆叠 + 微通道

### 6.3 输入文件

| 文件 | 说明 |
|------|------|
| `example.lcf` | 微通道层配置 |
| `example.ptrace` | 功耗追踪 |
| `example.config` | 仿真配置 |
| `example.materials` | 材料属性 |
| `floorplans/*.flp` | 各层平面规划 |
| `microchannel_geometries/*.csv` | 微通道几何配置 |

### 6.4 微通道几何

微通道配置定义了冷却通道的布局：

**水平微通道 (horizontal.csv):**
```
channel_width,channel_height,wall_width
100e-6,100e-6,50e-6
```

**垂直微通道 (vertical.csv):**
```
channel_width,channel_height,wall_width
80e-6,80e-6,40e-6
```

### 6.5 运行命令

```bash
cd examples/example5

# 稳态仿真 (微通道冷却)
../../hotspot -c example.config -p example.ptrace \
    -materials_file example.materials -grid_layer_file example.lcf \
    -model_type grid -detailed_3D on -use_microchannels 1 \
    -grid_steady_file outputs/example.grid.steady \
    -steady_file outputs/example.steady

# 瞬态仿真
cp outputs/example.steady example.init
../../hotspot -c example.config -p example.ptrace \
    -materials_file example.materials -grid_layer_file example.lcf \
    -init_file example.init -model_type grid -detailed_3D on \
    -use_microchannels 1 \
    -o outputs/example.transient \
    -grid_transient_file outputs/example.grid.ttrace
```

## 7 示例 6：热感知平面规划

### 7.1 路径

```
examples/example6/
```

### 7.2 功能

学习使用 HotFloorplan 工具进行热感知平面规划：
- 功能块布局优化
- 连线延迟计算
- 自定义目标函数

### 7.3 输入文件

| 文件 | 说明 |
|------|------|
| `ev6.desc` | 功能块描述文件 |
| `avg.p` | 平均功耗 |
| `example.config` | 仿真配置 |

### 7.4 功能块描述格式

`ev6.desc` 文件包含功能块的名称、面积、长宽比范围和连接关系：

```
# name    area    min_ar   max_ar   [connections]
CPU      10.0    0.5     2.0     L2 Cache
L2       5.0     0.5     2.0     CPU Memory
Memory   20.0    0.5     2.0     CPU L2
```

### 7.5 运行命令

```bash
cd examples/example6

# 运行热感知平面规划
../../hotfloorplan -c example.config -f ev6.desc \
    -p avg.p -o output.flp
```

### 7.6 输出

- `output.flp` - 可被 HotSpot 使用的平面规划文件
- stdout - FIG 格式的平面规划图
- stdout - 连线延迟统计

## 8 快速运行所有示例

```bash
# 在项目根目录执行
cd examples

# 示例 1
cd example1 && bash run.sh && cd ..

# 示例 2
cd example2 && bash run.sh && cd ..

# 示例 3
cd example3 && bash run.sh && cd ..

# 示例 4
cd example4 && bash run.sh && cd ..

# 示例 5
cd example5 && bash run.sh && cd ..

# 示例 6
cd example6 && bash run.sh && cd ..
```

## 9 常见问题

### 9.1 缺少 Perl 脚本依赖

某些示例需要 Perl 或 Python 脚本来生成图像。如果缺少依赖，可以跳过图像生成步骤：

```bash
# 跳过图像生成
# 不执行 grid_thermal_map.pl 或 grid_thermal_map.py
```

### 9.2 网格尺寸限制

当不使用 SuperLU 时，网格尺寸限制为 2 的幂次方：

```bash
# 有效的网格尺寸
-grid_rows 32 -grid_cols 32
-grid_rows 64 -grid_cols 64
-grid_rows 128 -grid_cols 128

# 无效的网格尺寸 (会报错或自动调整)
-grid_rows 60 -grid_cols 60
```

### 9.3 内存不足

如果运行 3D 或网格模型时内存不足：

- 减小网格尺寸 (`-grid_rows 32 -grid_cols 32`)
- 减少仿真层数
- 使用块级模型代替网格模型
