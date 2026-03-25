# HotSpot 热仿真器重构建议

本文档为 HotSpot 热仿真器的代码架构改进和扩展建议提供参考。文档基于对源代码的详细分析，提出针对内存管理、API设计、冷却技术扩展、性能优化、代码组织和测试基础设施六个方面的改进建议。

---

## 1. 内存管理优化

### 1.1 当前模式分析

HotSpot 使用自定义内存分配器替代标准库实现，主要分配器位于 `src/util.c`：

| 函数 | 分配类型 | 用途 |
|------|----------|------|
| `dvector()` | double 向量 | 温度、功率向量 |
| `dmatrix()` | double 矩阵 | 热阻/热容矩阵 |
| `dcuboid_tail()` | double 三维数组 | 网格温度存储 |
| `ivector()` | int 向量 | 置换向量、索引 |
| `imatrix()` | int 矩阵 | 边界标记数组 |

### 1.2 内存池模式建议

当前分配模式每次调用都执行 `calloc()`，频繁分配/释放会造成堆碎片化。建议实现内存池：

```c
// 内存池结构示例
typedef struct memory_pool_t_st {
    void *chunk;           // 内存块起始指针
    size_t chunk_size;     // 块大小
    size_t used;           // 已使用大小
    struct memory_pool_t_st *next;  // 下一块
} memory_pool_t;

// 池分配器接口
memory_pool_t *pool_create(size_t block_size);
void *pool_alloc(memory_pool_t *pool, size_t size);
void pool_destroy(memory_pool_t *pool);
```

应用场景:
- `hotspot_vector()` 分配的瞬态温度向量可复用
- 矩阵操作中的临时缓冲区可池化
- 网格求解器的迭代缓冲区

### 1.3 对象池模式建议

对于 `block_model_t` 和 `grid_model_t` 等频繁创建/销毁的结构：

```c
// 模型对象池
typedef struct model_pool_t_st {
    block_model_t *block_models;
    grid_model_t *grid_models;
    int pool_size;
    int active_count;
} model_pool_t;

RC_model_t *pool_alloc_model(thermal_config_t *config, int model_type);
void pool_free_model(RC_model_t *model);
```

### 1.4 内存泄漏风险点

当前代码中已识别的泄漏风险:

1. **配置复制问题** (`temperature_block.c:28`)
   ```c
   model->config = *config;  // 浅拷贝，指针成员未复制
   ```

2. **字符串表复制** (`temperature.h:187-196`)
   ```c
   char init_file[STR_SIZE];      // 文件路径未验证生命周期
   char steady_file[STR_SIZE];
   char model_type[STR_SIZE];
   ```

3. **microchannel 配置泄漏** (`microchannel.c:586-616`)
   ```c
   void free_microchannel(microchannel_config_t *config) {
       // cell_types、mapping、config 本身均需正确释放
   }
   ```

4. **矩阵 resize 泄漏** (`temperature_block.c:517-521`)
   ```c
   resize_dmatrix(model->len, model->n_units, model->n_units);
   // resize 后原矩阵数据是否正确保留?
   ```

### 1.5 改进建议总结

| 改进项 | 优先级 | 工作量 |
|--------|--------|--------|
| 实现内存池分配器 | 高 | 中等 |
| 对象池用于 RC_model | 中 | 较大 |
| 添加 valgrind/ASAN 支持 | 高 | 较小 |
| 统一分配/释放接口 | 高 | 较大 |
| 生命周期文档完善 | 中 | 较小 |

---

## 2. API 设计改进

### 2.1 当前联合类型 dispatch 问题

`RC_model_t` 使用 union 进行模型分发:

```c
typedef struct RC_model_t_st {
    union {
        struct block_model_t_st *block;
        struct grid_model_t_st *grid;
    };
    int type;
    thermal_config_t *config;
} RC_model_t;
```

问题:
- 类型安全缺失: 访问 `model->block` 时编译器无法检查
- 扩展性差: 新增模型类型需修改结构定义
- 维护困难: switch-case 分散在多处

