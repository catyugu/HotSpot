# HotSpot热模拟器重构与扩展建议

## 1. 引言

HotSpot是一款开源的VLSI热模拟器，支持2D芯片和3D堆叠架构的热仿真。本文档针对代码库中存在的架构问题和现代化需求，提出具体的重构和扩展建议。

### 1.1 代码库现状

**技术栈：**
- 语言标准：C99
- 构建系统：CMake + Ninja
- 可选加速：SuperLU（稀疏矩阵求解）、AVX2向量化

**核心文件结构：**
```
src/
├── hotspot.c          # 主程序入口
├── temperature.c     # 温度计算调度器
├── temperature_block.c # 块级热模型
├── temperature_grid.c  # 网格级热模型（支持3D）
├── microchannel.c     # 微流道冷却
├── flp.c              # 平面规划解析
├── util.c             # 内存分配与工具函数
└── materials.c        # 材料属性
```

**当前模块依赖关系：**
```
hotspot.c
    └── temperature.c
            ├── temperature_block.c
            │       ├── flp.c
            │       └── util.c
            └── temperature_grid.c
                    ├── microchannel.c
                    ├── flp.c
                    └── util.c
```

### 1.2 关键数据结构

**RC_model_t（温度模型基类）：**
```c
typedef struct RC_model_t_st {
    union {
        struct block_model_t_st *block;
        struct grid_model_t_st *grid;
    };
    int type;  // BLOCK_MODEL 或 GRID_MODEL
    thermal_config_t *config;
} RC_model_t;
```

**块模型结构：**
```c
typedef struct block_model_t_st {
    flp_t *flp;
    thermal_config_t config;
    double **b;       // 电导矩阵
    double **lu;      // LUP分解结果
    int *p;           // 置换向量
    double *a;        // 对角电容矩阵
    double *inva;     // a的逆矩阵
    double **c;       // c = inva * b
    double *t_vector; // 临时向量
    int n_nodes;
    int n_units;
} block_model_t;
```

**网格模型结构：**
```c
typedef struct grid_model_t_st {
    thermal_config_t config;
    layer_t *layers;
    int n_layers;
    int rows, cols;
    double width, height;
    int total_n_blocks;
#if SUPERLU > 0
    SuperMatrix G;
    diagonal_matrix_t *C;
#endif
} grid_model_t;
```

---

## 2. 代码质量改进

### 2.1 废弃关键字

**问题描述：**

代码库中未使用`register`关键字，但若后续代码引入此关键字，在C++17编译环境下会导致构建失败。

**示例问题代码：**
```c
// util.h 或其他文件可能存在
register double *v;  // C++17不支持
```

**修复方案：**

直接移除`register`关键字。C99及以上标准中，`register`仅为提示符，编译器会自动进行寄存器优化。

```c
// 修改前
register double *v;

// 修改后
double *v;
```

**建议措施：**

1. 使用静态分析工具扫描整个代码库
2. 建立CI构建检查，同时使用GCC和Clang编译
3. 考虑将项目迁移至纯C99或C11标准

### 2.2 内存安全改进

**问题描述：**

当前动态内存管理存在以下风险：

1. **指针运算缺乏边界检查**
2. **容量计算使用int而非size_t**
3. **二维数组内存布局不连续**

**当前实现（util.c）：**

```c
double **dmatrix(int nr, int nc)
{
    int i;
    double **m;
    m = (double **) calloc (nr, sizeof(double *));
    assert(m != NULL);
    m[0] = (double *) calloc (nr * nc, sizeof(double));
    assert(m[0] != NULL);
    for (i = 1; i < nr; i++)
        m[i] =  m[0] + nc * i;  // 指针运算
    return m;
}
```

**建议改进方案：**

**方案A：结构化矩阵封装**

