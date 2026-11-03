`timescale 1ns/1ps
//====================================================================
// bin2bcd.v — 24位二进制 → 8位BCD (双dabble算法, 组合逻辑)
// 最大 16,777,215 → 8 个 BCD 位
//====================================================================
module bin2bcd (
    input  wire [23:0] bin,
    output reg  [31:0] bcd    // bcd[31:28]=千万位 ... bcd[3:0]=个位
);
    integer i;
    reg [55:0] shift;

    always @(*) begin
        shift = {32'b0, bin};
        for (i = 0; i < 24; i = i + 1) begin
            if (shift[27:24] >= 5) shift[27:24] = shift[27:24] + 3;
            if (shift[31:28] >= 5) shift[31:28] = shift[31:28] + 3;
            if (shift[35:32] >= 5) shift[35:32] = shift[35:32] + 3;
            if (shift[39:36] >= 5) shift[39:36] = shift[39:36] + 3;
            if (shift[43:40] >= 5) shift[43:40] = shift[43:40] + 3;
            if (shift[47:44] >= 5) shift[47:44] = shift[47:44] + 3;
            if (shift[51:48] >= 5) shift[51:48] = shift[51:48] + 3;
            if (shift[55:52] >= 5) shift[55:52] = shift[55:52] + 3;
            shift = shift << 1;
        end
        bcd = shift[55:24];
    end
endmodule