### 2.2 接口抽象建议

采用策略模式和接口抽象:

```c
// 模型接口定义
typedef struct thermal_model_ops_t_st {
    void (*steady_state)(void *model, double *power, double *temp);
    void (*compute_temp)(void *model, double *power, double *temp, double time_elapsed);
    double *(*hotspot_vector)(void *model);
    void (*set_temp)(void *model, double *temp, double val);
    void (*dump_temp)(void *model, double *temp, char *file);
    void (*read_temp)(void *model, double *temp, char *file, int clip);
    void (*copy_temp)(void *model, double *dst, double *src);
    double (*find_max_temp)(void *model, double *temp);
    double (*find_avg_temp)(void *model, double *temp);
    void (*delete)(void *model);
} thermal_model_ops_t;

// 通用模型结构
typedef struct thermal_model_t {
    thermal_model_ops_t *ops;
    thermal_config_t *config;
    void *instance;  // 具体模型实例
} thermal_model_t;

// 统一接口
void steady_state_temp(thermal_model_t *model, double *power, double *temp) {
    model->ops->steady_state(model->instance, power, temp);
}
```

### 2.3 策略模式实现

```c
// 块模型策略
static thermal_model_ops_t block_model_ops = {
    .steady_state   = steady_state_temp_block,
    .compute_temp    = compute_temp_block,
    .hotspot_vector = hotspot_vector_block,
    .set_temp       = set_temp_block,
    .dump_temp      = dump_temp_block,
    .read_temp      = read_temp_block,
    .copy_temp      = copy_temp_block,
    .find_max_temp  = find_max_temp_block,
    .find_avg_temp  = find_avg_temp_block,
    .delete         = delete_block_model,
};

// 网格模型策略
static thermal_model_ops_t grid_model_ops = {
    .steady_state   = steady_state_temp_grid,
    .compute_temp   = compute_temp_grid,
    // ... 其他操作
    .delete         = delete_grid_model,
};

// 工厂函数
thermal_model_t *alloc_thermal_model(thermal_config_t *config, ...) {
    thermal_model_t *model = calloc(1, sizeof(thermal_model_t));
    if (config->model_type == BLOCK_MODEL) {
        model->ops = &block_model_ops;
        model->instance = alloc_block_model(config, ...);
    } else {
        model->ops = &grid_model_ops;
        model->instance = alloc_grid_model(config, ...);
    }
    model->config = config;
    return model;
}
```

### 2.4 配置结构改进

```c
// 配置视图模式
typedef struct thermal_config_view_t {
    // 只读访问器
    double (*get_chip_thickness)(thermal_config_t *config);
    double (*get_ambient_temp)(thermal_config_t *config);
    char *(*get_model_type)(thermal_config_t *config);
    // 可选: 验证器
    int (*validate)(thermal_config_t *config);
} thermal_config_view_t;
```

### 2.5 API 设计改进总结

| 改进项 | 优先级 | 兼容性 |
|--------|--------|--------|
| 接口抽象层 | 高 | 需重构 |
| 策略模式实现 | 高 | 需重构 |
| 配置访问器 | 中 | 可渐进 |
| 文档完善 | 中 | 无影响 |

## 3. 性能优化机会

### 3.1 稀疏矩阵优化 (SuperLU)

当前稀疏矩阵集成状态:

```c
#if SUPERLU > 0
// 使用 SuperLU 求解器
int build_A_matrix(SuperMatrix *G, diagonal_matrix_t *C, double h, SuperMatrix *A);
int build_B_matrix(diagonal_matrix_t *C, double *T, double *P, double h, SuperMatrix *B);
double backward_euler(SuperMatrix *G, diagonal_matrix_t *C, ...);
#endif
```

改进建议:

1. **矩阵格式优化**
   - 当前使用 CSC/CSR，可考虑 ELLPACK/ITBLOCK 以提高缓存局部性
   - 添加矩阵重排序选项 (AMD, METIS)

