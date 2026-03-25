# package.c / package.h - 封装热模型

## 文件位置

- 头文件: [`src/package.h`](src/package.h)
- 源文件: [`src/package.c`](src/package.c)

## 功能概述

封装模块建模芯片的散热片、热扩散器以及对流边界。该模块计算：

- 扩散器和散热器内部的横向热阻
- 通过封装层的垂直热阻
- 向周围环境的对流散热

封装模型支持两种对流模式：

1. **自然对流**: 依靠热源驱动的空气流动，散热效果较弱
2. **强制对流**: 通过风扇产生的气流散热，散热效果更好

## 核心数据结构

### package_config_t

封装配置结构，定义散热器和风扇的物理参数：

```c
typedef struct package_config_t_st {
    /* 对流模式 - 0: 强制对流, 1: 自然对流 */
    int natural_convec;
    
    /* 气流类型 - 0: 横向气流, 1: 撞击气流 */
    int flow_type;
    
    /* 散热器类型 - 0: 翅片通道散热器, 1: 针翅散热器 */
    int sink_type;
    
    /* 翅片通道散热器参数 */
    double fin_height;      /* 翅片高度 */
    double fin_width;       /* 翅片宽度 */
    double channel_width;   /* 通道宽度 */
    
    /* 针翅散热器参数 */
    double pin_height;      /* 针高度 */
    double pin_diam;        /* 针直径 */
    double pin_dist;        /* 针间距 */
    
    /* 风扇参数 */
    double fan_radius;      /* 风扇半径 */
    double motor_radius;    /* 电机半径 */
    int rpm;                /* 转速 (转/分钟) */
} package_config_t;
```

### convection_t

对流参数结构，存储计算得到的对流特性：

```c
typedef struct convection_t_st {
    double n_fin;           /* 翅片数量 */
    double sur_area_fin;    /* 翅片总表面积 */
    
    double n_pin;           /* 针数量 */
    double sur_area_pin;    /* 针总表面积 */
    
    double reynolds;        /* 雷诺数 */
    double nusselt;         /* 努塞尔数 */
    double h_coeff;        /* 传热系数 */
    double v;              /* 空气流速 */
    double r_th;           /* 等效对流热阻 */
} convection_t;
```

### package_RC_t

封装RC参数结构（在 [`temperature.h`](src/temperature.h) 中定义），存储封装层的热阻热容：

```c
typedef struct package_RC_t_st {
    /* 横向热阻 - 扩散器外围节点 */
    double r_sp1_x;
    double r_sp1_y;
    
    /* 横向热阻 - 散热器内围 */
    double r_hs1_x;
    double r_hs1_y;
    double r_hs2_x;
    double r_hs2_y;
    
    /* 横向热阻 - 散热器外围 */
    double r_hs;
    
    /* 垂直热阻 - 扩散器外围 */
    double r_sp_per_x;
    double r_sp_per_y;
    
    /* 垂直热阻 - 散热器内围 */
    double r_hs_c_per_x;
    double r_hs_c_per_y;
    
    /* 垂直热阻 - 散热器外围 */
    double r_hs_per;
    
    /* 垂直热容 - 扩散器外围 */
    double c_sp_per_x;
    double c_sp_per_y;
    
    /* 垂直热容 - 散热器内围 */
    double c_hs_c_per_x;
    double c_hs_c_per_y;
    
    /* 垂直热容 - 散热器外围 */
    double c_hs_per;
    
    /* 到环境的垂直RC - 散热器内围 */
    double r_amb_c_per_x;
    double c_amb_c_per_x;
    double r_amb_c_per_y;
    double c_amb_c_per_y;
    
    /* 到环境的垂直RC - 散热器外围 */
    double r_amb_per;
    double c_amb_per;
    
    /* 次级路径RC (用于3D封装) */
    double r_sub1_x, r_sub1_y;
    double r_solder1_x, r_solder1_y;
    double r_pcb1_x, r_pcb1_y;
    double r_pcb2_x, r_pcb2_y;
    double r_pcb;
    /* ... 以及对应的垂直RC和热容 ... */
} package_RC_t;
```

## 核心函数

### default_package_config()

```c
package_config_t default_package_config(void);
```

返回默认的封装配置参数：

