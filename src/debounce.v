`timescale 1ns/1ps
//====================================================================
// debounce.v — 按键消抖 (低有效按键, 按下为低电平)
// 输入电平需保持稳定 MS_TICKS 个周期后才被确认:
//   * btn_stable: 消抖后的稳定电平 (确认后更新)
//   * btn_pulse:  确认"按下"的瞬间输出单周期脉冲
//====================================================================
module debounce #(
    parameter WIDTH    = 4,
    parameter MS_TICKS = 1_000_000    // 20ms @ 50MHz
)(
    input  wire             clk,
    input  wire             rst_n,
    input  wire [WIDTH-1:0] btn_in,       // 按下为低电平
    output wire [WIDTH-1:0] btn_stable,   // 消抖后的稳定电平
    output wire [WIDTH-1:0] btn_pulse     // 按下瞬间单周期脉冲
);
    // 两级同步消除亚稳态
    reg [WIDTH-1:0] sync1, sync2;
    always @(posedge clk) begin
        sync1 <= btn_in;
        sync2 <= sync1;
    end

    // 输入信号连续稳定 MS_TICKS 个周期后, 确认新电平
    // 寄存器显式初始值: 仿真避免X态, 上板即 INIT 值(按键未按下=全1)
    reg [WIDTH-1:0] sync_prev = {WIDTH{1'b1}};
    reg [19:0] cnt = 20'd0;
    reg [WIDTH-1:0] stable_r = {WIDTH{1'b1}};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sync_prev <= {WIDTH{1'b1}};
            cnt       <= 20'd0;
            stable_r  <= {WIDTH{1'b1}};
        end else begin
            sync_prev <= sync2;
            if (sync2 != sync_prev) begin          // 输入发生变化(抖动), 重新计时
                cnt <= 20'd0;
            end else if (cnt != MS_TICKS) begin    // 输入稳定, 持续计时
                cnt <= cnt + 20'd1;
            end
            if (cnt == MS_TICKS) stable_r <= sync2; // 稳定期满, 确认电平
        end
    end

    // 稳定值下降沿 = 确认按下
    reg [WIDTH-1:0] stable_prev = {WIDTH{1'b1}};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) stable_prev <= {WIDTH{1'b1}};
        else        stable_prev <= stable_r;
    end

    assign btn_stable = stable_r;
    assign btn_pulse  = stable_prev & ~stable_r;
endmodule
