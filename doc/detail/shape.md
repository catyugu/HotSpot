# shape.c / shape.h - 形状曲线模块

## 文件位置

- 头文件: [`src/shape.h`](../../src/shape.h)
- 源文件: [`src/shape.c`](../../src/shape.c)

## 功能概述

形状曲线（shape curve）模块负责：

1. 生成表示固定面积块所有可能（宽度，高度）组合的形状曲线
2. 形状曲线的分段线性运算（水平/垂直堆叠）
3. 切片树（slicing tree）的构建与管理
4. 将切片树转换为实际布局
5. 形状曲线调试输出

形状曲线是floorplanning中的核心数据结构，它允许在给定的面积约束下探索不同的长宽比组合。

## 核心数据结构

### shape_t - 分段线性形状曲线

```c
typedef struct shape_t_st {
    double *x;           // 宽度数组
    double *y;           // 高度数组
    
    // 如果这不是布局中的叶子节点，
    // 则记录方向在贡献形状曲线中的位置
    int *left_pos;       // 左子形状曲线位置
    int *right_pos;      // 右子形状曲线位置
    
    double *median;      // 分割线位置
    int size;            // 曲线点数
} shape_t;
```

### tree_node_t - 切片树节点

```c
typedef struct tree_node_t_st {
    shape_t *curve;           // 形状曲线
    
    union {
        int cut_type;        // 切割类型（CUT_VERTICAL / CUT_HORIZONTAL）
        int unit;            // 单元索引（叶子节点）
    } label;
    
    struct tree_node_t_st *left;   // 左子节点
    struct tree_node_t_st *right;  // 右子节点
} tree_node_t;
```

### tree_node_stack_t - 树节点栈

```c
typedef struct tree_node_stack_t_st {
    tree_node_t *array[MAX_STACK];  // 节点数组
    int top;                         // 栈顶指针
} tree_node_stack_t;
```

### 切割类型常量

```c
#define CUT_NONE        -1
#define CUT_VERTICAL    -2   // 垂直切割（左右并排）
#define CUT_HORIZONTAL  -3   // 水平切割（上下堆叠）
```

## 核心函数

### 形状曲线创建与销毁

#### shape_from_aspect()

```c
shape_t *shape_from_aspect(double area, double min, 
                           double max, int rotable,
                           int n_orients);
```

根据面积和长宽比范围生成形状曲线。

**参数：**
- `area`: 块面积（平方米）
- `min`: 最小长宽比
- `max`: 最大长宽比
- `rotable`: 是否可旋转（可旋转时生成2n个方向）
- `n_orients`: 方向数（必须是大于1的偶数）

**算法：**
```c
// 如果不可旋转或存在重叠区域
if (!rotable || overlap) {
    minx = sqrt(area * min);
    maxx = sqrt(area * max);
    r = pow((maxx / minx), 1.0/(n-1));
    for (i = 0; i < n; i++) {
        shape->x[i] = minx * pow(r, i);
        shape->y[i] = area / shape->x[i];
    }
}
```

**示例：** 面积=1e-4 m²，长宽比范围=[0.5, 2.0]，n=3
```
点1: width=0.0100, height=0.0100  (正方形, ar=1.0)
点2: width=0.0071, height=0.0141  (ar=0.5)
点3: width=0.0141, height=0.0071  (ar=2.0)
```

#### free_shape()

```c
void free_shape(shape_t *shape);
```

释放形状曲线所有内存，包括x、y数组和位置数组。

#### shape_duplicate()

```c
shape_t *shape_duplicate(shape_t *shape);
```

复制形状曲线，用于创建备份。

---

### 形状曲线运算

#### shape_add()

```c
shape_t *shape_add(shape_t *shape1, shape_t *shape2, int cut_type);
```

将两个形状曲线堆叠组合。

**垂直切割（CUT_VERTICAL）** - 左右并排：
```
width = w1 + w2
height = max(h1, h2)
```

**水平切割（CUT_HORIZONTAL）** - 上下堆叠：
```
width = max(w1, w2)
height = h1 + h2
```