- 自然对流模式: 0 (强制对流)
- 气流类型: 0 (横向气流)
- 散热器类型: 0 (翅片通道)
- 翅片高度: 0.03 m
- 翅片宽度: 0.001 m
- 通道宽度: 0.002 m
- 风扇半径: 0.03 m
- 电机半径: 0.01 m
- 转速: 1000 RPM

### package_config_add_from_strs()

```c
void package_config_add_from_strs(package_config_t *config, str_pair *table, int size);
```

从字符串对表解析配置参数。支持的参数包括：

- `natural_convec` - 对流模式
- `flow_type` - 气流类型
- `sink_type` - 散热器类型
- `fin_height`, `fin_width`, `channel_width` - 翅片参数
- `pin_height`, `pin_diam`, `pin_dist` - 针翅参数
- `fan_radius`, `motor_radius`, `rpm` - 风扇参数

### package_config_to_strs()

```c
int package_config_to_strs(package_config_t *package_config, str_pair *package_table, int max_entries);
```

将配置转换为字符串对表，返回转换的参数数量（12个）。

### calculate_flow()

```c
void calculate_flow(convection_t *p, package_config_t *config, thermal_config_t *thermal_config);
```

计算强制对流条件下的气流和对流参数。

#### 算法步骤

1. **计算风扇出口体积流速**

```c
dr = sqrt(fan_radius * fan_radius - motor_radius * motor_radius);
a_fan = PI * dr * dr;
vol_v = a_fan * sqrt(0.25 * PI * pow(r_approx, FAN_BETA-1) * 
                      pow(rpm * RPM_TO_RAD, FAN_ALPHA) / a_fan);
```

2. **计算空气流速**

横向气流时：
```c
dh = 2.0 * channel_width * s_sink / (channel_width + s_sink);
v = vol_v / ((n_fin-1) * channel_width * fin_height);  // 翅片通道
v = vol_v / ((sqrt(n_pin)-1) * pin_dist * pin_height); // 针翅
```

撞击气流时：
```c
dh = 2.0 * s_sink / sqrt(PI);
v = vol_v / (s_sink*s_sink - n_pin*PI*(pin_diam*0.5)*(pin_diam*0.5));
```

3. **计算雷诺数**

```c
reynolds = AIR_DSTY * v * dh / AIR_DYNVISC;
```

4. **计算努塞尔数和传热系数**

层流（Re <= 3500）使用解析公式，湍流使用经验公式。

5. **计算等效对流热阻**

```c
r_th = 1.0 / (h_coeff * sur_area);
```

### calc_natural_convec()

```c
void calc_natural_convec(convection_t *p, package_config_t *config, 
                         thermal_config_t *thermal_config, double sink_temp);
```

计算自然对流条件下的对流参数。

#### 算法步骤

1. **计算瑞利数**

```c
rayleigh = GRAVITY * VOL_EXP_COEFF * (sink_temp - ambient) * 
           pow(w, 3.0) * PRANTDL_NUM / (AIR_KINVISC * AIR_KINVISC);
```

2. **计算努塞尔数**

```c
nusselt = pow((576/((rayleigh*w/s_sink)*(rayleigh*w/s_sink)) + 
              2.873/sqrt(rayleigh*w/s_sink)), -0.5);
```

3. **计算热辐射影响**

```c
r_th_rad = (sink_temp - ambient) / 
           (EMISSIVITY * STEFAN * (pow(sink_temp,4.0) - pow(ambient,4.0)) * sur_area);
```

4. **总热阻（对流与辐射并联）**

```c
r_th = r_th * r_th_rad / (r_th + r_th_rad);
```

### package_model()

```c
int package_model(thermal_config_t *thermal_config, str_pair *table, 
                  int size, double sink_temp);
```

初始化并计算封装参数，更新 `thermal_config->r_convec`。

返回值为自然对流标志（1表示自然对流，0表示强制对流）。

#### 执行流程

1. 获取默认配置
2. 读取封装配置文件（如指定）
3. 解析配置参数
4. 根据对流模式调用 `calculate_flow()` 或 `calc_natural_convec()`
5. 更新 `thermal_config->r_convec`

### debug_print_convection()

```c
void debug_print_convection(convection_t *p);
```

