# AGENTS.md - HotSpot Thermal Simulator

## Project Overview

HotSpot is a pre-RTL thermal simulator for VLSI design. It supports 2D ICs, 3D ICs, and microfluidic cooling.

**Language**: C (C99 standard)
**Build System**: CMake (note: file is `CMakeLists.txt` - typo in original)
**Backend**: Ninja

---

## Build Commands

### Full Build
```bash
# From project root (uses existing CMakeLists.txt)
cd build
cmake -G Ninja ..
ninja

# Or from source root with existing build dir
cmake -S . -B build -G Ninja
cmake --build build
```

### Build Options
```bash
cmake -DENABLE_DEBUG=ON ..        # Debug build (-O0 -ggdb -Wall -Wextra)
cmake -DENABLE_PROFILE=ON ..      # Profiling build (-O3 -pg -ggdb)
cmake -DUSE_SUPERLU=ON ..         # With SuperLU acceleration
cmake -DVERBOSE_LEVEL=3 ..        # Verbosity (0-3)
```

### Running HotSpot
```bash
# Basic usage (from build directory)
./hotspot.exe -f <floorplan.flp> -p <power.ptrace> -c hotspot.config

# Grid model
./hotspot.exe -f <floorplan.flp> -p <power.ptrace> -model_type grid -grid_layer_file <layer.lcf>

# With output
./hotspot.exe -f <floorplan.flp> -p <power.ptrace> -o <output.ttrace> -c hotspot.config

# Dump config
./hotspot.exe -f <floorplan.flp> -p <power.ptrace> -d <dump.config>
```

### Running hotfloorplan
```bash
./hotfloorplan.exe -f <floorplan.flp>
```

---

## Code Style Guidelines

### File Structure
- Source: `src/*.c` (16 files)
- Headers: `src/*.h` (14 files)
- Headers use include guards: `#ifndef __NAME_H_` / `#define __NAME_H_` / `#endif`
- Header organization: includes at top, then macros, then types, then functions

### Naming Conventions

| Element | Convention | Example |
|---------|------------|---------|
| Struct types | `snake_case_t_st` | `global_config_t_st` |
| Struct members | `snake_case` | `flp_file`, `t_chip` |
| Functions | `snake_case` | `steady_state_temp()`, `compute_temp()` |
| Macros | `UPPER_SNAKE_CASE` | `TEMP_HIGH`, `MAX_UNITS`, `STR_SIZE` |
| Enum values | `UPPER_SNAKE_CASE` | `BLOCK_MODEL`, `GRID_MODEL` |
| Typedefs | `_t` suffix | `str_pair`, `RC_model_t` |

### Type Usage
- `double` for floating-point (temperature, power, coordinates)
- `int` for counts, indices, boolean flags
- `char*` / `char[]` for strings
- Custom allocators: `dvector()`, `dmatrix()`, `ivector()`, `imatrix()`
- Do NOT use `float` - use `double` consistently

### Error Handling
```c
// Fatal errors - prints to stderr and exits with code 1
void fatal(char *s);
void fatal("error message\n");

// Warnings - prints to stderr, continues execution
void warning(char *s);

// Internal assertions (from <assert.h>)
assert(m != NULL);
```

### Memory Allocation
```c
// Pattern: cast, check, use
double *dvector(int n) {
    double *v = (double *)calloc(n, sizeof(double));
    if (!v) fatal("allocation failure in dvector()\n");
    return v;
}

// Always check allocations
m = (double **) calloc(nr, sizeof(double *));
assert(m != NULL);
```

### Control Flow
- Use `if/else` with braces even for single statements
- `while` loops for iteration
- `do { } while()` when loop body must execute at least once

### Comments
```c
/* Multi-line comment for function descriptions */
/* Used for section dividers and detailed explanations */

// Single-line for brief notes
// TODO: comments for incomplete features
// FIXME: comments for known issues
```

### Preprocessor
```c
// Conditional compilation for optional features
#if SUPERLU > 0
    // SuperLU-specific code
#endif

// Compiler-specific handling
#ifdef _MSC_VER
    #define strcasecmp _stricmp
#endif
```

---

## Configuration File Format

Config files use tab-separated `-name value` pairs:
```
-t_chip				0.00015
-ambient			318.15
-model_type			block
```

### String Constants (from util.h)
```c
#define NULLFILE		"(null)"
#define STR_SIZE		512
#define LINE_SIZE		65536
#define MAX_ENTRIES		512
#define TRUE			1
#define FALSE			0
```

---

## Key Source Files

| File | Purpose |
|------|---------|
| `src/hotspot.c` | Main executable - trace-based thermal simulation |
| `src/hotfloorplan.c` | Floorplan utility executable |
| `src/temperature.c` | Core temperature computation (block/grid models) |
| `src/flp.c` | Floorplan parsing and management |
| `src/util.c` | Memory allocation, string tables, math utilities |
| `src/temperature_block.c` | Block-level thermal model |
| `src/temperature_grid.c` | Grid-level thermal model (3D capable) |
| `src/microchannel.c` | Microfluidic cooling support |

---

## Important Constants (temperature.h)

```c
#define TEMP_HIGH	500.0          // Sanity check threshold
#define LEAKAGE_MAX_ITER 100       // Max thermal-leakage iterations
#define LEAK_TOL	0.01           // Convergence criterion
#define MIN_STEP	1e-7           // Minimum time step
```

---

## Function Naming Patterns

| Pattern | Purpose | Example |
|---------|---------|---------|
| `alloc_*` | Constructor | `alloc_RC_model()` |
| `delete_*` | Destructor | `delete_RC_model()` |
| `populate_*` | Initialize internal data | `populate_R_model()` |
| `read_*` / `dump_*` | I/O operations | `read_temp()`, `dump_power()` |
| `default_*` | Get default config | `default_thermal_config()` |
| `*_to_strs` / `*_from_strs` | Config serialization | `thermal_config_to_strs()` |

---

## Testing

**No formal test suite exists.** Verify changes by:
1. Building with `cmake --build build`
2. Running `./hotspot.exe -f <test.flp> -p <test.ptrace>` with known inputs
3. Comparing outputs against reference results

---

## Platform-Specific Notes

- Windows: Uses MSVC compatibility macros in util.c
- CMake finds math library (`-lm`) automatically
- Optional AVX2 vectorization if compiler supports it
- SuperLU dependency is optional (requires BLAS)