2. **迭代求解器**
   ```c
   // 共轭梯度法 (CG) 用于对称正定矩阵
   typedef struct cg_solver_t_st {
       double tolerance;
       int max_iterations;
       int (*preconditioner)(double **M, double *r);
   } cg_solver_t;
   ```

3. **批量矩阵运算**
   ```c
   // 瞬态分析中批量处理多个时间步
   int batch_backward_euler(SuperMatrix *G, diagonal_matrix_t *C, 
                           double **T_batch, double **P_batch, 
                           int batch_size, double h);
   ```

### 3.2 OpenMP 并行化可能性

热点函数并行化机会:

1. **矩阵-向量乘法** (`matvectmult`)
   ```c
   void matvectmult_parallel(double *vout, double **m, double *vin, int n) {
       #pragma omp parallel for
       for (int i = 0; i < n; i++) {
           double sum = 0;
           for (int j = 0; j < n; j++)
               sum += m[i][j] * vin[j];
           vout[i] = sum;
       }
   }
   ```

2. **网格温度更新** (`temperature_grid.c`)
   ```c
   // Jacobi 迭代求解网格温度
   #pragma omp parallel for collapse(2)
   for (int i = 1; i < grid_rows-1; i++)
       for (int j = 1; j < grid_cols-1; j++)
           T_new[i][j] = (T_old[i-1][j] + T_old[i+1][j] + 
                         T_old[i][j-1] + T_old[i][j+1]) / 4.0;
   ```

3. **热阻/热容批量计算**
   ```c
   #pragma omp parallel for
   for (int i = 0; i < n_units; i++) {
       gx[i] = 1.0/getr(k_chip, flp->units[i].width/2.0, ...);
       gy[i] = 1.0/getr(k_chip, flp->units[i].height/2.0, ...);
   }
   ```

### 3.3 GPU 加速潜力

1. **CUDA 内存管理**
   ```c
   // GPU 矩阵结构
   typedef struct gpu_matrix_t_st {
       double *d_data;      // 设备内存
       int *d_row_ptr;      // 行指针 (CSR)
       int *d_col_idx;      // 列索引
       int rows, cols, nnz; // 维度
   } gpu_matrix_t;
   
   // GPU 矩阵向量乘法
   __global__ void matvectmult_kernel(double *vout, double *m_data, 
                                      int *row_ptr, int *col_idx, 
                                      double *vin, int n);
   ```

2. **cuBLAS/cuSOLVER 集成**
   ```c
   // 使用 cuBLAS 优化 BLAS 运算
   #include <cublas_v2.h>
   
   cublasHandle_t cublas_handle;
   cublasCreate(&cublas_handle);
   cublasDgemv(cublas_handle, CUBLAS_OP_N, n, n, &alpha, 
               d_A, n, d_x, 1, &beta, d_y, 1);
   ```

3. **异步流处理**
   ```c
   cudaStream_t temp_stream, solver_stream;
   // 温度更新与矩阵求解并行
   cudaMemcpyAsync(d_temp, h_temp, ..., cudaMemcpyHostToDevice, temp_stream);
   solve_on_gpu<<<..., temp_stream>>>(...);
   ```

### 3.4 性能优化总结

| 优化项 | 优先级 | 预期收益 | 难度 |
|--------|--------|----------|------|
| SuperLU 参数调优 | 高 | 10-30% | 较小 |
| OpenMP 并行化 | 高 | 2-4x (多核) | 中等 |
| GPU 加速 | 中 | 10-50x | 较大 |
| 缓存优化 | 中 | 20-50% | 中等 |
| SIMD 向量化 | 低 | 2-4x | 中等 |

---

## 4. 代码组织建议

### 4.1 当前模块结构