**实现要点：**
- 使用类似归并排序的算法遍历两个曲线
- 记录每个结果点在原始曲线中的位置（left_pos, right_pos）
- 结果曲线大小由遍历次数决定

```c
// 垂直切割示例
if (cut_type == CUT_VERTICAL) {
    sum->x[k] = shape1->x[i] + shape2->x[j];
    sum->y[k] = MAX(shape1->y[i], shape2->y[j]);
    sum->left_pos[k] = i;
    sum->right_pos[k] = j;
    if (shape1->y[i] >= shape2->y[j])
        i++;
    else
        j++;
}
```

#### min_area_pos()

```c
int min_area_pos(shape_t *curve);
```

找到形状曲线上面积最小的点位置。用于在tree_to_flp中选择最优布局。

```c
int min_area_pos(shape_t *curve) {
    int i, pos = 0;
    double min = curve->x[0] * curve->y[0];
    for (i = 1; i < curve->size; i++)
        if (min > curve->x[i] * curve->y[i]) {
            min = curve->x[i] * curve->y[i];
            pos = i;
        }
    return pos;
}
```

---

### 栈操作

```c
// 创建栈
tree_node_stack_t *new_tree_node_stack(void);

// 压栈
void tree_node_stack_push(tree_node_stack_t *stack, tree_node_t *node);

// 弹栈
tree_node_t *tree_node_stack_pop(tree_node_stack_t *stack);

// 栈状态检查
int tree_node_stack_isfull(tree_node_stack_t *stack);
int tree_node_stack_isempty(tree_node_stack_t *stack);

// 清空和释放
void tree_node_stack_clear(tree_node_stack_t *stack);
void free_tree_node_stack(tree_node_stack_t *stack);
```

---

### 切片树操作

#### tree_from_NPE()

```c
tree_node_t *tree_from_NPE(flp_desc_t *flp_desc,
                          tree_node_stack_t *stack,
                          NPE_t *expr);
```

从归一化波兰表达式（NPE）构建切片树。

**算法：**
```c
for (i = 0; i < expr->size; i++) {
    node = (tree_node_t *) calloc(1, sizeof(tree_node_t));
    
    // 叶子节点 - 复制单元的形状曲线
    if (expr->elements[i] >= 0) {
        node->curve = shape_duplicate(flp_desc->units[expr->elements[i]].shape);
        node->left = node->right = NULL;
        node->label.unit = expr->elements[i];
    }
    // 内部节点 - 切割操作
    else {
        right = tree_node_stack_pop(stack);
        left = tree_node_stack_pop(stack);
        node->curve = shape_add(left->curve, right->curve, expr->elements[i]);
        node->left = left;
        node->right = right;
        node->label.cut_type = expr->elements[i];
    }
    tree_node_stack_push(stack, node);
}
```

#### tree_to_flp()

```c
int tree_to_flp(tree_node_t *root, flp_t *flp, int compact_dead,
               double compact_ratio);
```

将切片树转换为实际布局。

**流程：**
1. 找到面积最小的形状曲线位置
2. 调用`recursive_sizing()`递归计算每个单元的尺寸和位置
3. 处理死块（dead block）的压缩

**返回：** 被压缩的死块数量

#### recursive_sizing()

```c
int recursive_sizing(tree_node_t *node, int pos,
                    double leftx, double bottomy,
                    int dead_count, int compact_dead,
                    double compact_ratio,
                    flp_t *flp);
```

递归计算布局中每个单元的实际位置和尺寸。

**叶子节点处理：**
```c
if (node->label.unit >= 0) {
    flp->units[node->label.unit].width = self->x[pos];
    flp->units[node->label.unit].height = self->y[pos];
    flp->units[node->label.unit].leftx = leftx;
    flp->units[node->label.unit].bottomy = bottomy;
}
```

