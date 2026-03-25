# materials.c / materials.h - 材料热属性模块

## 文件位置

- 头文件: [`src/materials.h`](src/materials.h)
- 源文件: [`src/materials.c`](src/materials.c)

## 功能概述

材料模块负责管理和查询材料的热物理属性，为热仿真提供必要的参数支持。主要功能包括：

1. 材料属性数据结构管理
2. 材料属性数据库构建
3. 从文件加载自定义材料
4. 材料属性查询接口
5. 内存管理

## 核心数据结构

### material_t - 材料属性结构

```c
typedef struct material_t_st {
    int material_type;                      // 材料类型：SOLID_MATERIAL 或 FLUID_MATERIAL
    double thermal_conductivity;            // 热导率，单位：W/(m*K)
    double volumetric_heat_capacity;         // 体积比热容，单位：J/(m^3*K)
    double dynamic_viscosity;                // 动力粘度，单位：Pa*s（仅流体材料使用）
} material_t;
```

**字段说明：**

| 字段 | 类型 | 说明 |
|------|------|------|
| `material_type` | int | 0 表示固体 (SOLID_MATERIAL)，1 表示流体 (FLUID_MATERIAL) |
| `thermal_conductivity` | double | 热导率，表征材料导热能力 |
| `volumetric_heat_capacity` | double | 体积比热容，表征材料储热能力 |
| `dynamic_viscosity` | double | 动力粘度，仅对流体材料有意义 |

### materials_list_t - 材料数据库结构

```c
typedef struct materials_list_t_st {
    int size;                               // 材料数量
    char **names;                           // 材料名称数组
    material_t *material_properties;         // 材料属性数组
} materials_list_t;
```

## 材料类型常量

```c
#define SOLID_MATERIAL  0   // 固体材料
#define FLUID_MATERIAL  1   // 流体材料
```

### 固体材料

固体材料具有固定的热导率和体积比热容，不需要动力粘度参数。

典型固体材料：

| 材料名称 | 热导率 W/(m*K) | 体积比热容 J/(m^3*K) |
|----------|----------------|---------------------|
| silicon（硅） | 100 | 1.75e6 |
| copper（铜） | 400 | 3.55e6 |
| aluminum（铝） | 237 | 2.43e6 |
| interface（界面材料） | 4 | 4e6 |

### 流体材料

流体材料除了热导率和体积比热容外，还必须指定动力粘度参数。

典型流体材料：

| 材料名称 | 热导率 W/(m*K) | 体积比热容 J/(m^3*K) | 动力粘度 Pa*s |
|----------|----------------|---------------------|---------------|
| water（水） | 0.6 | 4172638 | 0.00065 |

## 核心函数

### default_materials()

```c
void default_materials(materials_list_t *materials_list)
```

初始化空材料列表。此函数创建一个不包含任何预定义材料的空数据库。

**参数：**
- `materials_list`：指向材料列表结构的指针

**实现：**

```c
void default_materials(materials_list_t *materials_list) {
    materials_list->size = 0;
}
```

### materials_add_from_file()

```c
void materials_add_from_file(materials_list_t *materials_list, char *materials_filename)
```

从文件加载材料数据。采用两遍解析策略：

1. **第一遍**：遍历文件统计材料数量
2. **第二遍**：分配内存并填充材料属性

**参数：**
- `materials_list`：指向材料列表结构的指针
- `materials_filename`：材料文件路径

**文件格式：**

```
# 注释行（以 # 开头）
material_name
solid 或 fluid
thermal_conductivity
volumetric_heat_capacity
[dynamic_viscosity]    # 仅流体材料需要
```

**示例文件：**

```
# 硅材料
silicon
solid
100
1750000

# 铜材料
copper
solid
400
3550000

# 水（流体材料）
water
fluid
0.6
4172638
0.00065
```

**解析状态机：**

```c
#define MATERIAL_NAME                      0
#define MATERIAL_TYPE                     1
#define MATERIAL_THERMAL_CONDUCTIVITY     2
#define MATERIAL_VOLUMETRIC_HEAT_CAPACITY 3
#define MATERIAL_DYNAMIC_VISCOSITY         4
```

解析过程中进行以下验证：
- 材料类型必须为 `solid` 或 `fluid`
- 热导率必须非负
- 体积比热容必须非负
- 动力粘度必须非负

### get_material_properties()

```c
material_t get_material_properties(materials_list_t *materials_list, char *name)
```

根据材料名称查询完整材料属性结构。如果未找到指定材料，调用 `fatal()` 终止程序。

