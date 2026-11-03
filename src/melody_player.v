`timescale 1ns/1ps
//====================================================================
// melody_player.v — 旋律播放器: 从音符表读取音名+时值, 输出音符频率
// 内置《小星星》全曲(42音符), 播放时驱动 DDS 输出正弦旋律
// 音符频率表: 标准十二平均律
//====================================================================
module melody_player #(
    parameter CLK_HZ  = 50_000_000,
    parameter DUR_UNIT = 500000,   // 时值单位(10ms)对应的时钟周期数
    parameter GAP_TICKS = 1_250_000 // 音符间间隙(25ms): 让节奏分明
)(
    input  wire        clk,
    input  wire        rst_n,
    input  wire        play_en,       // 播放使能(开关)
    input  wire        song_sel,      // 0=小星星 1=生日快乐
    output reg  [23:0] note_freq,     // 当前音符频率(Hz)
    output reg         playing,       // 正在播放指示
    output reg         note_on        // 音符发声使能(间隙期为低, 制造节奏)
);
    // ---- 音符频率表 (12 音阶, 单位Hz) ----
    // 索引: 0=C4 2=D4 4=E4 5=F4 7=G4 9=A4 11=B4 12=C5 14=D5 16=E5 17=F5 19=G5
    function [23:0] note_hz;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  note_hz = 24'd262;
                5'd1:  note_hz = 24'd277;
                5'd2:  note_hz = 24'd294;
                5'd3:  note_hz = 24'd311;
                5'd4:  note_hz = 24'd330;
                5'd5:  note_hz = 24'd349;
                5'd6:  note_hz = 24'd370;
                5'd7:  note_hz = 24'd392;
                5'd8:  note_hz = 24'd415;
                5'd9:  note_hz = 24'd440;
                5'd10: note_hz = 24'd466;
                5'd11: note_hz = 24'd494;
                5'd12: note_hz = 24'd523;
                5'd13: note_hz = 24'd554;
                5'd14: note_hz = 24'd587;
                5'd15: note_hz = 24'd622;
                5'd16: note_hz = 24'd659;
                5'd17: note_hz = 24'd698;
                5'd18: note_hz = 24'd740;
                5'd19: note_hz = 24'd784;
                default: note_hz = 24'd262;
            endcase
        end
    endfunction

    // ---- 歌曲库: 音名+时值(10ms单位) ----
    // 歌曲0 小星星(42音符): 1 1 5 5 6 6 5- | 4 4 3 3 2 2 1- | 5 5 4 4 3 3 2- | 5 5 4 4 3 3 2- | 1 1 5 5 6 6 5- | 4 4 3 3 2 2 1-
    // 歌曲1 生日快乐(25音符, 3/4拍): 5 5 6 5 1' 7- | 5 5 6 5 2' 1'- | 5 5 5' 3' 1' 7 6 | 4' 4' 3' 1' 2' 1'-
    reg [4:0]  mel_note [0:41];
    reg [6:0]  mel_dur  [0:41];
    reg [4:0]  mel2_note [0:24];
    reg [6:0]  mel2_dur  [0:24];
    integer mi;
    initial begin
        for (mi = 0; mi < 42; mi = mi + 1) begin mel_note[mi] = 5'd0; mel_dur[mi] = 7'd0; end
        for (mi = 0; mi < 25; mi = mi + 1) begin mel2_note[mi] = 5'd0; mel2_dur[mi] = 7'd0; end
        // 音符索引: C4=0 D4=2 E4=4 F4=5 G4=7 A4=9 B4=11 C5=12 D5=14 E5=16 F5=17 G5=19
        // ---- 小星星 ----
        mel_note[0]=5'd0;  mel_dur[0]=7'd40;    // 1
        mel_note[1]=5'd0;  mel_dur[1]=7'd40;    // 1
        mel_note[2]=5'd7;  mel_dur[2]=7'd40;    // 5
        mel_note[3]=5'd7;  mel_dur[3]=7'd40;    // 5
        mel_note[4]=5'd9;  mel_dur[4]=7'd40;    // 6
        mel_note[5]=5'd9;  mel_dur[5]=7'd40;    // 6
        mel_note[6]=5'd7;  mel_dur[6]=7'd80;    // 5-
        mel_note[7]=5'd5;  mel_dur[7]=7'd40;    // 4
        mel_note[8]=5'd5;  mel_dur[8]=7'd40;    // 4
        mel_note[9]=5'd4;  mel_dur[9]=7'd40;    // 3
        mel_note[10]=5'd4; mel_dur[10]=7'd40;   // 3
        mel_note[11]=5'd2; mel_dur[11]=7'd40;   // 2
        mel_note[12]=5'd2; mel_dur[12]=7'd40;   // 2
        mel_note[13]=5'd0; mel_dur[13]=7'd80;   // 1-
        mel_note[14]=5'd7; mel_dur[14]=7'd40;   // 5
        mel_note[15]=5'd7; mel_dur[15]=7'd40;   // 5
        mel_note[16]=5'd5; mel_dur[16]=7'd40;   // 4
        mel_note[17]=5'd5; mel_dur[17]=7'd40;   // 4
        mel_note[18]=5'd4; mel_dur[18]=7'd40;   // 3
        mel_note[19]=5'd4; mel_dur[19]=7'd40;   // 3
        mel_note[20]=5'd2; mel_dur[20]=7'd80;   // 2-
        mel_note[21]=5'd7; mel_dur[21]=7'd40;   // 5
        mel_note[22]=5'd7; mel_dur[22]=7'd40;   // 5
        mel_note[23]=5'd5; mel_dur[23]=7'd40;   // 4
        mel_note[24]=5'd5; mel_dur[24]=7'd40;   // 4
        mel_note[25]=5'd4; mel_dur[25]=7'd40;   // 3
        mel_note[26]=5'd4; mel_dur[26]=7'd40;   // 3
        mel_note[27]=5'd2; mel_dur[27]=7'd80;   // 2-
        mel_note[28]=5'd0; mel_dur[28]=7'd40;   // 1
        mel_note[29]=5'd0; mel_dur[29]=7'd40;   // 1
        mel_note[30]=5'd7; mel_dur[30]=7'd40;   // 5
        mel_note[31]=5'd7; mel_dur[31]=7'd40;   // 5
        mel_note[32]=5'd9; mel_dur[32]=7'd40;   // 6
        mel_note[33]=5'd9; mel_dur[33]=7'd40;   // 6
        mel_note[34]=5'd7; mel_dur[34]=7'd80;   // 5-
        mel_note[35]=5'd5; mel_dur[35]=7'd40;   // 4
        mel_note[36]=5'd5; mel_dur[36]=7'd40;   // 4
        mel_note[37]=5'd4; mel_dur[37]=7'd40;   // 3
        mel_note[38]=5'd4; mel_dur[38]=7'd40;   // 3
        mel_note[39]=5'd2; mel_dur[39]=7'd40;   // 2
        mel_note[40]=5'd2; mel_dur[40]=7'd40;   // 2
        mel_note[41]=5'd0; mel_dur[41]=7'd80;   // 1-
        // ---- 生日快乐 (3/4拍, 300ms/拍) ----
        mel2_note[0]=5'd7;  mel2_dur[0]=7'd15;   // 5
        mel2_note[1]=5'd7;  mel2_dur[1]=7'd15;   // 5
        mel2_note[2]=5'd9;  mel2_dur[2]=7'd30;   // 6
        mel2_note[3]=5'd7;  mel2_dur[3]=7'd30;   // 5
        mel2_note[4]=5'd12; mel2_dur[4]=7'd30;   // 1'
        mel2_note[5]=5'd11; mel2_dur[5]=7'd60;   // 7-
        mel2_note[6]=5'd7;  mel2_dur[6]=7'd15;   // 5
        mel2_note[7]=5'd7;  mel2_dur[7]=7'd15;   // 5
        mel2_note[8]=5'd9;  mel2_dur[8]=7'd30;   // 6
        mel2_note[9]=5'd7;  mel2_dur[9]=7'd30;   // 5
        mel2_note[10]=5'd14; mel2_dur[10]=7'd30; // 2'
        mel2_note[11]=5'd12; mel2_dur[11]=7'd60; // 1'-
        mel2_note[12]=5'd7; mel2_dur[12]=7'd15;  // 5
        mel2_note[13]=5'd7; mel2_dur[13]=7'd15;  // 5
        mel2_note[14]=5'd19; mel2_dur[14]=7'd30; // 5'
        mel2_note[15]=5'd16; mel2_dur[15]=7'd30; // 3'
        mel2_note[16]=5'd12; mel2_dur[16]=7'd30; // 1'
        mel2_note[17]=5'd11; mel2_dur[17]=7'd30; // 7
        mel2_note[18]=5'd9;  mel2_dur[18]=7'd30; // 6
        mel2_note[19]=5'd17; mel2_dur[19]=7'd30; // 4'
        mel2_note[20]=5'd17; mel2_dur[20]=7'd30; // 4'
        mel2_note[21]=5'd16; mel2_dur[21]=7'd30; // 3'
        mel2_note[22]=5'd12; mel2_dur[22]=7'd30; // 1'
        mel2_note[23]=5'd14; mel2_dur[23]=7'd30; // 2'
        mel2_note[24]=5'd12; mel2_dur[24]=7'd60; // 1'-
    end

    reg [5:0] idx = 6'd0;
    reg [25:0] cnt = 26'd0;      // 26位: 最大时值 80*500000=40M
    reg [6:0] dur = 7'd0;
    reg idx_valid = 1'b0;
    reg song_r = 1'b0;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            idx <= 6'd0; cnt <= 26'd0; dur <= 7'd0;
            idx_valid <= 1'b0; playing <= 1'b0;
            note_freq <= 24'd262; note_on <= 1'b0;
            song_r <= 1'b0;
        end else begin
            if (!play_en) begin
                idx <= 6'd0; cnt <= 26'd0; idx_valid <= 1'b0;
                playing <= 1'b0; note_on <= 1'b0;
            end else begin
                playing <= 1'b1;
                // 切换歌曲时从头播放
                if (song_sel != song_r) begin
                    song_r <= song_sel;
                    idx <= 6'd0; idx_valid <= 1'b0; cnt <= 26'd0;
                end else if (!idx_valid) begin
                    dur <= song_sel ? mel2_dur[idx] : mel_dur[idx];
                    idx_valid <= 1'b1;
                    cnt <= 26'd0;
                end else if (cnt >= dur * DUR_UNIT - 1) begin
                    // 当前音符到时, 换下一个(循环播放)
                    if (song_sel ? (idx == 6'd24) : (idx == 6'd41)) idx <= 6'd0;
                    else                                              idx <= idx + 6'd1;
                    idx_valid <= 1'b0;
                end else begin
                    cnt <= cnt + 26'd1;
                end
                // 每个音符开头静默25ms, 形成节奏分明的"断奏"
                note_on <= (cnt >= GAP_TICKS);
            end
            note_freq <= note_hz(song_sel ? mel2_note[idx] : mel_note[idx]);
        end
    end
endmodule
