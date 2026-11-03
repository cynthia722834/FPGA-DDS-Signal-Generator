`timescale 1ns/1ps
//====================================================================
// startupe2_inst.v — STARTUPE2 原语例化
// 7系列FPGA配置完成后, 配置SPI引脚(D00-D03等)的访问权交给用户逻辑;
// 若不例化 STARTUPE2, Vivado 无法通过JTAG间接烧写板载QSPI Flash
// (表现为 "Failure to set flash parameters")。
// 本模块仅作占位: 不使用USRCLK/USRDONE功能, 只为打通Flash烧写通道。
//====================================================================
module startupe2_inst ();
    STARTUPE2 #(
        .PROG_USR("FALSE"),
        .SIM_CCLK_FREQ(0.0)
    ) u_startupe2 (
        .CFGCLK(),      // 输出: 配置时钟
        .CFGMCLK(),     // 输出: 配置主时钟
        .CLK(1'b0),
        .GSR(1'b0),
        .GTS(1'b0),
        .KEYCLEARB(1'b0),
        .PACK(1'b0),
        .USRCCLKO(1'b0),   // 用户CCLK输出(不用)
        .USRCCLKTS(1'b0),  // 三态(不用)
        .USRDONEO(1'b1),   // DONE引脚输出(上拉)
        .USRDONETS(1'b1),  // DONE三态(不用时置1)
        .EOS()             // 配置结束指示
    );
endmodule
