# HotSpot 文档汇总

## 文档结构

```
doc/
|-- detail/      # 源代码详细分析
|-- summary/     # 系统级文档汇总
|-- model/       # 物理/数学模型
|-- analysis/    # 优缺点分析
|-- tutorial/   # 使用教程
```

## summary 目录说明

本目录提供 HotSpot 的系统级文档，涵盖架构、工具使用、示例和核心算法。

## 文档索引

### 1. 系统架构

| 文档 | 内容 |
|------|------|
| [architecture.md](architecture.md) | HotSpot 整体架构、模块关系、数据流 |

### 2. 工具使用

| 文档 | 内容 |
|------|------|
| [executables.md](executables.md) | hotspot.exe 和 hotfloorplan.exe 完整使用指南 |
| [examples.md](examples.md) | 6 个示例的详细说明和运行方法 |

### 3. 核心算法

| 文档 | 内容 |
|------|------|
| [core_methods.md](core_methods.md) | LUP 分解、RK4、Jacobi 迭代等数值算法 |

## 快速导航

### 新用户

1. 先阅读 [architecture.md](architecture.md) 了解系统架构
2. 阅读 [examples.md](examples.md) 的示例 1 快速上手
3. 参考 [executables.md](executables.md) 查看完整命令行选项

### 进阶用户

1. 深入阅读 [core_methods.md](core_methods.md) 理解数值算法
2. 研究示例 3-5 学习 3D 和微通道功能
3. 使用示例 6 进行热感知平面规划

### 开发者

1. 参考 [`doc/detail/`](../detail/) 目录查看各源文件的详细分析
2. 阅读 [core_methods.md](core_methods.md) 了解核心算法实现
3. 查看 CMakeLists.txt 了解构建配置

## 关键特性总结

| 特性 | 说明 |
|------|------|
| 热模型 | 块级模型 + 网格模型 |
| 3D 支持 | 多层堆叠、TSV、微通道 |
| 求解器 | LUP 分解 (稳态) + RK4 (瞬态) |
| 输出格式 | .flp, .ptrace, .ttrace |
| 构建系统 | CMake 3.15+ |

## 相关链接

- 项目主页: https://lava.cs.virginia.edu/hotspot/
- 源码: [`src/`](../../src/)
- 示例: [`examples/`](../../examples/)
- 配置模板: [`template.config`](../../template.config)