```c
typedef struct {
    int rows;
    int cols;
    double *data;  // 连续内存
} matrix_t;

matrix_t *matrix_create(int rows, int cols) {
    matrix_t *m = (matrix_t *)malloc(sizeof(matrix_t));
    if (!m) return NULL;
    
    m->rows = rows;
    m->cols = cols;
    m->data = (double *)calloc(rows * cols, sizeof(double));
    if (!m->data) {
        free(m);
        return NULL;
    }
    return m;
}

inline double matrix_get(matrix_t *m, int row, int col) {
    assert(m != NULL);
    assert(row >= 0 && row < m->rows);
    assert(col >= 0 && col < m->cols);
    return m->data[row * m->cols + col];
}

inline void matrix_set(matrix_t *m, int row, int col, double val) {
    assert(m != NULL);
    assert(row >= 0 && row < m->rows);
    assert(col >= 0 && col < m->cols);
    m->data[row * m->cols + col] = val;
}

void matrix_destroy(matrix_t *m) {
    if (m) {
        free(m->data);
        free(m);
    }
}
```

**方案B：添加边界检查宏**

```c
#define MATRIX_CHECK(m, r, c) \
    do { \
        if ((r) < 0 || (r) >= (m)->rows || \
            (c) < 0 || (c) >= (m)->cols) { \
            fatal("matrix index out of bounds\n"); \
        } \
    } while(0)
```

**容量计算改进：**

```c
// 修改前（使用int）
int size = n * m * sizeof(double);

// 修改后（使用size_t）
size_t size = (size_t)n * (size_t)m * sizeof(double);
```

### 2.3 错误处理标准化

**问题描述：**

当前`fatal()`函数设计为立即终止程序，不支持错误恢复。这在长时仿真过程中尤为不便，一旦出现可恢复的错误（如配置参数越界），用户必须重新运行整个仿真。

**当前实现（util.c）：**

```c
void fatal(char *s)
{
    fprintf(stderr, "error: %s", s);
    exit(1);
}

void warning(char *s)
{
    fprintf(stderr, "warning: %s", s);
}
```

**建议改进方案：**

**步骤1：定义错误码枚举**

```c
typedef enum {
    ERR_NONE = 0,
    ERR_MEMORY_ALLOCATION,
    ERR_FILE_NOT_FOUND,
    ERR_INVALID_PARAMETER,
    ERR_MATRIX_SINGULAR,
    ERR_NUMERICAL_OVERFLOW,
    ERR_MODEL_TYPE_UNKNOWN,
    ERR_CONFIG_PARSE_ERROR,
    ERR_MAX
} error_code_t;
```

**步骤2：实现可恢复错误机制**

```c
typedef struct {
    error_code_t code;
    char message[STR_SIZE];
    const char *file;
    int line;
} error_info_t;

static error_info_t global_error = {ERR_NONE, "", NULL, 0};

void set_error(error_code_t code, const char *msg, const char *file, int line) {
    global_error.code = code;
    strncpy(global_error.message, msg, STR_SIZE - 1);
    global_error.file = file;
    global_error.line = line;
}

error_code_t get_error_code(void) {
    return global_error.code;
}

const char *get_error_message(void) {
    return global_error.message;
}

void clear_error(void) {
    global_error.code = ERR_NONE;
    global_error.message[0] = '\0';
}

void fatal_with_info(const char *s, const char *file, int line)
{
    fprintf(stderr, "error: %s", s);
    fprintf(stderr, "  at %s:%d\n", file, line);
    exit(1);
}

// 兼容宏
#define fatal(s) fatal_with_info(s, __FILE__, __LINE__)
```

**步骤3：关键函数返回错误码**

```c
// 修改前
void compute_temp(RC_model_t *model, double *power, double *temp);

// 修改后
int compute_temp(RC_model_t *model, double *power, double *temp) {
    if (!model || !power || !temp) {
        set_error(ERR_INVALID_PARAMETER, "null pointer argument", __FILE__, __LINE__);
        return ERR_INVALID_PARAMETER;
    }
    // ... 计算逻辑
    return ERR_NONE;
}
```

