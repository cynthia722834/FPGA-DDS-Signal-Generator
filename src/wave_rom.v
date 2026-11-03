`timescale 1ns/1ps
//====================================================================
// wave_rom.v — 正弦波查找表 (4096 x 8bit), 真双端口 BRAM
// 端口A: DDS 输出 (50MHz 时钟域)
// 端口B: VGA 波形渲染 (25MHz 像素时钟域)
//====================================================================
module wave_rom (
    input  wire        clk_a,
    input  wire [11:0] addr_a,
    output reg  [7:0]  dout_a,
    input  wire        clk_b,
    input  wire [11:0] addr_b,
    output reg  [7:0]  dout_b
);
    reg [7:0] mem [0:4095];
    // 用裸文件名: 工程模式下由 add_files 加入的 .mem 目录参与搜索;
    // 仿真时需在包含该文件的目录下运行(或将文件复制到运行目录)
    initial $readmemh("sine_rom_4096x8.mem", mem);

    always @(posedge clk_a) dout_a <= mem[addr_a];
    always @(posedge clk_b) dout_b <= mem[addr_b];
endmodule
