# 仿真脚本: xvlog 编译 → xelab 精化 → xsim 运行
cd D:/FPGA_DDS
xvlog [glob D:/FPGA_DDS/src/*.v] D:/FPGA_DDS/sim/tb_dds.v
xelab tb_dds -s dds_sim
xsim dds_sim -R