**步骤4：可选的setjmp/longjmp恢复机制**

```c
#include <setjmp.h>

static jmp_buf jump_buffer;

void setup_error_recovery(void) {
    if (setjmp(jump_buffer) != 0) {
        // 从longjmp返回，程序被恢复
        fprintf(stderr, "Recovered from error, resuming...\n");
        clear_error();
    }
}

void trigger_recovery(error_code_t code, const char *msg) {
    set_error(code, msg, __FILE__, __LINE__);
    longjmp(jump_buffer, 1);
}
```

---

## 3. 架构现代化

### 3.1 模块解耦

**问题描述：**

当前架构存在以下耦合问题：

1. `temperature.c`直接包含`temperature_block.c`和`temperature_grid.c`的逻辑
2. `RC_model_t`使用union实现多态，扩展困难
3. 材料系统与热求解器紧耦合

**当前依赖图：**

```
hotspot.c -> temperature.c -> temperature_block.c
                            -> temperature_grid.c -> microchannel.c
```

**建议的目标架构：**

```
                    ┌─────────────────┐
                    │  solver_iface.h │
                    │   (抽象接口层)   │
                    └────────┬────────┘
                             │
         ┌───────────────────┼───────────────────┐
         │                   │                   │
         ▼                   ▼                   ▼
┌─────────────────┐ ┌─────────────────┐ ┌─────────────────┐
│   block_solver  │ │   grid_solver   │ │  micro_solver   │
│ temperature_block│ │ temperature_grid│ │  microchannel   │
└────────┬────────┘ └────────┬────────┘ └─────────────────┘
         │                   │
         └───────────┬───────┘
                     ▼
            ┌─────────────────┐
            │   materials.h   │
            │   (独立模块)     │
            └─────────────────┘
```

**实现步骤：**

**步骤1：定义求解器接口**

```c
// solver_iface.h
#ifndef SOLVER_IFACE_H
#define SOLVER_IFACE_H

typedef struct solver_ops_st {
    int (*init)(void *ctx, void *config);
    int (*populate_R)(void *ctx);
    int (*populate_C)(void *ctx);
    int (*solve_steady)(void *ctx, double *power, double *temp);
    int (*solve_transient)(void *ctx, double *power, double *temp, double dt);
    void (*destroy)(void *ctx);
} solver_ops_t;

typedef struct solver_instance_st {
    void *ctx;
    const solver_ops_t *ops;
    void *config;
} solver_instance_t;

solver_instance_t *solver_create(const char *type, void *config);
int solver_init(solver_instance_t *s);
int solver_solve_steady(solver_instance_t *s, double *power, double *temp);
int solver_solve_transient(solver_instance_t *s, double *power, double *temp, double dt);
void solver_destroy(solver_instance_t *s);

#endif
```

**步骤2：实现插件注册机制**

```c
// solver_registry.c
#include "solver_iface.h"

typedef struct {
    const char *name;
    solver_ops_t ops;
} solver_entry_t;

static solver_entry_t solvers[] = {
    {"block", {
        .init = block_solver_init,
        .populate_R = block_solver_populate_R,
        .populate_C = block_solver_populate_C,
        .solve_steady = block_solver_solve_steady,
        .solve_transient = block_solver_solve_transient,
        .destroy = block_solver_destroy
    }},
    {"grid", {
        .init = grid_solver_init,
        .populate_R = grid_solver_populate_R,
        .populate_C = grid_solver_populate_C,
        .solve_steady = grid_solver_solve_steady,
        .solve_transient = grid_solver_solve_transient,
        .destroy = grid_solver_destroy
    }}
};

solver_instance_t *solver_create(const char *type, void *config) {
    for (int i = 0; i < sizeof(solvers)/sizeof(solvers[0]); i++) {
        if (strcmp(solvers[i].name, type) == 0) {
            solver_instance_t *s = calloc(1, sizeof(solver_instance_t));
            s->ops = &solvers[i].ops;
            s->config = config;
            return s;
        }
    }
    return NULL;  // 未找到匹配的求解器
}
```

