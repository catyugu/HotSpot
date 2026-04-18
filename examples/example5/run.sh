#! /usr/bin/env bash

# Remove files from previous simulations
rm -f *.init
rm -f outputs/*

# Create outputs directory if it doesn't exist
mkdir outputs

# Steady state simulation
../../hotspot -c example.config -p example.ptrace -materials_file example.materials -grid_layer_file example.lcf -model_type grid -detailed_3D on -use_microchannels 1 -grid_steady_file outputs/example.grid.steady -steady_file outputs/example.steady

cp outputs/example.steady example.init

# Transient simulation
../../hotspot -c example.config -p example.ptrace -materials_file example.materials -grid_layer_file example.lcf -init_file example.init -model_type grid -detailed_3D on -use_microchannels 1 -o outputs/example.transient -grid_transient_file outputs/example.grid.ttrace

python ../../scripts/split_grid_steady.py outputs/example.grid.steady 6 64 64
python ../../scripts/grid_thermal_map.py ev6_3D_cache_1.flp outputs/example_layer0.grid.steady 64 64 outputs/layer0.png
python ../../scripts/grid_thermal_map.py ev6_3D_TIM_TSV.flp outputs/example_layer1.grid.steady 64 64 outputs/layer1.png
python ../../scripts/grid_thermal_map.py ev6_3D_cache_2.flp outputs/example_layer2.grid.steady 64 64 outputs/layer2.png
python ../../scripts/grid_thermal_map.py ev6_3D_TIM_TSV.flp outputs/example_layer3.grid.steady 64 64 outputs/layer3.png
python ../../scripts/grid_thermal_map.py ev6_3D_core_layer.flp outputs/example_layer4.grid.steady 64 64 outputs/layer4.png
python ../../scripts/grid_thermal_map.py ev6_3D_TIM.flp outputs/example_layer5.grid.steady 64 64 outputs/layer5.png