```
src/
├── temperature_block.c    # 882 行 - 块级热模型
├── temperature_grid.c     # 规模更大 - 网格级热模型
├── temperature.c         # 核心接口
├── microchannel.c        # 616 行 - 微流控冷却
├── RCutil.c              # 数值计算
├── util.c                # 890 行 - 工具函数
├── flp.c                 # 布局管理
└── package.c             # 封装模型
```

问题:
- `temperature_grid.c` 规模过大 (超过 2000 行)
- `util.c` 包含过多不相关功能
- 头文件依赖关系复杂

### 4.2 temperature_grid.c 拆分建议

```
src/grid/
├── temperature_grid.c        # 主入口 (~400行)
├── grid_model.c              # 网格模型结构 (~300行)
├── grid_layer.c              # 层管理 (~200行)
├── grid_solver.c             # 迭代求解器 (~400行)
├── grid_mapping.c             # 网格-块映射 (~200行)
├── grid_io.c                 # 网格 I/O (~200行)
└── temperature_grid.h        # 统一头文件
```

### 4.3 util.c 拆分建议

```
src/util/
├── memory.c                  # 内存分配器
├── string_table.c            # 字符串表操作
├── math_utils.c              # 数学工具
├── random.c                  # 随机数生成
├── search.c                  # 二进制搜索
├── file_utils.c              # 文件操作
└── util.h                    # 统一头文件
```

### 4.4 头文件依赖清理

当前依赖关系:
```
temperature.h
├── flp.h
├── util.h
├── microchannel.h  # 仅部分函数需要
└── materials.h
```

建议按需include:
```c
// temperature_block.h
#ifndef __TEMPERATURE_BLOCK_H_
#define __TEMPERATURE_BLOCK_H_

#include "flp.h"        // 必需: flp_t
#include "thermal_config.h"  // 避免循环依赖

// 前向声明
struct RC_model_t_st;

typedef struct block_model_t_st { ... } block_model_t;

#endif
```

### 4.5 模块接口标准化

```c
// 模块接口模式
#ifndef __MODULE_NAME_H_
#define __MODULE_NAME_H_

#include "module_types.h"  // 公共类型

// 初始化/销毁
module_t *module_create(module_config_t *config);
void module_destroy(module_t *module);

// 主要操作
int module_process(module_t *module, input_t *in, output_t *out);

// 查询接口
int module_get_state(module_t *module, state_t *state);
const char *module_get_version(void);

#endif
```

### 4.6 代码组织总结

| 改进项 | 优先级 | 工作量 |
|--------|--------|--------|
| 拆分 temperature_grid.c | 高 | 较大 |
| 拆分 util.c | 中 | 中等 |
| 依赖关系清理 | 高 | 中等 |
| 统一模块接口 | 中 | 较小 |
| 添加模块测试 | 中 | 中等 |

---

## 5. 测试基础设施

### 5.1 当前测试状态

根据 AGENTS.md 说明:

> **Testing**
> **No formal test suite exists.** Verify changes by:
> 1. Building with `cmake --build build`
> 2. Running `./hotspot.exe -f <test.flp> -p <test.ptrace>` with known inputs
> 3. Comparing outputs against reference results

这是重大技术债务，需建立完整测试体系。

### 5.2 单元测试框架

```c
// tests/unit/test_util.c 示例
#include <assert.h>
#include <math.h>
#include "util.h"

void test_dvector_alloc(void) {
    double *v = dvector(100);
    assert(v != NULL);
    zero_dvector(v, 100);
    for (int i = 0; i < 100; i++)
        assert(eq(v[i], 0.0));
    free_dvector(v);
}

void test_dmatrix_alloc(void) {
    double **m = dmatrix(10, 10);
    assert(m != NULL);
    assert(m[0] != NULL);
    zero_dmatrix(m, 10, 10);
    assert(eq(m[5][5], 0.0));
    free_dmatrix(m);
}

void test_eq_double(void) {
    assert(eq(1.0, 1.0));
    assert(eq(1.0, 1.0 + DELTA/2));
    assert(!eq(1.0, 1.0 + DELTA * 2));
}

int main(void) {
    test_dvector_alloc();
    test_dmatrix_alloc();
    test_eq_double();
    printf("All util tests passed.\n");
    return 0;
}
```

