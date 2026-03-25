# RCutil.c - RC电路与矩阵运算模块

## 文件位置

- 源文件: [`src/RCutil.c`](src/RCutil.c)
- 声明: [`src/temperature.h`](src/temperature.h)

## 功能概述

RCutil模块提供热仿真所需的数值计算功能：

1. **热阻热容计算** - 根据材料属性和几何尺寸计算R和C值
2. **矩阵分解与求解** - LUP分解、前进/后退替换、矩阵求逆
3. **矩阵运算** - 矩阵乘法、矩阵向量乘法、对角矩阵运算
4. **常微分方程求解** - 4阶Runge-Kutta法（自适应步长）、Backward Euler法
5. **向量运算** - 缩放加法运算

模块支持多种数学加速库（Intel MKL、AMD ACML、Apple Accelerate、SUN Performance Library），当这些库可用时自动使用硬件优化的BLAS/LAPACK routines；否则使用纯C实现。

## 核心函数

### 热阻热容计算

#### getr() - 热阻计算

```c
double getr(double conductivity, double thickness, double area)
```

根据导热系数、厚度和面积计算热阻：

```
R = thickness / (conductivity * area)
```

**参数：**
- `conductivity` - 材料导热系数 (W/(m·K))
- `thickness` - 材料厚度 (m)
- `area` - 导热面积 (m²)

**返回值：** 热阻值 (K/W)

#### getcap() - 热容计算

```c
double getcap(double sp_heat, double thickness, double area)
```

计算热容，包含集总参数与分布参数修正：

```c
return C_FACTOR * sp_heat * thickness * area;
```

其中 `C_FACTOR = 0.333`，用于修正与Floworks仿真结果的差异。

**参数：**
- `sp_heat` - 材料比热容 (J/(kg·K))
- `thickness` - 材料厚度 (m)
- `area` - 面积 (m²)

**返回值：** 热容值 (J/K)

---

### 矩阵分解与求解

#### lupdcmp() - LUP分解

```c
void lupdcmp(double**a, int n, int *p, int spd)
```

对矩阵A进行LUP分解，使得 PA = LU，其中P是置换矩阵。分解结果存储在原矩阵a中。

**参数：**
- `a` - 输入矩阵，输出为LU矩阵（就地存储）
- `n` - 矩阵维度
- `p` - 置换向量，记录行交换
- `spd` - 标志：1表示对称正定矩阵（SPD），可使用更高效的dpstrf

**算法说明：**

标准C版本使用部分主元高斯消元：

```c
for (k = 0; k < n-1; k++) {
    // 找第k列绝对值最大的元素作为主元
    max = 0;
    for (i = k; i < n; i++) {
        if (fabs(a[i][k]) > max) {
            max = fabs(a[i][k]);
            pivot = i;
        }
    }
    
    // 交换行
    swap_ival(&p[k], &p[pivot]);
    for (i = 0; i < n; i++)
        swap_dval(&a[k][i], &a[pivot][i]);
    
    // 消元
    for (i = k+1; i < n; i++) {
        a[i][k] /= a[k][k];
        for (j = k+1; j < n; j++)
            a[i][j] -= a[i][k] * a[k][j];
    }
}
```

当定义了 `MATHACCEL` 时，调用对应的LAPACK例程：
- Intel MKL: `dgetrf`（通用）或 `dpotrf`（SPD）
- AMD ACML: `dgetrf_` / `dpotrf_`
- Apple Accelerate: `dgetrf_` / `dpotrf_`
- SUN Performance: `dgetrf_` / `dpotrf_`

#### lusolve() - 前进/后退替换

```c
void lusolve(double **a, int n, int *p, double *b, double *x, int spd)
```

利用LUP分解的结果求解 Ax = b。

**参数：**
- `a` - LU矩阵（来自lupdcmp）
- `n` - 矩阵维度
- `p` - 置换向量
- `b` - 右端向量（输入）
- `x` - 解向量（输出）
- `spd` - 标志：1表示对称正定

**算法说明：**

分两步进行：

1. **前进替换**（求解 Ly = Pb）：
   ```c
   for (i = 0; i < n; i++) {
       sum = 0;
       for (j = 0; j < i; j++)
           sum += y[j] * LOWER(a, i, j);
       y[i] = b[p[i]] - sum;
   }
   ```