打印对流参数用于调试，输出包括：

- 翅片/针数量和表面积
- 雷诺数、努塞尔数
- 传热系数、流速
- 热阻值

## 物理常数

### 空气物性（标准大气压）

| 常数 | 值 | 单位 |
|------|------|------|
| AIR_DSTY | 1.059 | kg/m³ (密度) |
| AIR_SPECHT | 1007 | J/(kg·K) (比热) |
| AIR_COND | 0.028 | W/(m·K) (热导率) |
| AIR_DIFF | 2.6e-5 | m²/s (热扩散率) |
| AIR_DYNVISC | 2.0e-5 | Pa·s (动力粘度) |
| AIR_KINVISC | 1.9e-5 | m²/s (运动粘度) |

### 其他常数

| 常数 | 值 | 说明 |
|------|------|------|
| PRANTDL_NUM | 0.73 | 普朗特数 |
| REY_THRESHOLD | 3500 | 层流/湍流雷诺数阈值 |
| VOL_EXP_COEFF | 3.0e-3 | 体积膨胀系数 (1/K) |
| GRAVITY | 9.8 | 重力加速度 (m/s²) |
| STEFAN | 5.67e-8 | 斯特藩-玻尔兹曼常数 |
| EMISSIVITY | 0.95 | 发射率 |
| R_CONVEC_HIGH | 50.0 | 自然对流热阻上界 (K/W) |
| R_CONVEC_LOW | 0.01 | 强制对流热阻下界 (K/W) |

## 热阻网络

### 主热路径

```
芯片 → 界面层 → 扩散器 → 散热器 → 环境
         ↓          ↓        ↓
      R_interface R_spreader R_sink + R_convec
```

### 封装内部节点

```
扩散器外围节点 (SP_N, SP_S, SP_E, SP_W)
      ↓
散热器内围节点 (SINK_C_N, SINK_C_S, SINK_C_E, SINK_C_W)
      ↓
散热器外围节点 (SINK_N, SINK_S, SINK_E, SINK_W)
      ↓
    环境
```

### 次级热路径（3D封装）

```
芯片边缘 → 封装基板 → 焊球 → PCB内围 → PCB外围 → 环境
```

## 对流模型对比

| 特性 | 自然对流 | 强制对流 |
|------|----------|----------|
| 驱动方式 | 温度差导致密度变化 | 风扇机械驱动 |
| 热阻范围 | 1-50 K/W | 0.01-1 K/W |
| 散热能力 | 较弱 | 较强 |
| 能耗 | 无 | 风扇功耗 |
| 噪声 | 无 | 有 |

## 翅片效率

对于翅片通道散热器，计算翅片效率：

```c
m = sqrt(2 * h_coeff / (k_sink * fin_width)); /* 翅片参数 */
eta = tanh(m * s_sink) / (m * s_sink);         /* 翅片效率 */
```

有效散热面积：
```c
A_eff = channel_width + 2 * eta * s_sink
```

## 配置示例

### 翅片通道散热器 + 强制对流

```
natural_convec		0
flow_type			0
sink_type			0
fin_height			0.03
fin_width			0.001
channel_width		0.002
fan_radius			0.03
motor_radius		0.01
rpm					1000
```

### 针翅散热器 + 自然对流

```
natural_convec		1
flow_type			0
sink_type			1
pin_height			0.02
pin_diam			0.002
pin_dist			0.005
```

## 参考文献

1. P. Tretvstra et al. "Analytical Forced Convection Modeling of Plate-Fin Heat Sinks". IEEE SEMI-THERM, 1999
2. Y. A. Cengel. "Heat and Mass Transfer: A Practical Approach", McGraw-Hill, 2007
3. R. Ribando et al. "Estimating the Convection Coefficient for Flow Through Banks of Fins". U.Va. MAE314 Course Notes, 2007
4. H. A. El-Sheikh et al. "Heat Transfer from Pin-Fin Heat Sinks under Multiple Impinging Jets". IEEE Trans. on Adv. Packaging, 2000
5. F. P. Bleier. "Fan Handbook: Selection, Application and Design". McGraw-Hill, 1998
6. Y. Zhang et al. "SODA: Sensitivity-Based Optimization of Disk Architecture". IEEE/ACM DAC, 2007