### 3.2 数据结构优化

**问题描述：**

当前`dmatrix()`实现的二维数组存在以下问题：

1. 内存不连续（行间可能不连续）
2. 访问效率低（双重指针间接访问）
3. 缓存局部性差

**当前实现问题：**

```c
double **dmatrix(int nr, int nc)
{
    // m[0]是数据指针，m[1..nr-1]是指向m[0]不同偏移的指针
    // 如果realloc发生，数据指针可能改变，但m[1..nr-1]不会自动更新
    m = (double **) calloc (nr, sizeof(double *));
    m[0] = (double *) calloc (nr * nc, sizeof(double));
    for (i = 1; i < nr; i++)
        m[i] = m[0] + nc * i;  // 依赖m[0]地址的固定偏移
}
```

**优化建议：**

**方案A：使用结构体封装连续内存矩阵**

```c
typedef struct {
    int rows;
    int cols;
    double *data;
    int owns_data;  // 标记是否拥有内存
} dense_matrix_t;

// 创建矩阵
dense_matrix_t *dmatrix_create(int rows, int cols) {
    dense_matrix_t *m = calloc(1, sizeof(dense_matrix_t));
    if (!m) return NULL;
    m->rows = rows;
    m->cols = cols;
    m->data = calloc((size_t)rows * cols, sizeof(double));
    if (!m->data) {
        free(m);
        return NULL;
    }
    m->owns_data = 1;
    return m;
}

// 从现有数据创建视图（不复制）
dense_matrix_t *dmatrix_create_view(int rows, int cols, double *data) {
    dense_matrix_t *m = calloc(1, sizeof(dense_matrix_t));
    if (!m) return NULL;
    m->rows = rows;
    m->cols = cols;
    m->data = data;
    m->owns_data = 0;
    return m;
}

// 安全的元素访问
static inline double dmatrix_get(dense_matrix_t *m, int i, int j) {
    assert(m && m->data);
    assert(i >= 0 && i < m->rows && j >= 0 && j < m->cols);
    return m->data[(size_t)i * m->cols + j];
}

static inline void dmatrix_set(dense_matrix_t *m, int i, int j, double val) {
    assert(m && m->data);
    assert(i >= 0 && i < m->rows && j >= 0 && j < m->cols);
    m->data[(size_t)i * m->cols + j] = val;
}

void dmatrix_destroy(dense_matrix_t *m) {
    if (m) {
        if (m->owns_data && m->data)
            free(m->data);
        free(m);
    }
}
```

**方案B：提供BLAS兼容接口**

```c
// 便于接入OpenBLAS或MKL
typedef dense_matrix_t blas_matrix_t;

// BLAS风格访问（列主序，与OpenBLAS兼容）
static inline double blas_get(blas_matrix_t *m, int i, int j) {
    // BLAS使用列主序
    return m->data[(size_t)j * m->rows + i];
}

static inline void blas_set(blas_matrix_t *m, int i, int j, double val) {
    m->data[(size_t)j * m->rows + i] = val;
}
```

### 3.3 配置系统重构

**问题描述：**

当前配置系统使用制表符分隔的纯文本格式，缺乏以下功能：

1. 无schema验证
2. 不支持include
3. 不支持继承和覆盖
4. 类型安全不足

**当前格式示例：**

```
-t_chip             0.00015
-ambient            318.15
-model_type         block
```

**建议的JSON格式：**

```json
{
  "thermal": {
    "t_chip": 0.00015,
    "ambient": 318.15,
    "model_type": "block"
  },
  "grid": {
    "rows": 39,
    "cols": 39
  },
  "package": {
    "c_spreader": 0.1,
    "r_spreader": 0.01
  },
  "materials": {
    "silicon": {
      "k": 150.0,
      "c": 710.0,
      "rho": 2329.0
    }
  }
}
```

**实现建议：**

**步骤1：添加JSON解析库依赖**

