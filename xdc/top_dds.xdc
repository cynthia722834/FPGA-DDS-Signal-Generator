#====================================================================
# top_dds.xdc — DDS 信号发生器引脚约束
# 板卡: 硬木课堂 Artix-7 (XC7A35TFTG256-1) 核心板 + 扩展底板
# 引脚来源: 硬木课堂官方文档(语雀知识库)管脚约束表
#====================================================================

#---------- 系统时钟 50MHz (FPGA_GCLK1) ----------
set_property PACKAGE_PIN D4 [get_ports clk50]
set_property IOSTANDARD LVCMOS33 [get_ports clk50]
create_clock -period 20.000 -name clk50 [get_ports clk50]

#---------- 矩阵键盘 (第一行4键: KEY0..KEY3) ----------
set_property PACKAGE_PIN K3  [get_ports key_row]
set_property IOSTANDARD LVCMOS33 [get_ports key_row]
set_property PACKAGE_PIN R12 [get_ports {key_col[0]}]
set_property PACKAGE_PIN T12 [get_ports {key_col[1]}]
set_property PACKAGE_PIN R11 [get_ports {key_col[2]}]
set_property PACKAGE_PIN T10 [get_ports {key_col[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {key_col[*]}]
set_property PULLUP true [get_ports {key_col[*]}]

#---------- 拨码开关 ----------
# SW1:0 波形 | SW3:2 幅度 | SW5:4 相位差 | SW6/SW8 显示模式 | SW7 扫频 | SW9 音乐
set_property PACKAGE_PIN T9 [get_ports {sw[0]}]
set_property PACKAGE_PIN T8 [get_ports {sw[1]}]
set_property PACKAGE_PIN T7 [get_ports {sw[2]}]
set_property PACKAGE_PIN R6 [get_ports {sw[3]}]
set_property PACKAGE_PIN P6 [get_ports {sw[4]}]
set_property PACKAGE_PIN R5 [get_ports {sw[5]}]
set_property PACKAGE_PIN P4 [get_ports {sw[6]}]
set_property PACKAGE_PIN R3 [get_ports {sw[7]}]
set_property PACKAGE_PIN R2 [get_ports {sw[8]}]
set_property PACKAGE_PIN N4 [get_ports {sw[9]}]
set_property IOSTANDARD LVCMOS33 [get_ports {sw[*]}]

#---------- XADC 模拟输入 (通道6, ±5V模拟输入B; 负端使用时接地) ----------
set_property PACKAGE_PIN C3 [get_ports vaux6_p]
set_property PACKAGE_PIN C2 [get_ports vaux6_n]
set_property IOSTANDARD LVCMOS33 [get_ports {vaux6_p vaux6_n}]

#---------- 音频输出 (板载3.5mm口, PWM驱动功放) ----------
set_property PACKAGE_PIN D9 [get_ports audio_pwm]
set_property IOSTANDARD LVCMOS33 [get_ports audio_pwm]

#---------- 无源蜂鸣器 (播放旋律时发声) ----------
set_property PACKAGE_PIN L2 [get_ports buzzer]
set_property IOSTANDARD LVCMOS33 [get_ports buzzer]

#---------- 数码管段码 (共阴, 高有效) ----------
# seg[0]=A seg[1]=B seg[2]=C seg[3]=D seg[4]=E seg[5]=F seg[6]=G seg[7]=DP
set_property PACKAGE_PIN P11 [get_ports {seg[0]}]
set_property PACKAGE_PIN N12 [get_ports {seg[1]}]
set_property PACKAGE_PIN L14 [get_ports {seg[2]}]
set_property PACKAGE_PIN K13 [get_ports {seg[3]}]
set_property PACKAGE_PIN K12 [get_ports {seg[4]}]
set_property PACKAGE_PIN P13 [get_ports {seg[5]}]
set_property PACKAGE_PIN M14 [get_ports {seg[6]}]
set_property PACKAGE_PIN L13 [get_ports {seg[7]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg[*]}]

#---------- 数码管位选 (低有效) ----------
# seg_sel[5]=DIG1(最左) ... seg_sel[0]=DIG6(最右)
set_property PACKAGE_PIN N11 [get_ports {seg_sel[5]}]
set_property PACKAGE_PIN N14 [get_ports {seg_sel[4]}]
set_property PACKAGE_PIN N13 [get_ports {seg_sel[3]}]
set_property PACKAGE_PIN M12 [get_ports {seg_sel[2]}]
set_property PACKAGE_PIN H13 [get_ports {seg_sel[1]}]
set_property PACKAGE_PIN G12 [get_ports {seg_sel[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {seg_sel[*]}]

#---------- LED (共阴极, 高电平点亮) ----------
set_property PACKAGE_PIN P9 [get_ports {led[0]}]
set_property PACKAGE_PIN R8 [get_ports {led[1]}]
set_property PACKAGE_PIN R7 [get_ports {led[2]}]
set_property PACKAGE_PIN T5 [get_ports {led[3]}]
set_property IOSTANDARD LVCMOS33 [get_ports {led[*]}]

#---------- VGA RGB444 + 行场同步 (核心板自带VGA接口) ----------
set_property PACKAGE_PIN M15 [get_ports {vga_r[3]}]
set_property PACKAGE_PIN M16 [get_ports {vga_r[2]}]
set_property PACKAGE_PIN F4  [get_ports {vga_r[1]}]
set_property PACKAGE_PIN F5  [get_ports {vga_r[0]}]
set_property PACKAGE_PIN R15 [get_ports {vga_g[3]}]
set_property PACKAGE_PIN P16 [get_ports {vga_g[2]}]
set_property PACKAGE_PIN P15 [get_ports {vga_g[1]}]
set_property PACKAGE_PIN N16 [get_ports {vga_g[0]}]
set_property PACKAGE_PIN T14 [get_ports {vga_b[3]}]
set_property PACKAGE_PIN P14 [get_ports {vga_b[2]}]
set_property PACKAGE_PIN T15 [get_ports {vga_b[1]}]
set_property PACKAGE_PIN R16 [get_ports {vga_b[0]}]
set_property PACKAGE_PIN R13 [get_ports hsync]      ;# VGA_HS
set_property PACKAGE_PIN T13 [get_ports vsync]      ;# VGA_VS
set_property IOSTANDARD LVCMOS33 [get_ports {vga_r[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_g[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {vga_b[*]}]
set_property IOSTANDARD LVCMOS33 [get_ports {hsync vsync}]

#---------- 板载 TLC7528 双通道 DAC ----------
set_property PACKAGE_PIN H2 [get_ports dac_cs]
set_property PACKAGE_PIN H1 [get_ports dac_wr]
set_property PACKAGE_PIN J3 [get_ports dac_ab]
set_property PACKAGE_PIN J1 [get_ports {dac_data[7]}]
set_property PACKAGE_PIN K2 [get_ports {dac_data[6]}]
set_property PACKAGE_PIN K1 [get_ports {dac_data[5]}]
set_property PACKAGE_PIN L3 [get_ports {dac_data[4]}]
set_property PACKAGE_PIN E1 [get_ports {dac_data[3]}]
set_property PACKAGE_PIN F2 [get_ports {dac_data[2]}]
set_property PACKAGE_PIN G2 [get_ports {dac_data[1]}]
set_property PACKAGE_PIN G1 [get_ports {dac_data[0]}]
set_property IOSTANDARD LVCMOS33 [get_ports {dac_cs dac_wr dac_ab dac_data[*]}]

#---------- 25MHz 像素时钟 (BUFG 输出, 时序约束) ----------
create_clock -period 40.000 -name clk25 [get_nets clk25]
set_property PACKAGE_PIN H4 [get_ports {sw[10]}]
