# util.c / util.h - 通用工具模块

## 文件位置

- 头文件: [`src/util.h`](../../src/util.h)
- 源文件: [`src/util.c`](../../src/util.c)

## 功能概述

通用工具模块提供：
1. 内存分配/释放接口（向量、矩阵、三维数组）
2. 字符串表格管理（配置解析）
3. 数学工具（浮点比较、高斯消元、LUP分解）
4. 随机数生成
5. 二进制搜索
6. 文件操作辅助函数

## 头文件重要定义

### 常量

```c
#define DELTA			1.0e-6       // 浮点比较容差
#define LARGENUM		1.0e100      // 大数常量
#define NULLFILE		"(null)"     // 空文件标记

#define TRUE			1            // 布尔真
#define	FALSE			0            // 布尔假

#define RAND_SEED		1500450271    // 随机数种子

#define STR_SIZE		512          // 字符串大小
#define LINE_SIZE		65536        // 行缓冲大小
#define MAX_ENTRIES		512          // 最大条目数
```

### 宏定义

```c
#define MAX(x,y)		(((x)>(y))?(x):(y))
#define MIN(x,y)		(((x)<(y))?(x):(y))
#define MAX3(a,b,c)		MAX(MAX(a,b),c)
#define MIN3(a,b,c)		MIN(MIN(a,b),c)
#define MID3(a,b,c)		((MIN(a,b)<(c))?(MIN(MAX(a,b),c)):(MAX(MIN(a,b),c)))
#define MAX4(a,b,c,d)	MAX(MAX(MAX(a,b),c),d)
#define MIN4(a,b,c,d)	MIN(MIN(MIN(a,b),c),d)
```

## 核心数据结构

### str_pair - 字符串键值对

```c
typedef struct str_pair_st
{
    char name[STR_SIZE];   // 名称
    char value[STR_SIZE]; // 值
} str_pair;
```

用于存储配置文件的 `-name value` 格式数据。

### diagonal_matrix_t - 对角矩阵（SuperLU）

```c
typedef struct diagonal_matrix_t_st
{
    int n;                // 矩阵维度
    double *vals;          // 对角元素值
} diagonal_matrix_t;
```

## 核心函数

### 错误处理

```c
void fatal(char *s);
```

打印错误消息到 stderr 并以退出码 1 终止程序。

```c
void warning(char *s);
```

打印警告消息到 stderr，程序继续执行。

### 浮点数比较（带容差）

```c
int eq(double x, double y);   // x == y (|x-y| < DELTA)
int le(double x, double y);   // x <= y
int ge(double x, double y);   // x >= y
```

使用 DELTA (1.0e-6) 作为容差进行比较，避免浮点精度问题。

```c
// 示例
if (eq(val, 1.0)) {
    // val 接近 1.0
}
```

### 容差取整

```c
int tolerant_ceil(double val);   // 容差上取整
int tolerant_floor(double val);   // 容差下取整
```

对于接近整数的值（如 0.9999999）返回精确整数，避免浮点误差导致的取整错误。

### swap 函数

```c
void swap_ival(int *a, int *b);     // 交换两个整数
void swap_dval(double *a, double *b); // 交换两个双精度浮点
```

### 内存分配 - 向量

```c
double *dvector(int n);              // 分配 double 向量
void free_dvector(double *v);        // 释放 double 向量
void dump_dvector(double *v, int n); // 打印向量元素
void copy_dvector(double *dst, double *src, int n); // 复制向量
void zero_dvector(double *v, int n); // 置零向量
double sum_dvector(double *v, int n); // 求和

int *ivector(int n);                 // 分配 int 向量
void free_ivector(int *v);           // 释放 int 向量
```

```c
// 示例
double *vec = dvector(100);
zero_dvector(vec, 100);
vec[0] = 1.0;
vec[1] = 2.0;
double total = sum_dvector(vec, 100);
free_dvector(vec);
```

### 内存分配 - 矩阵

```c
double **dmatrix(int nr, int nc);        // 分配 double 矩阵
void free_dmatrix(double **m);            // 释放 double 矩阵
void dump_dmatrix(double **m, int nr, int nc); // 打印矩阵
void copy_dmatrix(double **dst, double **src, int nr, int nc); // 复制
void zero_dmatrix(double **m, int nr, int nc); // 置零
void resize_dmatrix(double **m, int nr, int nc); // 调整维度
void mirror_dmatrix(double **m, int n);   // 下三角镜像到上三角

int **imatrix(int nr, int nc);           // 分配 int 矩阵
void free_imatrix(int **m);               // 释放 int 矩阵
```

