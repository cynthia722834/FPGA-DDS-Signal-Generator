`timescale 1ns/1ps
//====================================================================
// sweep_ctrl.v — 扫频控制: 频率自动从下限扫到上限再回卷
// 每 STEP_TICKS 周期按 step_hz 递增一次, 用于演示 DDS 宽频输出
//====================================================================
module sweep_ctrl #(
    parameter CLK_HZ  = 50_000_000,
    parameter STEP_TICKS = 500_000    // 每 10ms 步进一次
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        sweep_en,      // 扫频使能
    input  wire [23:0] step_hz,       // 每步频率增量
    input  wire [23:0] f_min,
    input  wire [23:0] f_max,
    input  wire [23:0] init_freq,     // 使能时的起始频率
    output reg  [23:0] freq_out
);
    reg [19:0] cnt = 20'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 20'd0;
            freq_out <= init_freq;
        end else begin
            if (!sweep_en) begin
                cnt <= 20'd0;
                freq_out <= init_freq;
            end else begin
                if (cnt >= STEP_TICKS - 1) begin
                    cnt <= 20'd0;
                    if (freq_out + step_hz > f_max) freq_out <= f_min;
                    else                              freq_out <= freq_out + step_hz;
                end else begin
                    cnt <= cnt + 20'd1;
                end
            end
        end
    end
endmodule