推荐使用cJSON（单头文件）或jansson（更完整）。

```cmake
# CMakeLists.txt
find_package(PkgConfig REQUIRED)
pkg_check_modules(JANSSON REQUIRED jansson)

target_link_libraries(hotspot_common PRIVATE ${JANSSON_LIBRARIES})
target_include_directories(hotspot_common PUBLIC ${JANSSON_INCLUDE_DIRS})
```

**步骤2：实现配置读取层**

```c
// config_reader.h
typedef struct thermal_config_st {
    double t_chip;
    double ambient;
    char model_type[STR_SIZE];
    int grid_rows;
    int grid_cols;
    // ... 其他配置项
} thermal_config_t;

int config_from_json(const char *json_file, thermal_config_t *config);
int config_from_legacy(const char *legacy_file, thermal_config_t *config);
int config_validate(const thermal_config_t *config);
```

**步骤3：支持配置继承**

```json
{
  "base": "./default_config.json",
  "overrides": {
    "ambient": 320.0,
    "grid_rows": 64
  }
}
```

---

## 4. 扩展建议

### 4.1 并行化

**当前串行瓶颈：**

`temperature_grid.c`中的网格计算是最主要的性能瓶颈。

```c
// temperature_grid.c 中的串行循环示例
for (i = 0; i < grid->rows; i++) {
    for (j = 0; j < grid->cols; j++) {
        // 逐点计算
        compute_grid_point(grid, i, j, power, temp);
    }
}
```

**OpenMP并行化方案：**

**网格层循环并行化：**

```c
// temperature_grid.c
void compute_temp_grid_parallel(grid_model_t *grid, double *power, double *temp) {
    #pragma omp parallel for collapse(2) schedule(dynamic)
    for (int i = 0; i < grid->rows; i++) {
        for (int j = 0; j < grid->cols; j++) {
            // 计算每个网格点的热流
            compute_grid_point(grid, i, j, power, temp);
        }
    }
}
```

**瞬态仿真的时间步并行：**

```c
// 多个时间步可以并行处理（空间解耦时）
#pragma omp parallel for schedule(dynamic)
for (int t = 0; t < n_timesteps; t++) {
    solve_timestep(grid, power_trace[t], temp + t * n_points, dt);
}
```

**CMake配置：**

```cmake
# 添加OpenMP支持
find_package(OpenMP REQUIRED)
target_link_libraries(hotspot_common PRIVATE OpenMP::OpenMP_C)
```

### 4.2 多物理场耦合

**电-热耦合：**

当前HotSpot仅接收功率trace作为输入。可扩展为接收电路仿真结果，自动计算Joule热。

```c
// electrothermal.h
typedef struct {
    double voltage;
    double current;
    double resistance;
} electrical_data_t;

int electrothermal_couple(
    thermal_config_t *thermal,
    electrical_data_t *e_data,
    int n_nodes,
    double *junction_temps
);
```

**机械应力-热耦合：**

```c
// thermomechanical.h
typedef struct {
    double alpha;      // 热膨胀系数
    double youngs_mod; // 弹性模量
    double poisson_ratio;
} mechanical_props_t;

int compute_thermal_stress(
    grid_model_t *thermal_model,
    mechanical_props_t *props,
    double *stress_tensor
);
```

### 4.3 机器学习集成

**快速热模型近似：**

训练神经网络替代详细的热RC网络，实现毫秒级热估计。

```c
// ml_thermal.h
typedef struct neural_thermal_model_st {
    void *model;           // TensorFlow/PyTorch模型指针
    int n_inputs;
    int n_outputs;
} neural_thermal_model_t;

neural_thermal_model_t *ml_model_load(const char *model_path);
int ml_model_predict(neural_thermal_model_t *m, double *power, double *temp);
void ml_model_destroy(neural_thermal_model_t *m);
```

**功率Trace预测：**

