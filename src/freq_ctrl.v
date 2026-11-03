`timescale 1ns/1ps
//====================================================================
// freq_ctrl.v — 频率控制: 按键增减频率 + 步进档位切换 + 长按连加
// 默认 1kHz; 步进循环: 1kHz → 10kHz → 100kHz → 1MHz
// 长按按键: 每 100ms 自动步进一次 (无需反复按)
// fcw = freq_hz * 2^32 / CLK_HZ (64位中间值, 精确无误差)
//====================================================================
module freq_ctrl #(
    parameter CLK_HZ = 50_000_000,
    parameter F_MAX  = 10_000_000,   // 上限 10MHz
    parameter F_MIN  = 100,          // 下限 100Hz
    parameter REPEAT_TICKS = 5_000_000   // 长按连加速率: 100ms/步
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        btn_up,       // 消抖后单脉冲
    input  wire        btn_down,
    input  wire        btn_step,
    input  wire        up_hold,      // 长按电平(连加)
    input  wire        down_hold,    // 长按电平(连减)
    output reg  [23:0] freq_hz,      // 当前频率 (Hz)
    output reg  [1:0]  step_sel,     // 0:1k 1:10k 2:100k 3:1M
    output wire [31:0] fcw
);
    reg [23:0] step_hz;
    reg [22:0] rep_cnt;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            freq_hz  <= 24'd1000;
            step_sel <= 2'd0;
            rep_cnt  <= 23'd0;
        end else begin
            case (step_sel)
                2'd0: step_hz = 24'd1000;
                2'd1: step_hz = 24'd10000;
                2'd2: step_hz = 24'd100000;
                2'd3: step_hz = 24'd1000000;
                default: step_hz = 24'd1000;
            endcase
            if (btn_step)                                  step_sel <= step_sel + 2'd1;
            if (btn_up   && freq_hz <= F_MAX - step_hz)    freq_hz  <= freq_hz + step_hz;
            if (btn_down && freq_hz >= F_MIN + step_hz)    freq_hz  <= freq_hz - step_hz;
            // 长按连加/连减: 每100ms一步
            if (up_hold || down_hold) begin
                rep_cnt <= rep_cnt + 23'd1;
                if (rep_cnt >= REPEAT_TICKS - 1) begin
                    rep_cnt <= REPEAT_TICKS - 50_000;
                    if (up_hold && freq_hz <= F_MAX - step_hz)
                        freq_hz <= freq_hz + step_hz;
                    else if (down_hold && freq_hz >= F_MIN + step_hz)
                        freq_hz <= freq_hz - step_hz;
                end
            end else begin
                rep_cnt <= 23'd0;
            end
        end
    end

    assign fcw = (freq_hz * 64'd4294967296) / CLK_HZ;
endmodule
