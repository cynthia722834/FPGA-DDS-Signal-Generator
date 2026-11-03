#====================================================================
# program_board.tcl — 烧录比特流到硬木课堂 Artix-7 板 (JTAG)
# 用法: vivado -mode batch -source D:/FPGA_DDS/program_board.tcl
#====================================================================
open_hw_manager
connect_hw_server -url localhost:3121
open_hw_target

# 刷新并列举设备
set devices [get_hw_devices]
puts "发现硬件设备: $devices"

if {[llength $devices] == 0} {
    puts "!!! 未发现 FPGA 设备, 请检查:"
    puts "  1. USB 线是否插在 JTAG 口"
    puts "  2. 板子电源是否打开"
    puts "  3. 是否有其他软件占用 FT2232"
    exit 1
}

current_hw_device [lindex $devices 0]
refresh_hw_device -update_hw_probes false [current_hw_device]

set_property PROGRAM.FILE {D:/FPGA_DDS/vivado_proj/dds_signal_gen.runs/impl_1/top_dds.bit} [current_hw_device]
puts "开始烧录..."
program_hw_devices [current_hw_device]
puts "=== PROGRAM DONE ==="
close_hw_manager
