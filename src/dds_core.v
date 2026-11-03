`timescale 1ns/1ps
//====================================================================
// dds_core.v — DDS 内核: 32位相位累加器 + 四波形 + 双通道输出
// 通道A: 主输出; 通道B: 同频、相位偏移(0/90/180/270°)输出
// 幅度档位: 00:25% 01:50% 10:75% 11:100% (两通道同步)
// f_out = fcw * f_clk / 2^32
//====================================================================
module dds_core #(
    parameter PHASE_W = 32
)(
    input  wire               clk,            // 50MHz
    input  wire               rst_n,
    input  wire [PHASE_W-1:0] fcw,            // 频率控制字
    input  wire [PHASE_W-1:0] phase_offset,   // 通道B相位偏移量
    input  wire [1:0]         wave_sel,       // 00正弦 01方波 10三角波 11锯齿波
    input  wire [1:0]         amp_sel,        // 幅度档位
    output wire [9:0]         wave_out,       // 通道A (10位无符号, 中心512)
    output wire [9:0]         wave_out_b,     // 通道B
    output wire               square_out,     // 相位最高位 = 与输出同频的方波
    output wire [11:0]        rom_addr,       // 正弦ROM A口地址
    input  wire [7:0]         rom_data,
    output wire [11:0]        rom_addr_b,     // 正弦ROM B口地址
    input  wire [7:0]         rom_data_b
);
    reg [PHASE_W-1:0] phase = {PHASE_W{1'b0}};
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) phase <= {PHASE_W{1'b0}};
        else        phase <= phase + fcw;
    end

    wire [PHASE_W-1:0] phase_b = phase + phase_offset;

    assign square_out = phase[PHASE_W-1];
    assign rom_addr   = phase[PHASE_W-1 -: 12];
    assign rom_addr_b = phase_b[PHASE_W-1 -: 12];

    // ---- 波形取值 (10位无符号, 中心512) ----
    function [9:0] wave_val;
        input [PHASE_W-1:0] ph;
        input [1:0] sel;
        input [7:0] rd;                 // 正弦ROM数据(0..255中心128)
        reg [8:0] s9;
        begin
            case (sel)
                2'd0: begin             // 正弦: 512 + (rd-128)*4
                    s9 = {1'b0, rd} - 9'd128;
                    wave_val = 10'd512 + {s9, 2'b00};
                end
                2'd1:   wave_val = ph[PHASE_W-1] ? 10'd1023 : 10'd0;   // 方波
                2'd2:   wave_val = (ph[PHASE_W-1] ? (11'd2047 - ph[PHASE_W-2 -: 11])
                                                 : ph[PHASE_W-2 -: 11]) >> 1;  // 三角
                2'd3:   wave_val = ph[PHASE_W-1 -: 10];                 // 锯齿
                default: wave_val = 10'd512;
            endcase
        end
    endfunction

    // ---- 幅度缩放 ----
    function [9:0] amp_scale;
        input [9:0] v;
        input [1:0] a;
        reg signed [12:0] vs;
        begin
            vs = $signed({1'b0, v}) - 13'sd512;      // [-512, 511]
            case (a)
                2'd0: vs = vs >>> 2;                 // 25%
                2'd1: vs = vs >>> 1;                 // 50%
                2'd2: vs = (vs * 13'sd3) >>> 2;      // 75% (有符号乘法!)
                default: vs = vs;                    // 100%
            endcase
            amp_scale = 10'd512 + vs;                // [0, 1023]
        end
    endfunction

    reg [9:0] out_a_r = 10'd512;
    reg [9:0] out_b_r = 10'd512;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            out_a_r <= 10'd512;
            out_b_r <= 10'd512;
        end else begin
            out_a_r <= amp_scale(wave_val(phase,   wave_sel, rom_data),   amp_sel);
            out_b_r <= amp_scale(wave_val(phase_b, wave_sel, rom_data_b), amp_sel);
        end
    end

    assign wave_out   = out_a_r;
    assign wave_out_b = out_b_r;
endmodule