```c
// 使用LSTM预测未来功率Trace，辅助热預測
int ml_predict_power(const char *model_path, double *past_power, 
                     int n_past, double *future_power, int n_future);
```

---

## 5. 测试基础设施

### 5.1 单元测试框架

**推荐框架：Unity（轻量级）或Criterion（功能丰富）**

**CMake集成：**

```cmake
# tests/CMakeLists.txt
add_executable(test_util tests/test_util.c src/util.c)
target_include_directories(test_util PRIVATE src)

add_executable(test_temperature tests/test_temperature.c)
target_link_libraries(test_temperature PRIVATE hotspot_common criterion::criterion)
```

**测试示例：**

```c
// tests/test_util.c
#include "unity.h"
#include "util.h"

void setUp(void) {}
void tearDown(void) {}

void test_dvector_allocation(void) {
    double *v = dvector(10);
    TEST_ASSERT_NOT_NULL(v);
    for (int i = 0; i < 10; i++) {
        TEST_ASSERT_EQUAL_DOUBLE(0.0, v[i]);
    }
    free_dvector(v);
}

void test_dmatrix_allocation(void) {
    double **m = dmatrix(5, 3);
    TEST_ASSERT_NOT_NULL(m);
    TEST_ASSERT_EQUAL_DOUBLE(0.0, m[2][1]);
    free_dmatrix(m);
}

void test_matrix_get_set(void) {
    matrix_t *m = matrix_create(4, 4);
    matrix_set(m, 2, 2, 3.14);
    TEST_ASSERT_EQUAL_DOUBLE(3.14, matrix_get(m, 2, 2));
    matrix_destroy(m);
}

int main(void) {
    UNITY_BEGIN();
    RUN_TEST(test_dvector_allocation);
    RUN_TEST(test_dmatrix_allocation);
    RUN_TEST(test_matrix_get_set);
    return UNITY_END();
}
```

### 5.2 集成测试

**基于示例的回归测试：**

```bash
#!/bin/bash
# tests/integration_test.sh

HOTSPOT=./build/hotspot.exe
FLP=./examples/simple/floorplan.flp
PWR=./examples/simple/power.ptrace
CONFIG=./examples/simple/config

$HOTSPOT -f $FLP -p $PWR -c $CONFIG -o /tmp/output.ttrace

# 与参考输出比较
if diff -q /tmp/output.ttrace ./examples/simple/ref_output.ttrace > /dev/null; then
    echo "PASS: output matches reference"
    exit 0
else
    echo "FAIL: output differs from reference"
    diff /tmp/output.ttrace ./examples/simple/ref_output.ttrace
    exit 1
fi
```

**精度回归检测：**

```python
#!/usr/bin/env python3
# tests/precision_check.py
import numpy as np

def check_precision(ref_file, new_file, rtol=1e-10, atol=1e-12):
    ref = np.loadtxt(ref_file)
    new = np.loadtxt(new_file)
    
    if not np.allclose(ref, new, rtol=rtol, atol=atol):
        max_diff = np.max(np.abs(ref - new))
        print(f"FAIL: Max temperature difference = {max_diff}")
        return False
    print("PASS: Precision maintained")
    return True
```

### 5.3 基准测试

**性能基准套件：**

```c
// benchmark/benchmark.c
typedef struct {
    const char *name;
    const char *flp_file;
    const char *pwr_file;
    int n_timesteps;
    double dt;
} benchmark_case_t;

static benchmark_case_t benchmarks[] = {
    {"simple_2d", "examples/simple.flp", "examples/simple.ptrace", 1000, 0.001},
    {"3d_stacked", "examples/3d/floorplan.flp", "examples/3d/power.ptrace", 500, 0.0001},
    {"microfluidic", "examples/micro/floorplan.flp", "examples/micro/power.ptrace", 200, 0.001},
};

void run_benchmark(benchmark_case_t *bench) {
    RC_model_t *model = alloc_RC_model(config, flp, NULL, NULL, 0, 0);
    
    double *power = read_power_trace(bench->pwr_file);
    double *temp = dvector(model->config.n_nodes);
    
    clock_t start = clock();
    for (int t = 0; t < bench->n_timesteps; t++) {
        compute_temp(model, power + t * model->config.n_nodes, temp, bench->dt);
    }
    clock_t end = clock();
    
    printf("%s: %.3f seconds\n", bench->name, 
           (double)(end - start) / CLOCKS_PER_SEC);
    
    delete_RC_model(model);
    free(temp);
}
```