2. **后退替换**（求解 Ux = y）：
   ```c
   for (i = n-1; i >= 0; i--) {
       sum = 0;
       for (j = i+1; j < n; j++)
           sum += x[j] * UPPER(a, i, j);
       x[i] = (y[i] - sum) / UPPER(a, i, i);
   }
   ```

宏定义用于提取L和U矩阵：
```c
#define LOWER(a, i, j) ((i > j) ? a[i][j] : 0)
#define UPPER(a, i, j) ((i <= j) ? a[i][j] : 0)
```

#### matinv() - 矩阵求逆

```c
void matinv(double **inv, double **m, int n, int spd)
```

计算矩阵m的逆矩阵，存储到inv中。

**参数：**
- `inv` - 逆矩阵输出
- `m` - 输入矩阵
- `n` - 矩阵维度
- `spd` - 标志：1表示对称正定

**算法说明：**

使用LUP分解和列求解法：

```c
lupdcmp(m, n, p, spd);

for (j = 0; j < n; j++) {
    // 创建第j个单位向量
    for (i = 0; i < n; i++) col[i] = 0.0;
    col[j] = 1.0;
    
    // 求解 m * x = col
    lusolve(m, n, p, col, work, spd);
    
    // 将解复制到逆矩阵的第j列
    for (i = 0; i < n; i++) inv[i][j] = work[i];
}
```

当启用数学加速时，调用LAPACK的 `dgetri`（通用）或 `dpotri`（SPD）。

---

### 矩阵运算

#### matvectmult() - 矩阵向量乘法

```c
void matvectmult(double *vout, double **m, double *vin, int n)
```

计算 vout = m * vin。

```c
for (i = 0; i < n; i++) {
    vout[i] = 0;
    for (j = 0; j < n; j++)
        vout[i] += m[i][j] * vin[j];
}
```

当启用数学加速时，使用 `cblas_dgemv` 或 `dgemv`。

#### diagmatvectmult() - 对角矩阵向量乘法

```c
void diagmatvectmult(double *vout, double *m, double *vin, int n)
```

当m是对角矩阵（存储为1维数组）时，高效计算 vout = m * vin：

```c
for (i = 0; i < n; i++)
    vout[i] = m[i] * vin[i];
```

当启用数学加速时，使用 `cblas_dsbmv` 或 `dsbmv`。

#### matmult() - 矩阵乘法

```c
void matmult(double **c, double **a, double **b, int n)
```

计算 c = a * b，其中a、b、c都是n×n矩阵：

```c
for (i = 0; i < n; i++)
    for (j = 0; j < n; j++) {
        c[i][j] = 0;
        for (k = 0; k < n; k++)
            c[i][j] += a[i][k] * b[k][j];
    }
```

当启用数学加速时，使用 `cblas_dgemm` 或 `dgemm`。

#### diagmatmult() - 对角矩阵乘法

```c
void diagmatmult(double **c, double *a, double **b, int n)
```

计算 c = a * b，其中a是对角矩阵（存储为1维数组）：

```c
for (i = 0; i < n; i++)
    for (j = 0; j < n; j++)
        c[i][j] = a[i] * b[i][j];
```

---

### 向量运算

#### scaleadd_dvector() - 缩放加法

```c
void scaleadd_dvector(double *dst, double *src1, double *src2, int n, double scale)
```

计算 dst = src1 + scale * src2。

当启用数学加速时，使用BLAS的 `dcopy` 和 `daxpy` 优化。

---

### 常微分方程求解

#### rk4_core() - Runge-Kutta 4阶核心

```c
void rk4_core(void *model, double *y, double *k1, void *p, int n, double h, double *yout, slope_fn_ptr f)
```

4阶Runge-Kutta方法的核心计算。根据初始斜率k1，计算步长h后的解。

**参数：**
- `model` - 热模型指针
- `y` - 当前状态向量
- `k1` - 当前斜率（已在外部计算）
- `p` - 额外参数
- `n` - 状态维度
- `h` - 步长
- `yout` - 输出状态向量
- `f` - 斜率函数回调

**算法说明：**

```c
// k2 = slope at midpoint (using k1)
t = y + h/2 * k1
k2 = f(model, t, p)

// k3 = slope at midpoint (using k2)
t = y + h/2 * k2
k3 = f(model, t, p)

// k4 = slope at endpoint (using k3)
t = y + h * k3
k4 = f(model, t, p)

// Combine
yout = y + h * (k1/6 + k2/3 + k3/3 + k4/6)
```

#### rk4() - Runge-Kutta 4阶（自适应步长）