```c
// 示例
double **A = dmatrix(10, 10);
zero_dmatrix(A, 10, 10);
A[0][0] = 1.0;
A[0][1] = 0.5;
// 对称化
mirror_dmatrix(A, 10);
free_dmatrix(A);
```

### 内存分配 - 三维数组

```c
double ***dcuboid_tail(int nr, int nc, int nl, int xtra);
void free_dcuboid(double ***m);
```

分配带尾部扩展的三维数组：
- `nr`: 行数
- `nc`: 列数
- `nl`: 层数
- `xtra`: 尾部额外元素数

内存布局：连续分配 `nl * nr * nc + xtra` 个 double 值。

```c
// 示例：分配温度网格 (10x10x5) + 额外10个元素
double ***temp = dcuboid_tail(10, 10, 5, 10);
temp[0][0][0] = 300.0; // 第一层第一行第一列
temp[4][9][9] = 350.0; // 最后一层最后一行最后一列
free_dcuboid(temp);
```

### 字符串表格函数

```c
int read_str_pairs(str_pair *table, int max_entries, char *file);
```

从文件读取制表符分隔的键值对。忽略空行和 `#` 注释行。

```c
// 配置文件格式
-t_chip				0.00015
-ambient			318.15
-model_type			block
```

```c
int parse_cmdline(str_pair *table, int max_entries, int argc, char **argv);
```

从命令行解析键值对，格式：`-name value -name2 value2`。

```c
void dump_str_pairs(str_pair *table, int size, char *file, char *prefix);
```

将表格写入文件，每行格式：`prefix+name+value`。

```c
int get_str_index(str_pair *table, int size, char *str);
```

在表格中查找名称，返回索引或 -1（未找到）。

```c
int str_pairs_remove_duplicates(str_pair *table, int size);
```

移除重复名称，保留首次出现的条目，返回新大小。

```c
// 示例
str_pair config[MAX_ENTRIES];
int n = read_str_pairs(config, MAX_ENTRIES, "hotspot.config");
n = str_pairs_remove_duplicates(config, n);
int idx = get_str_index(config, n, "t_chip");
if (idx >= 0) {
    double t_chip = atof(config[idx].value);
}
```

### 二进制搜索

```c
int bsearch_double(double *arr, int n, double ele, double **loc);
```

在有序 double 数组中查找元素：
- 找到：返回 TRUE，`*loc` 指向该元素
- 未找到：返回 FALSE，`*loc` 指向应插入位置

```c
int bsearch_insert_double(double *arr, int n, double ele);
```

查找并插入（如果不存在）。返回 FALSE 表示已存在，TRUE 表示新插入。

```c
// 示例
double sorted[] = {1.0, 2.0, 3.0, 4.0, 5.0};
double *loc;
if (bsearch_double(sorted, 5, 3.0, &loc)) {
    // 找到
} else {
    // 未找到，应插入位置：sorted + (loc - sorted)
}
```

### 随机数生成

```c
void init_rand(void);              // 初始化随机数生成器
int rand_upto(int max);           // [0, max-1] 范围内的随机整数
double rand_fraction(void);       // [0, 1) 范围内的随机浮点数
```

使用 `RAND_SEED` 初始化，确保可重复性。

```c
// 示例
init_rand();
int dice = rand_upto(6) + 1;     // 1-6 的骰子
double prob = rand_fraction();    // 0.0 到 1.0 之间
```

### 数组操作

```c
int contains(int *array, int size, int value);
```

检查数组是否包含指定值，返回索引或 -1。

```c
unsigned int ones8(register unsigned char n);
```

计算 8 位整数的置位数（population count）。

```c
int count_significant_lines(FILE *fp);
```

统计文件中非空、非注释的行数。

### 矩阵运算

```c
int coo2csc(int size, int nnz,
            int *cooX, int *cooY, double *cooV,
            int *cscRowInd, int *cscColPtr, double *cscV);
```

COO（坐标）格式转换为 CSC（压缩稀疏列）格式。

```c
int c2c_cmp(const void *a, const void *b);
```

COO 元素比较函数（按 y 坐标、然后 x 坐标排序）。

### 高斯消元

