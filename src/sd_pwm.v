`timescale 1ns/1ps
//====================================================================
// sd_pwm.v — 一阶 Sigma-Delta 调制器: 10位波形 → 1位 PWM 音频流
// 输出接板载音频口(D9), 经板上低通滤波+功放后还原模拟波形
// 占空比 = sample/1024, 中心值512 → 50% 占空比(交流耦合后无直流)
//====================================================================
module sd_pwm (
    input  wire        clk,
    input  wire        rst_n,
    input  wire [9:0]  sample,      // 0..1023 中心512
    output reg         pwm_out
);
    reg [15:0] acc = 16'd0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            acc     <= 16'd0;
            pwm_out <= 1'b0;
        end else begin
            acc     <= acc + {6'b0, sample};
            pwm_out <= acc[15];
        end
    end
endmodule
