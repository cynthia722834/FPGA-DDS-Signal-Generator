`timescale 1ns/1ps
//====================================================================
// seg7_display.v — 6位数码管动态扫描, 显示当前频率
// 显示规则: <1MHz → xxx.yyy kHz (前导0熄灭)
//           >=1MHz → x.yyy MHz (后两位熄灭), 单位由 LED 指示
// 极性参数按板子实际数码管类型修改
//====================================================================
module seg7_display #(
    parameter SEG_ACTIVE_LOW = 1'b0,   // 段码极性: 0=共阴(高有效) 1=共阳(低有效)
    parameter SEL_ACTIVE_LOW = 1'b0,   // 位选极性: 0=高有效 1=低有效
    parameter SCAN_DIV       = 5000     // 扫描时钟分频 (50MHz/5000=10kHz/位)
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire [23:0] freq_hz,
    output wire [7:0]  seg,        // 段码 {dp,g,f,e,d,c,b,a}
    output wire [5:0]  seg_sel,    // 位选
    output wire        led_mhz,    // MHz 档指示
    output wire        led_khz     // kHz 档指示
);
    wire [31:0] bcd;
    bin2bcd u_bin2bcd (.bin(freq_hz), .bcd(bcd));

    wire mhz_mode = (freq_hz >= 24'd1_000_000);
    assign led_mhz = mhz_mode;
    assign led_khz = ~mhz_mode;

    // ---- 显示数字与小数点位置 ----
    reg [3:0] dig [0:5];
    reg [2:0] dp_pos;
    integer i;
    always @(*) begin
        for (i = 0; i < 6; i = i + 1) dig[i] = 4'hF;   // F=熄灭
        if (mhz_mode) begin
            // x.yyy MHz: 千位,百位,十位,个位(Hz的10^6~10^3位)
            dig[3] = bcd[31:28];
            dig[2] = bcd[27:24];
            dig[1] = bcd[23:20];
            dig[0] = bcd[19:16];
            dp_pos = 3'd3;
        end else begin
            // xxx.yyy kHz: 直接取 Hz 的 10^6..10^1 位
            dig[5] = bcd[27:24];
            dig[4] = bcd[23:20];
            dig[3] = bcd[19:16];
            dig[2] = bcd[15:12];
            dig[1] = bcd[11:8];
            dig[0] = bcd[7:4];
            dp_pos = 3'd2;
            // 前导0熄灭: 千位为0熄灭, 百位在前导情况下也熄灭
            if (dig[5] == 4'd0) dig[5] = 4'hF;
            if (dig[5] == 4'hF && dig[4] == 4'd0) dig[4] = 4'hF;
        end
    end

    // ---- 动态扫描 ----
    reg [12:0] cnt;
    reg [2:0]  idx;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            cnt <= 13'd0;
            idx <= 3'd0;
        end else if (cnt == SCAN_DIV - 1) begin
            cnt <= 13'd0;
            idx <= (idx == 3'd5) ? 3'd0 : idx + 3'd1;
        end else begin
            cnt <= cnt + 13'd1;
        end
    end

    // ---- 段码译码 ----
    function [7:0] seg_code;
        input [3:0] d;
        begin
            case (d)
                4'd0: seg_code = 8'h3F;
                4'd1: seg_code = 8'h06;
                4'd2: seg_code = 8'h5B;
                4'd3: seg_code = 8'h4F;
                4'd4: seg_code = 8'h66;
                4'd5: seg_code = 8'h6D;
                4'd6: seg_code = 8'h7D;
                4'd7: seg_code = 8'h07;
                4'd8: seg_code = 8'h7F;
                4'd9: seg_code = 8'h6F;
                default: seg_code = 8'h00;
            endcase
        end
    endfunction

    wire [3:0] cur_dig = dig[idx];
    wire [7:0] code    = seg_code(cur_dig) | ((idx == dp_pos) ? 8'h80 : 8'h00);

    assign seg     = SEG_ACTIVE_LOW ? ~code : code;
    assign seg_sel = SEL_ACTIVE_LOW ? ~(6'b000001 << idx) : (6'b000001 << idx);
endmodule