**参数：**
- `materials_list`：指向材料列表结构的指针
- `name`：材料名称

**返回值：**
- 对应材料的 `material_t` 结构

**实现：**

```c
material_t get_material_properties(materials_list_t *materials_list, char *name) {
    int i;
    for(i = 0; i < materials_list->size; i++) {
        if(!strncmp(materials_list->names[i], name, STR_SIZE)) {
            return materials_list->material_properties[i];
        }
    }
    fatal("Unable to find material properties for name\n");
}
```

### get_material_thermal_conductivity()

```c
double get_material_thermal_conductivity(materials_list_t *materials_list, char *name)
```

查询材料的热导率。如果未找到返回 -1。

**参数：**
- `materials_list`：指向材料列表结构的指针
- `name`：材料名称

**返回值：**
- 材料的热导率（单位：W/(m*K)），未找到时返回 -1

### get_material_volumetric_heat_capacity()

```c
double get_material_volumetric_heat_capacity(materials_list_t *materials_list, char *name)
```

查询材料的体积比热容。如果未找到返回 -1。

**参数：**
- `materials_list`：指向材料列表结构的指针
- `name`：材料名称

**返回值：**
- 材料的体积比热容（单位：J/(m^3*K)），未找到时返回 -1

### get_material_dynamic_viscosity()

```c
double get_material_dynamic_viscosity(materials_list_t *materials_list, char *name)
```

查询材料的动力粘度。如果未找到返回 -1。

**参数：**
- `materials_list`：指向材料列表结构的指针
- `name`：材料名称

**返回值：**
- 材料的动力粘度（单位：Pa*s），未找到时返回 -1

### free_materials()

```c
void free_materials(materials_list_t *materials_list)
```

释放材料数据库占用的所有内存。

**参数：**
- `materials_list`：指向材料列表结构的指针

**实现：**

```c
void free_materials(materials_list_t *materials_list) {
    int i;
    for(i = 0; i < materials_list->size; i++) {
        free(materials_list->names[i]);
    }
    free(materials_list->names);
    free(materials_list->material_properties);
}
```

## 使用流程

### 基本使用流程

```c
// 1. 创建材料列表
materials_list_t materials_list;
default_materials(&materials_list);

// 2. 从文件加载材料
materials_add_from_file(&materials_list, "materials.db");

// 3. 查询材料属性
double k = get_material_thermal_conductivity(&materials_list, "silicon");
double cp = get_material_volumetric_heat_capacity(&materials_list, "silicon");

// 4. 使用完毕后释放内存
free_materials(&materials_list);
```

### 完整材料属性查询

```c
material_t mat = get_material_properties(&materials_list, "water");
printf("热导率: %f W/(m*K)\n", mat.thermal_conductivity);
printf("体积比热容: %f J/(m^3*K)\n", mat.volumetric_heat_capacity);
printf("动力粘度: %e Pa*s\n", mat.dynamic_viscosity);
printf("材料类型: %s\n", mat.material_type == SOLID_MATERIAL ? "固体" : "流体");
```

## 热物理参数说明

### 热导率 (Thermal Conductivity)

热导率 k 表征材料传导热量的能力，定义为：

```
q = -k * dT/dx
```

其中 q 为热通量，dT/dx 为温度梯度。单位：W/(m*K)

| 材料类型 | 典型热导率范围 |
|----------|----------------|
| 金属 | 10 - 400 W/(m*K) |
| 半导体 | 50 - 150 W/(m*K) |
| 绝缘体 | 0.1 - 1 W/(m*K) |
| 流体 | 0.01 - 1 W/(m*K) |

### 体积比热容 (Volumetric Heat Capacity)

体积比热容 rho*cp 表征材料单位体积升高单位温度所需热量：

```
C = rho * cp
```

其中 rho 为密度，cp 为比热容。单位：J/(m^3*K)

### 动力粘度 (Dynamic Viscosity)

动力粘度 mu 表征流体内摩擦阻力：

```
tau = mu * (dv/dy)
```

其中 tau 为剪切应力，dv/dy 为速度梯度。单位：Pa*s

## 与其他模块的集成

材料模块被以下模块使用：

| 模块 | 用途 |
|------|------|
| temperature_grid.c | 网格模型中查询层材料属性 |
| microchannel.c | 微流控冷却模拟中查询冷却液属性 |
| temperature_block.c | 块模型中查询封装材料属性 |

材料数据通常通过配置文件或材料数据库文件加载，典型配置方式：

```
-materials_file		materials.db
```
