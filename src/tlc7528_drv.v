`timescale 1ns/1ps
//====================================================================
// tlc7528_drv.v — 板载 TLC7528 双通道 8 位并行 DAC 驱动
//
// 时序(参考硬木课堂官方例程):
//   DAC_CS 与 DAC_WR 用同一方波驱动(低有效), 频率为采样率的 2 倍
//   DACAB 为 CS/WR 的 2 分频, 即 DAC 实际采样率
//   DACAB=0 时数据线放通道A数据, =1 时放通道B数据
//
// 本设计采样率 1MHz (50MHz/50), CS/WR 低电平宽 500ns >> 数据手册
// 要求的写脉冲宽度(约100ns), 数据在 WR 上升沿前 500ns 已稳定。
// 注意: 1MHz 采样率下输出信号最高约 400kHz (奈奎斯特), 超过会混叠。
//====================================================================
module tlc7528_drv #(
    parameter SAMPLE_DIV = 50      // 采样率 = clk / SAMPLE_DIV
)(
    input  wire        clk,        // 50MHz
    input  wire        rst_n,
    input  wire [7:0]  data_a,     // 通道A 数字量 (0..255)
    input  wire [7:0]  data_b,     // 通道B 数字量
    output reg         dac_cs,     // 片选 (低有效)
    output reg         dac_wr,     // 写使能 (低有效)
    output reg         dac_ab,     // 通道选择
    output reg  [7:0]  dac_data    // 8位数据总线
);
    localparam HALF = SAMPLE_DIV / 2;   // 25

    reg [5:0] cnt;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt      <= 6'd0;
            dac_ab   <= 1'b0;
            dac_cs   <= 1'b1;
            dac_wr   <= 1'b1;
            dac_data <= 8'd0;
        end else begin
            cnt <= (cnt == SAMPLE_DIV - 1) ? 6'd0 : cnt + 6'd1;
            // CS/WR 低电平: 前半周期
            dac_cs <= (cnt < HALF) ? 1'b0 : 1'b1;
            dac_wr <= (cnt < HALF) ? 1'b0 : 1'b1;
            // DACAB: 每个采样周期翻转一次(在 WR 变低的瞬间)
            // 数据线同步切换为新通道的数据 (WR 上升沿前有 HALF 周期稳定时间)
            if (cnt == SAMPLE_DIV - 1) begin
                dac_ab   <= ~dac_ab;
                dac_data <= (dac_ab) ? data_a : data_b;  // 取"即将生效"的通道
            end
        end
    end
endmodule
