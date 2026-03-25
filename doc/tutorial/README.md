# HotSpot 使用教程

## 教程概述

本教程面向希望学习使用 HotSpot 进行 VLSI 热仿真的用户。教程涵盖从环境搭建到高级功能的完整学习路径。

## 学习路径

```
新手入门
    |
    +-- 1. 编译安装 (compilation.md)
    |       |
    |       +-- Windows 编译
    |       +-- Linux 编译
    |       +-- macOS 编译
    |       +-- 可选依赖配置
    |
    +-- 2. 快速开始 (quickstart.md)
    |       |
    |       +-- 运行第一个仿真
    |       +-- 理解输入/输出文件
    |       +-- 基本故障排除
    |
    +-- 3. 配置参考 (configuration.md)
            |
            +-- 所有参数说明
            +-- 材料属性配置
            +-- 3D 配置
            +-- 微流控配置
```

## 文档索引

### 入门阶段

| 文档 | 内容 | 预计时间 |
|------|------|----------|
| [quickstart.md](quickstart.md) | 5 分钟快速上手 | 5 分钟 |
| [compilation.md](compilation.md) | 编译安装指南 | 10 分钟 |

### 进阶阶段

| 文档 | 内容 |
|------|------|
| [configuration.md](configuration.md) | 完整配置参数参考 |

## 推荐学习顺序

### 方案 A：快速体验 (30 分钟)

1. 阅读 [quickstart.md](quickstart.md) 的"环境准备"和"运行第一个仿真"章节
2. 按照步骤编译和运行示例 1
3. 跳过 [compilation.md](compilation.md)，使用预编译版本或 CMake 默认配置

### 方案 B：完整学习 (2 小时)

1. 阅读 [compilation.md](compilation.md) 完成编译环境配置
2. 阅读 [quickstart.md](quickstart.md) 完成快速入门
3. 阅读 [configuration.md](configuration.md) 了解所有配置选项
4. 运行示例 1-6，学习各项功能

## 功能学习路径

### 基础热仿真

```
1. 块级模型
   - 示例 1: 基本稳态/瞬态分析
   - 配置: -model_type block

2. 网格模型
   - 示例 2: 精细温度分布
   - 生成热分布图像
   - 配置: -model_type grid
```

### 高级功能

```
3. 多层布局
   - 示例 3: 多层 2D 布局
   - 层配置文件 (.lcf)

4. 3D IC
   - 示例 4: 3D 堆叠热仿真
   - TSV 建模
   - 配置: -detailed_3D on

5. 微流控冷却
   - 示例 5: 微通道散热
   - 微流控配置参数
   - 配置: -use_microchannels 1

6. 热感知平面规划
   - 示例 6: HotFloorplan 工具
   - 优化目标函数
```

## 常见场景

| 场景 | 推荐文档 | 关键配置 |
|------|----------|----------|
| 快速估算芯片温度 | quickstart.md | `-model_type block` |
| 详细热分析 | examples.md (示例2) | `-model_type grid` |
| 3D 堆叠仿真 | examples.md (示例4) | `-detailed_3D on` |
| 微流控散热 | examples.md (示例5) | `-use_microchannels 1` |
| 平面规划优化 | examples.md (示例6) | hotfloorplan |
| 封装热设计 | examples.md (示例1) | `-package_model_used 1` |

## 参考资料

### 相关文档

- [summary/](../summary/) - 系统架构和算法文档
- [detail/](../detail/) - 源代码详细分析

### 外部资源

- HotSpot 主页: https://lava.cs.virginia.edu/hotspot/
- GitHub: https://github.com/uvahotspot/HotSpot
- 邮件列表: hotspot@virginia.edu

## 故障排除

| 问题 | 解决方案 |
|------|----------|
| 编译失败 | 参考 [compilation.md](compilation.md) 的常见问题章节 |
| 参数错误 | 参考 [configuration.md](configuration.md) 的参数表 |
| 仿真结果异常 | 检查功耗单位、环境温度、散热器配置 |
| 内存不足 | 减小网格尺寸或使用块级模型 |

## 获取帮助

- 查看 [configuration.md](configuration.md) 的参数说明
- 参考 [examples.md](../summary/examples.md) 的示例代码
- 查阅 [executables.md](../summary/executables.md) 的详细选项
- 联系: hotspot@virginia.edu
