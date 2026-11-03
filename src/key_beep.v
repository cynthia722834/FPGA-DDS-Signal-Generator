`timescale 1ns/1ps
//====================================================================
// key_beep.v — 按键提示音: 按键时输出短促"滴"声(100ms)
// 不同按键不同音调: 频率+ →1kHz, 频率- →800Hz, 步进 →1.2kHz
// 旋律播放期间静默(蜂鸣器让位给音乐)
//====================================================================
module key_beep #(
    parameter CLK_HZ      = 50_000_000,
    parameter BEEP_TICKS  = 5_000_000   // 100ms
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        btn_up,     // 消抖后单脉冲
    input  wire        btn_down,
    input  wire        btn_step,
    input  wire        playing,    // 旋律播放中则静默
    output reg         beep_out
);
    reg [22:0] cnt;
    reg        beep_active;
    reg [15:0] tone_cnt;
    reg [15:0] tone_thresh;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 23'd0; beep_active <= 1'b0; tone_cnt <= 16'd0;
            beep_out <= 1'b0; tone_thresh <= 16'd25000;
        end else begin
            if (playing) begin
                cnt <= 23'd0; beep_active <= 1'b0; beep_out <= 1'b0;
            end else if (btn_up || btn_down || btn_step) begin
                beep_active <= 1'b1;
                cnt <= 23'd0;
                tone_cnt <= 16'd0;
                // 半周期 = CLK_HZ/(2*f): 1kHz→25000, 800Hz→31250, 1.2kHz→20833
                tone_thresh <= btn_up   ? 16'd25000 :
                               btn_down ? 16'd31250 : 16'd20833;
            end else if (beep_active) begin
                if (cnt >= BEEP_TICKS - 1) begin
                    beep_active <= 1'b0;
                    beep_out <= 1'b0;
                end else begin
                    cnt <= cnt + 23'd1;
                    if (tone_cnt >= tone_thresh - 1) begin
                        tone_cnt <= 16'd0;
                        beep_out <= ~beep_out;
                    end else begin
                        tone_cnt <= tone_cnt + 16'd1;
                    end
                end
            end
        end
    end
endmodule
