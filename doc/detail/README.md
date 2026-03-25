# HotSpot 源代码详细分析 - 总览

本文档对 HotSpot 项目源代码进行逐文件详细分析。

## 目录结构

```
src/
├── 核心仿真引擎
│   ├── temperature.c / temperature.h       # 温度计算核心接口
│   ├── temperature_block.c / .h         # 块级热模型
│   └── temperature_grid.c / .h          # 网格级热模型
├── 主程序入口
│   ├── hotspot.c / hotspot.h           # 热仿真器主程序
│   └── hotfloorplan.c / .h             # 布局规划工具主程序
├── 布局规划模块
│   ├── flp.c / flp.h                   # 布局文件解析与管理
│   ├── flp_desc.c                       # 布局描述工具
│   ├── npe.c / npe.h                   # 归一化波兰表达式
│   └── shape.c / shape.h               # 形状曲线处理
├── 材料与微通道
│   ├── materials.c / materials.h        # 材料热属性数据库
│   └── microchannel.c / microchannel.h # 微流控冷却模型
├── 封装模型
│   └── package.c / package.h           # 封装热阻热容模型
├── 数值计算
│   ├── RCutil.c                        # RC电路与矩阵运算
│   └── util.c / util.h                 # 通用工具函数
└── 辅助模块
    ├── wire.c / wire.h                 # 连线热模型
    ├── hotspot-iface.h                  # 接口定义
    └── sim-template.c                  # 仿真模板
```

## 文件依赖关系图

```
hotspot.c (主入口)
    |
    +-- temperature.c (核心接口)
    |       |
    |       +-- temperature_block.c (块模型)
    |       |       +-- RCutil.c (矩阵运算)
    |       |       +-- flp.c (布局解析)
    |       |       +-- package.c (封装模型)
    |       |
    |       +-- temperature_grid.c (网格模型)
    |               +-- microchannel.c (微流控)
    |               +-- materials.c (材料)
    |
    +-- flp.c (布局解析)
    |       +-- npe.c (布局优化)
    |       +-- shape.c (形状处理)
    |
    +-- util.c (通用工具)
```

## 关键数据结构

### 1. 热配置结构 (thermal_config_t)

位于 [`temperature.h`](src/temperature.h)，定义芯片、散热器、扩散器、接口材料的物理参数。

### 2. RC模型结构 (RC_model_t)

位于 [`temperature.h`](src/temperature.h)，是块模型和网格模型的联合类型。

### 3. 布局结构 (flp_t)

位于 [`flp.h`](src/flp.h)，存储功能单元的位置和尺寸信息。

## 核心算法

1. **稳态求解**: LUP分解 + 前进/后退替换
2. **瞬态求解**: 4阶Runge-Kutta方法（自适应步长）
3. **布局优化**: 模拟退火算法
4. **网格求解**: 迭代Jacobi松弛法

## 下一章

- [hotspot.md](detail/hotspot.md) - 主程序入口详解
- [temperature.md](detail/temperature.md) - 温度计算核心
- [temperature_block.md](detail/temperature_block.md) - 块级模型
- [temperature_grid.md](detail/temperature_grid.md) - 网格级模型
- [flp.md](detail/flp.md) - 布局管理
- [util.md](detail/util.md) - 工具函数
- [RCutil.md](detail/RCutil.md) - 矩阵运算
- [materials.md](detail/materials.md) - 材料属性
- [microchannel.md](detail/microchannel.md) - 微流控冷却
- [package.md](detail/package.md) - 封装模型