---

## 6. 优先级建议

### 6.1 高优先级改进

| 改进项 | 当前问题 | 建议方案 | 预期收益 |
|--------|----------|----------|----------|
| 消除C++17警告 | 废弃关键字风险 | 静态扫描 + CI检查 | 构建可靠性 |
| 添加单元测试 | 无测试覆盖 | 引入Unity框架 | 回归防护 |
| 内存安全改进 | 边界检查缺失 | 结构化矩阵封装 | 稳定性提升 |
| 错误处理标准化 | fatal()不可恢复 | 错误码枚举 + setjmp | 可用性改善 |

### 6.2 中优先级改进

| 改进项 | 当前问题 | 建议方案 | 预期收益 |
|--------|----------|----------|----------|
| 配置格式现代化 | 缺乏schema | JSON迁移 | 可维护性 |
| OpenMP并行化 | 串行瓶颈 | 网格循环并行 | 2-4x性能提升 |
| 模块解耦 | 紧耦合 | 策略模式重构 | 扩展性 |
| 文档完善 | 注释不足 | Doxygen生成 | 协作效率 |

### 6.3 低优先级改进

| 改进项 | 当前问题 | 建议方案 | 预期收益 |
|--------|----------|----------|----------|
| GPU加速 | 稀疏矩阵求解慢 | CUDA/OpenCL | 10-100x高端用例 |
| ML集成 | 详细仿真耗时长 | 神经网络近似 | 实时热估计 |
| 多物理场耦合 | 仅热仿真 | 电-热/力-热 | 仿真精度 |
| Web界面 | CLI仅限 | REST API | 易用性 |

### 6.4 实施路线图

**第一阶段（1-2个月）：基础改进**
```
1. 建立CI构建系统（GitHub Actions）
2. 消除所有编译器警告
3. 添加核心单元测试（util, flp模块）
4. 实现错误码枚举
```

**第二阶段（3-4个月）：性能提升**
```
1. OpenMP网格并行化
2. 连续内存矩阵优化
3. 配置系统JSON迁移
4. 完善集成测试
```

**第三阶段（5-6个月）：架构现代化**
```
1. 求解器接口抽象
2. 材料系统模块化
3. 基准测试套件建立
4. 性能回归检测
```

---

## 附录

### A. 关键文件索引

| 文件 | 用途 | 建议修改频率 |
|------|------|--------------|
| src/util.c / util.h | 内存分配、工具函数 | 低 |
| src/temperature.c | 热计算调度 | 中 |
| src/temperature_block.c | 块模型实现 | 中 |
| src/temperature_grid.c | 网格模型实现 | 高 |
| src/CMakeLists.txt | 构建配置 | 中 |

### B. 编译标志说明

```cmake
VERBOSE=0      # 静默模式
VERBOSE=1      # 标准输出
VERBOSE=2      # 详细输出
VERBOSE=3      # 调试级别

SUPERLU=0      # 不使用SuperLU
SUPERLU=1      # 使用SuperLU加速

MATHACCEL=0    # 无数学加速库
MATHACCEL=1    # Intel MKL
MATHACCEL=2    # AMD ACML
MATHACCEL=3    # Apple vecLib
MATHACCEL=4    # Sun Performance Library
```

### C. 参考资源

- HotSpot原始论文：S. Skadron et al., "Temperature-Aware Microarchitecture"
- Unity测试框架：https://github.com/ThrowTheSwitch/Unity
- cJSON库：https://github.com/DaveGamble/cJSON