**内部节点处理：**
```c
// 获取左右子形状曲线
shape_t *left = node->left->curve;
shape_t *right = node->right->curve;

// 添加死块
if (node->label.cut_type == CUT_VERTICAL) {
    // 左右并排，添加垂直方向死块
    flp->units[idx].width = (y2 >= y1) ? x1 : x2;
    flp->units[idx].height = fabs(y2 - y1);
    // 递归处理左右子节点
    dead_count = recursive_sizing(node->left, self->left_pos[pos],
                                  leftx, bottomy, ...);
    dead_count = recursive_sizing(node->right, self->right_pos[pos],
                                  leftx + self->median[pos], bottomy, ...);
}
```

#### free_tree()

```c
void free_tree(tree_node_t *root);
```

递归释放树的所有节点和形状曲线内存。

---

### 调试输出

```c
// 打印单个形状曲线
void print_shape(shape_t *shape);

// 打印形状曲线条目
void print_shape_entry(shape_t *shape, int i);

// 打印整个树
void print_tree(tree_node_t *root, flp_desc_t *flp_desc);

// 打印树中与特定位置相关的形状曲线
void print_tree_relevant(tree_node_t *root, int pos, flp_desc_t *flp_desc);
```

## 形状曲线说明

### 概念解释

形状曲线表示在固定面积约束下，一个块所有可能的宽度和高度组合。曲线上每个点(w, h)满足：

```
w * h = area（固定）
min_aspect <= h/w <= max_aspect
```

### 几何意义

形状曲线在宽度-高度坐标系中是一条双曲线（等面积线）。由于我们使用分段线性近似，实际存储的是曲线上的一组采样点。

```
height
  ^
  |    * (w1, h1)  ar = h1/w1
  |   *
  |  *  (w2, h2)  ar = h2/w2 (最大)
  | *
  |*
  +------------------------> width
```

### 组合运算示例

**原始形状曲线：**

块A（面积=1e-4 m², ar=[0.5, 2.0]）:
```
点: width=0.0100, height=0.0100
    width=0.0071, height=0.0141
    width=0.0141, height=0.0071
```

块B（面积=2e-4 m², ar=[0.5, 2.0]）:
```
点: width=0.0141, height=0.0141
    width=0.0100, height=0.0200
    width=0.0200, height=0.0100
```

**水平切割（左右并排）：**

```
结果宽度 = wA + wB
结果高度 = max(hA, hB)

示例组合（各取第一个点）:
width = 0.0100 + 0.0141 = 0.0241
height = max(0.0100, 0.0141) = 0.0141
面积 = 0.0241 * 0.0141 = 3.4e-4 m² (应为3e-4)
```

**垂直切割（上下堆叠）：**

```
结果宽度 = max(wA, wB)
结果高度 = hA + hB

示例组合（各取第一个点）:
width = max(0.0100, 0.0141) = 0.0141
height = 0.0100 + 0.0141 = 0.0241
```

### 与NPE的关系

NPE（归一化波兰表达式）是切片树的线性表示。树到NPE的转换和NPE到树的转换实现了布局的序列化和反序列化。

```
树结构:                    NPE表达式:
       *                       1 2 + *
      / \
     1   *                   (1, 2是两个叶子，+是切割)
        / \
       2   3
```

### 死块处理

在切片树中，死块（dead block）是填充切割缝隙的空白区域。`compact_ratio`参数控制何时忽略小型死块：

```c
if (compact_dead && fabs(y2-y1) / MIN(y1, y2) <= compact_ratio) {
    // 死块太小，合并到相邻块
    if (y2 >= y1)
        left->y[self->left_pos[pos]] = y2;
    else
        right->y[self->right_pos[pos]] = y1;
} else {
    // 保留死块作为独立单元
    dead_count++;
}
```

## 内存分配模式

```c
// 形状曲线分配
shape = (shape_t *) calloc(1, sizeof(shape_t));
shape->x = (double *) calloc(size, sizeof(double));
shape->y = (double *) calloc(size, sizeof(double));

// 树节点分配
node = (tree_node_t *) calloc(1, sizeof(tree_node_t));

// 栈分配
stack = (tree_node_stack_t *) calloc(1, sizeof(tree_node_stack_t));
```

所有分配失败都调用`fatal()`终止程序。
