# npe.c / npe.h - 归一化波兰表达式模块

## 文件位置

- 头文件: [`src/npe.h`](../../src/npe.h)
- 源文件: [`src/npe.c`](../../src/npe.c)

## 功能概述

归一化波兰表达式（Normalized Polish Expression，NPE）模块实现：
1. 切片式布局（slicing floorplan）的波兰表达式表示
2. NPE与布局树之间的相互转换
3. 模拟退火优化过程中的随机移动操作
4. NPE的归一化约束维护

NPE用于布局优化器（模拟退火算法）中，在退火过程中通过随机移动修改NPE，并评估生成的布局代价。

## 核心数据结构

### NPE_t - 归一化波兰表达式结构

```c
typedef struct NPE_t_st {
    int *elements;      // 表达式数组（算子/操作数编码）
    int size;           // 表达式长度 = 2 * n_units - 1

    /* 单元位置数组 */
    int *unit_pos;
    int n_units;

    /* 翻转位置数组 - 算子与单元相邻的位置 */
    int *flip_pos;
    int n_flips;

    /* 链位置数组 */
    int *chain_pos;
    int n_chains;

    /* 每个位置的投票计数 */
    int *ballot_count;
} NPE_t;
```

### 表达式元素编码

```c
// 切割类型（算子）
#define CUT_NONE        -1  // 无切割
#define CUT_VERTICAL    -2  // 垂直切割 (V)
#define CUT_HORIZONTAL  -3  // 水平切割 (H)

// 操作数为非负整数（单元索引）
```

### 切割类型常量

| 常量 | 值 | 含义 |
|------|-----|------|
| `CUT_NONE` | -1 | 无切割 |
| `CUT_VERTICAL` | -2 | 垂直切割，将布局左右分割 |
| `CUT_HORIZONTAL` | -3 | 水平切割，将布局上下分割 |

## 核心函数

### NPE_get_initial()

```c
NPE_t *NPE_get_initial(flp_desc_t *flp_desc)
```

创建模拟退火的初始NPE解。

初始解的构造规律：
```c
// 对于 n 个单元的布局
// 表达式: 0, V, 1, V, 2, V, ..., n-2, V, n-1
// 即: 单元0, 垂直切割, 单元1, 垂直切割, 单元2, ...
```

例如4个单元的初始NPE：
```
位置:    0   1   2   3   4   5   6
元素:   0   V   1   V   2   V   3
```

### free_NPE()

```c
void free_NPE(NPE_t *expr)
```

释放NPE的所有内存，包括：
- `elements` 数组
- `unit_pos` 数组
- `flip_pos` 数组
- `chain_pos` 数组
- `ballot_count` 数组
- NPE结构体本身

### print_NPE()

```c
void print_NPE(NPE_t *expr, flp_desc_t *flp_desc)
```

调试打印函数，输出NPE的完整信息：
- 表达式内容（将编码转换为可读格式）
- 单元位置数组
- 翻转位置数组
- 链位置数组
- 投票计数数组

示例输出：
```
printing normalized polish expression of size 7
alu1, V, alu2, H, cache, H, regfile
unit_pos:
0   2   4   6
flip_pos:
1   3   5
chain_pos:
1   3
ballot_count:
0   1   1   2   2   3   3
```

### NPE_swap_units() - M1移动

```c
void NPE_swap_units(NPE_t *expr, int pos)
```

交换NPE中两个相邻单元的位置（M1移动）。

工作原理：
1. 从给定位置 `pos` 开始查找下一个单元（索引递增）
2. 交换 `pos` 处的元素与找到的单元元素

```c
// 示例：交换位置0和位置2的单元
// 交换前: 0   V   1   V   2
// 交换后: 1   V   0   V   2
```

此移动改变了单元的物理顺序，但不改变切割结构。

### NPE_invert_chain() - M2移动

```c
void NPE_invert_chain(NPE_t *expr, int pos)
```

反转一条链中所有切割的类型（M2移动）。

工作原理：
1. 从位置 `pos` 开始，将切割类型反转（V变为H，H变为V）
2. 继续向后遍历同一链中的连续切割
3. 确保链中相邻切割类型不同（归一化约束）

```c
// 示例：反转位置1处的链
// 反转前: 1   V   H   V
// 反转后: 1   H   V   H
```

此移动改变了子布局的切割结构，保持布局的切片性质。

### NPE_swap_cut_unit() - M3移动

```c
int NPE_swap_cut_unit(NPE_t *expr, int pos)
```

交换相邻的切割和单元位置（M3移动）。

有两种情况：
1. **单元-切割交换**：`pos` 处是单元
2. **切割-单元交换**：`pos` 处是切割

合法性检查：
- 交换后不能产生相同类型的连续切割
- 不能违反投票约束（balloting property）

```c
// 单元-切割交换示例
// 交换前: ... 单元   V   单元 ...
// 交换后: ... V   单元   单元 ...

// 切割-单元交换示例
// 交换前: ... V   单元   H ...
// 交换后: ... 单元   V   H ...
```

### make_random_move()

```c
NPE_t *make_random_move(NPE_t *expr)
```

创建随机移动的核心函数。从三种移动类型中随机选择：

| 移动 | 类型 | 操作 |
|------|------|------|
| M1 | 0 | 交换相邻单元 |
| M2 | 1 | 反转切割链 |
| M3 | 2 | 交换切割与单元 |

