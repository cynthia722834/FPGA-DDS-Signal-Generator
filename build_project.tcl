#====================================================================
# build_project.tcl — 创建 Vivado 工程: 综合 → 实现 → 生成比特流
# 用法: vivado -mode batch -source D:/FPGA_DDS/build_project.tcl
# 注意: 器件型号需按板子实际封装修改 (见下方 set part)
#====================================================================
set proj_dir D:/FPGA_DDS/vivado_proj
set part xc7a35tftg256-2

# 若工程已存在则删除重建
file delete -force $proj_dir
create_project dds_signal_gen $proj_dir -part $part -force

# 添加源文件
add_files -fileset sources_1 [glob D:/FPGA_DDS/src/*.v]
# 正弦表初始化文件(供 $readmemh 使用): 加入工程 + 复制到工程根目录双保险
add_files -fileset sources_1 D:/FPGA_DDS/mem/sine_rom_4096x8.mem
file copy -force D:/FPGA_DDS/mem/sine_rom_4096x8.mem $proj_dir/sine_rom_4096x8.mem

# 添加约束 (无约束时综合仍可通过, 但生成比特流前必须填好引脚)
if {[file exists D:/FPGA_DDS/xdc/top_dds.xdc]} {
    add_files -fileset constrs_1 D:/FPGA_DDS/xdc/top_dds.xdc
}

set_property top top_dds [current_fileset]
update_compile_order -fileset sources_1

# 综合
launch_runs synth_1 -jobs 8
wait_on_run synth_1
if {[get_property PROGRESS [get_runs synth_1]] != "100%"} { puts "SYNTH FAILED"; exit 1 }

# 实现
launch_runs impl_1 -to_step write_bitstream -jobs 8
wait_on_run impl_1
if {[get_property PROGRESS [get_runs impl_1]] != "100%"} { puts "IMPL FAILED"; exit 1 }

puts "=== BITSTREAM DONE ==="
puts "[get_property DIRECTORY [get_runs impl_1]]/top_dds.bit"