### 5.3 回归测试套件

```c
// tests/regression/test_block_model.c
typedef struct regression_test_t_st {
    const char *name;
    const char *flp_file;
    const char *power_file;
    double expected_max_temp;
    double tolerance;
} regression_test_t;

static regression_test_t block_tests[] = {
    {"simple_2unit", "test/simple_2unit.flp", "test/simple_2unit.ptrace", 350.0, 1.0},
    {"island_4unit", "test/island_4unit.flp", "test/island_4unit.ptrace", 375.0, 1.0},
    {"matrix_10x10", "test/matrix_10x10.flp", "test/matrix_10x10.ptrace", 400.0, 2.0},
};

int run_regression_tests(void) {
    int passed = 0, failed = 0;
    for (int i = 0; i < sizeof(block_tests)/sizeof(block_tests[0]); i++) {
        RC_model_t *model = alloc_RC_model(&config, flp, NULL, NULL, FALSE, FALSE);
        populate_R_model(model, flp);
        populate_C_model(model, flp);
        
        double *power = hotspot_vector(model);
        read_power(model, power, block_tests[i].power_file);
        
        double *temp = hotspot_vector(model);
        steady_state_temp(model, power, temp);
        
        double max_temp = find_max_temp(model, temp);
        if (fabs(max_temp - block_tests[i].expected_max_temp) <= block_tests[i].tolerance) {
            printf("[PASS] %s\n", block_tests[i].name);
            passed++;
        } else {
            printf("[FAIL] %s: expected %.2f, got %.2f\n", 
                   block_tests[i].name, block_tests[i].expected_max_temp, max_temp);
            failed++;
        }
    }
    printf("Regression: %d passed, %d failed\n", passed, failed);
    return failed == 0 ? 0 : 1;
}
```

### 5.4 基准测试框架

```c
// tests/benchmark/benchmark.c
typedef struct benchmark_result_t_st {
    const char *name;
    double time_ms;
    double memory_mb;
    int iterations;
} benchmark_result_t;

double benchmark_steady_state(RC_model_t *model, double *power, int iterations) {
    double *temp = hotspot_vector(model);
    struct timespec start, end;
    
    clock_gettime(CLOCK_MONOTONIC, &start);
    for (int i = 0; i < iterations; i++) {
        steady_state_temp(model, power, temp);
    }
    clock_gettime(CLOCK_MONOTONIC, &end);
    
    free_hotspot_vector(model, temp);
    return (end.tv_sec - start.tv_sec) * 1000.0 + 
           (end.tv_nsec - start.tv_nsec) / 1000000.0;
}

void benchmark_matrix_operations(int size) {
    double **A = dmatrix(size, size);
    double **B = dmatrix(size, size);
    double **C = dmatrix(size, size);
    // ... 初始化
    
    struct timespec start, end;
    clock_gettime(CLOCK_MONOTONIC, &start);
    matmult(C, A, B, size);
    clock_gettime(CLOCK_MONOTONIC, &end);
    
    double time_ms = (end.tv_sec - start.tv_sec) * 1000.0 + 
                     (end.tv_nsec - start.tv_nsec) / 1000000.0;
    printf("matmult(%d): %.2f ms\n", size, time_ms);
}
```

### 5.5 测试基础设施总结

| 测试类型 | 优先级 | 覆盖目标 |
|----------|--------|----------|
| 单元测试 - util | 高 | 内存分配、字符串表、数学工具 |
| 单元测试 - temperature | 高 | 稳态/瞬态求解 |
| 回归测试 | 高 | 已知输入输出对 |
| 性能基准 | 中 | 关键路径耗时 |
| 内存检测 | 高 | valgrind/ASAN |
| 模糊测试 | 低 | 异常输入处理 |