```c
double rk4(void *model, double *y, void *p, int n, double *h, double *yout, slope_fn_ptr f)
```

使用嵌入式误差估计实现自适应步长控制。比较单步结果和两步半步结果来估计误差。

**参数：**
- `model` - 热模型指针
- `y` - 当前状态向量
- `p` - 额外参数
- `n` - 状态维度
- `h` - 步长（输入/输出）
- `yout` - 输出状态向量
- `f` - 斜率函数回调

**返回值：** 建议的下一步步长

**自适应算法：**

```c
#define RK4_SAFETY      0.95
#define RK4_MAXUP       5.0
#define RK4_MAXDOWN     10.0
#define RK4_PRECISION   0.01

// 比较一步和两步半步的结果
rk4_core(model, y, k1, p, n, h, ytemp, f);      // 单步
rk4_core(model, y, k1, p, n, h/2, t1, f);       // 第一半步
f(model, t1, p, k1);                            // 重新计算斜率
rk4_core(model, t1, k1, p, n, h/2, t2, f);      // 第二半步

max_error = max(|ytemp - t2|);

// 精度足够：增大步长
if (max_error <= RK4_PRECISION)
    new_h = SAFETY * h * (PRECISION/max_error)^0.2
    new_h = min(new_h, MAXUP * h)

// 精度不足：减小步长
else
    new_h = SAFETY * h * (PRECISION/max_error)^0.25
    new_h = max(new_h, h/MAXDOWN)
```

---

### SuperLU求解器（当SUPERLU > 0时）

#### build_A_matrix() - 构建系统矩阵

```c
int build_A_matrix(SuperMatrix *G, diagonal_matrix_t *C, double h, SuperMatrix *A)
```

构建Backward Euler格式的系统矩阵 A = (1/h)C + G，其中G是热导矩阵，C是热容矩阵（对角矩阵），h是时间步长。

#### build_B_matrix() - 构建右端向量

```c
int build_B_matrix(diagonal_matrix_t *C, double *T, double *P, double h, SuperMatrix *B)
```

构建右端向量 B = (1/h)CT + P，用于求解 AT = B。

#### backward_euler() - Backward Euler求解器

```c
double backward_euler(SuperMatrix *G, diagonal_matrix_t *C, double *T, double *P, double *h, double *Tout)
```

使用SuperLU库求解热传导方程 GT + CdT = P 的Backward Euler离散形式。

**参数：**
- `G` - 热导矩阵（稀疏矩阵）
- `C` - 热容对角矩阵
- `T` - 当前温度向量
- `P` - 功率向量
- `h` - 时间步长
- `Tout` - 输出温度向量

**返回值：** 建议的下一步步长

**Backward Euler公式：**

```
A = (1/h)C + G
B = (1/h)CT + P
求解 AT = B
```

---

## 算法说明

### LUP分解的数值稳定性

LUP分解通过部分主元选择保证数值稳定性：

1. 在每列中选择绝对值最大的元素作为主元
2. 通过行交换将主元移到对角位置
3. 记录置换向量p以便后续求解

这确保了即使矩阵接近奇异也能得到合理的结果。

### Runge-Kutta 4阶方法

RK4方法通过在区间内多个点估计斜率来达到4阶精度：

- k1：区间起点的斜率
- k2：区间中点的斜率（使用k1）
- k3：区间中点的斜率（使用k2）
- k4：区间终点的斜率（使用k3）

加权组合给出整体4阶精度，局部误差为O(h^5)。

### 自适应步长控制

通过比较单步结果和两步半步结果估计误差：

- 若误差小于阈值，增大步长（最多5倍）
- 若误差大于阈值，减小步长（最多10倍）

这确保在解变化剧烈时使用小步长，在解变化平缓时使用大步长，从而在精度和效率之间取得平衡。

### 数学加速库

HotSpot支持多种硬件优化的数学库：

| 平台 | 宏定义 | BLAS | LAPACK |
|------|--------|------|--------|
| Intel | MA_INTEL | MKL CBLAS | MKL LAPACK |
| AMD | MA_AMD | ACML | ACML |
| Apple | MA_APPLE | vecLib CBLAS | vecLib LAPACK |
| SUN | MA_SUN | sunperf | sunperf |
| 通用 | MA_NONE | 纯C | 纯C |

当这些库可用时，HotSpot自动使用对应的硬件加速函数，显著提升大规模矩阵运算的性能。