实现细节：
```c
NPE_t *make_random_move(NPE_t *expr)
{
    move = rand_upto(3);  // 随机选择0-2
    switch(move) {
        case 0: NPE_swap_units(expr, unit_pos[i]); break;
        case 1: NPE_invert_chain(expr, chain_pos[i]); break;
        case 2: NPE_swap_cut_unit(expr, flip_pos[i]); break;
    }
}
```

M3移动可能产生非法操作，因此最多尝试 `MAX_MOVES` 次直到成功或放弃。

### NPE_duplicate()

```c
NPE_t *NPE_duplicate(NPE_t *expr)
```

深拷贝NPE结构。分配新内存并复制所有数组：
- `elements` 数组
- `unit_pos` 数组
- `flip_pos` 数组
- `chain_pos` 数组
- `ballot_count` 数组

返回新创建的副本，用于在尝试移动前保存当前状态。

## 辅助函数

### fill_unit_pos()

```c
void fill_unit_pos(NPE_t *expr)
```

扫描表达式，填充 `unit_pos` 数组（所有单元的位置）。

```c
// elements[i] >= 0 表示单元
for (i=0; i < expr->size; i++)
    if (expr->elements[i] >= 0)
        expr->unit_pos[j++] = i;
```

### fill_flip_pos()

```c
void fill_flip_pos(NPE_t *expr)
```

填充 `flip_pos` 数组（算子与单元相邻的位置）。

```c
// 相邻元素类型不同（一个 >= 0，一个 < 0）
if ((elements[i] < 0 && elements[i+1] >= 0) ||
    (elements[i] >= 0 && elements[i+1] < 0))
    flip_pos[j++] = i;
```

这些位置是M3移动的候选位置。

### fill_chain_pos()

```c
void fill_chain_pos(NPE_t *expr)
```

填充 `chain_pos` 数组（连续切割链的起始位置）。

```c
// 扫描负值元素（切割）
while (i < expr->size) {
    if (expr->elements[i] < 0) {
        chain_pos[j++] = i;  // 链的起始位置
        // 跳过同一链中的所有切割
        while(i < expr->size && expr->elements[i] < 0)
            i++;
    } else
        i++;
}
```

### fill_ballot_count()

```c
void fill_ballot_count(NPE_t *expr)
```

计算并填充 `ballot_count` 数组（每个位置的投票计数）。

投票计数表示该位置之前（包括该位置）的切割数量。

```c
ballot_count = 0;
for (i=0; i < expr->size; i++) {
    if (expr->elements[i] < 0)
        ballot_count++;
    expr->ballot_count[i] = ballot_count;
}
```

此数组用于验证M3移动是否违反归一化约束。

### update_unit_pos()

```c
int update_unit_pos(NPE_t *expr, int pos, int delta, int start, int end)
```

二分查找并更新指定单元的位置偏移量（通过二分查找 `unit_pos` 数组）。

## NPE算法说明

### 切片式布局

切片式布局（slicing floorplan）是一种特殊的布局结构，可以通过递归的水平或垂直切割分成两个子布局。

```
布局示例:

+-----------+-----------+
|           |           |
|    A      |     B     |
|           |           |
+-----------+    +-------+
|           |    |       |
|    C      |    D      |
|           |    |       |
+-----------+----+-------+

切割结构:
        V
      /   \
     A     H
          / \
         C   D
```

### 波兰表达式

波兰表达式是前缀表示法，算子放在操作数之前。

对于上述布局：
- 垂直切割 V 表示左右分割
- 水平切割 H 表示上下分割
- 单元为叶子节点

波兰表达式: `V A H C D`

### 归一化约束

归一化要求：没有任何操作数（单元）同时被 H 和 V 两种切割在其子树中包围。

即：任何单元的子树中，不能同时包含 H 和 V 两种类型的切割。

这确保了每个单元在表达式中有唯一的位置表示。

### 投票约束（Balloting Property）

投票约束确保归一化性质：

```
2 * ballot_count[pos] < pos + 1
```

在任意位置 i，之前的切割数量必须少于该位置之前（包括该位置）的元素总数的一半。

### 模拟退火集成

在布局优化过程中，NPE用于表示当前布局配置：

```c
// 退火主循环
while (T >= Tcold) {
    for (i=0; i < moves_per_step; i++) {
        // 生成随机移动（修改NPE）
        NPE_t *new_npe = make_random_move(current_npe);
        
        // 从NPE重建布局树
        tree_node_t *tree = tree_from_NPE(new_npe);
        
        // 评估布局代价
        new_cost = evaluate_floorplan(tree);
        
        // Metropolis准则
        if (new_cost < cost || rand() < exp(-(new_cost-cost)/T)) {
            current_npe = new_npe;
            cost = new_cost;
        }
    }
    T *= Rcool;  // 冷却
}
```

## 内存布局

NPE结构的内存分配：

```
NPE_t
├── elements     [size]         int
├── unit_pos     [n_units]      int
├── flip_pos     [size]         int
├── chain_pos    [n_units-1]    int
└── ballot_count [size]         int
```

典型内存占用（假设 n_units = 100）：
- size = 2*100 - 1 = 199
- elements: 199 * 4 = 796 字节
- unit_pos: 100 * 4 = 400 字节
- flip_pos: 199 * 4 = 796 字节
- chain_pos: 99 * 4 = 396 字节
- ballot_count: 199 * 4 = 796 字节
- 总计: 约 3.2 KB

## 错误处理

所有内存分配失败时调用 `fatal()` 终止程序：

```c
if (!expr->elements || !expr->unit_pos || ...)
    fatal("memory allocation error\n");
```

归一化约束违反时也调用 `fatal()`：

```c
if (expr->elements[i] == prev)
    fatal("NPE not normalized\n");
```