```c
void gaussj(double **a, int n, double *b);
```

Gauss-Jordan 消元法求解线性方程组 Ax = b：
- `a`: n x n 系数矩阵（被修改为逆矩阵）
- `b`: 右端向量（被修改为解向量）

```c
// 示例：求解 Ax = b
double **A = dmatrix(3, 3);
double *b = dvector(3);

// 填充 A 和 b
A[0][0] = 2; A[0][1] = 1; A[0][2] = -1; b[0] = 8;
A[1][0] = -3; A[1][1] = -1; A[1][2] = 2; b[1] = -11;
A[2][0] = -1; A[2][1] = 1; A[2][2] = 1; b[2] = -3;

gaussj(A, 3, b);
// b 现在是解向量 [3, -1, 2]

free_dmatrix(A);
free_dvector(b);
```

## SuperLU 扩展函数

当 `SUPERLU > 0` 时可用：

```c
int diagonal_add_SparseMatrix(double c, diagonal_matrix_t *diag, SuperMatrix *A);
// 计算 A = c*diag + A

int diagonal_mul_vector(double c, diagonal_matrix_t *diag, double **vector);
// 计算 vector = c*diag*vector

int vector_add_vector(int n, double c1, double *vector1, double c2, double *vector2);
// 计算 vector2 = c1*vector1 + c2*vector2

int SparseMatrix_mul_vector(SuperMatrix *A, double *vector);
// 计算 vector = A*vector

void cooTocsv(char *filename, int size, int nnz, int *cooX, int *cooY, double *cooV);
void diagTocsv(char *filename, diagonal_matrix_t *diag);
void vectorTocsv(char *filename, int size, double *vector);
```

## 内存分配模式

HotSpot 使用自定义内存分配器而非标准库版本：

| 函数 | 标准库对应 | 说明 |
|------|-----------|------|
| `dvector()` | `calloc(n, sizeof(double))` | 分配并清零 |
| `dmatrix()` | 分层 `calloc` | 行指针 + 连续数据 |
| `dcuboid_tail()` | 三层指针 | 三维数组 + 尾部扩展 |

分配后使用 `fatal()` 处理分配失败，确保安全。

## 代码示例

### 完整的配置解析流程

```c
#include "util.h"

int main(int argc, char **argv) {
    str_pair config[MAX_ENTRIES];
    int n;
    
    // 从文件读取配置
    n = read_str_pairs(config, MAX_ENTRIES, "hotspot.config");
    
    // 从命令行覆盖
    n = parse_cmdline(config + n, MAX_ENTRIES - n, argc, argv);
    
    // 移除重复项
    n = str_pairs_remove_duplicates(config, n);
    
    // 查找参数
    int idx;
    double t_chip = 0.00015; // 默认值
    if ((idx = get_str_index(config, n, "t_chip")) >= 0) {
        t_chip = atof(config[idx].value);
    }
    
    double ambient = 318.15;
    if ((idx = get_str_index(config, n, "ambient")) >= 0) {
        ambient = atof(config[idx].value);
    }
    
    printf("t_chip=%e, ambient=%e\n", t_chip, ambient);
    return 0;
}
```

### 矩阵运算示例

```c
// 创建并初始化矩阵
double **A = dmatrix(4, 4);
zero_dmatrix(A, 4, 4);

// 填充稀疏矩阵（非零元素）
A[0][0] = 4;  A[0][1] = 1;
A[1][0] = 1;  A[1][1] = 3;  A[1][2] = 1;
A[2][1] = 1;  A[2][2] = 3;  A[2][3] = 1;
A[3][1] = 1;  A[3][3] = 4;

// 镜像使对称（如果需要）
mirror_dmatrix(A, 4);

// 复制矩阵
double **B = dmatrix(4, 4);
copy_dmatrix(B, A, 4, 4);

free_dmatrix(A);
free_dmatrix(B);
```

### 三维温度数组

```c
// 分配 5x5x3 的温度网格，带 10 元素尾部
double ***temp = dcuboid_tail(5, 5, 3, 10);

// 初始化
int i, j, k;
for (i = 0; i < 3; i++)
    for (j = 0; j < 5; j++)
        for (k = 0; k < 5; k++)
            temp[i][j][k] = 300.0; // 初始温度

// 使用
temp[0][0][0] = 350.0; // 热源

// 释放
free_dcuboid(temp);
```
