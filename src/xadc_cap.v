`timescale 1ns/1ps
//====================================================================
// xadc_cap.v — XADC 采集模块: 连续序列模式, 抓取通道6 (VAUXP6, ±5V模拟输入B)
// 默认配置下各通道轮流采样, 通道6速率约 46kHz (音频段足够)
// 采样值写入 1024x12 环形缓冲, VGA 显示端可跨时钟读取
//====================================================================
module xadc_cap (
    input  wire        clk50,
    input  wire        rst_n,
    input  wire        vaux6_p,       // 模拟输入正(±5V前端Analog B, 引脚C3)
    input  wire        vaux6_n,       // 模拟输入负(引脚C2, 使用时接地)
    // ---- VGA 读端口 (25MHz 像素时钟域) ----
    input  wire        clk_pix,
    input  wire [9:0]  rd_addr,
    output reg  [11:0] rd_data,
    output reg  [9:0]  wptr          // 当前写指针(供显示端锁存)
);
    wire [15:0] do;
    wire        drdy, eoc, eos, busy;
    wire [4:0]  channel;

    XADC #(
        .INIT_40(16'h0000),   // 默认: 连续序列模式, ADCCLK=DCLK/2=25MHz
        .INIT_41(16'h0000),
        .INIT_42(16'h0000),   // 内部通道全不使能
        .INIT_48(16'h0040),   // 只使能辅助通道6 → 单通道连续采样约960kSPS
        .INIT_49(16'h0000),
        .INIT_4A(16'h0000), .INIT_4B(16'h0000), .INIT_4C(16'h0000),
        .INIT_4D(16'h0000), .INIT_4E(16'h0000), .INIT_4F(16'h0000),
        .INIT_50(16'h0000), .INIT_51(16'h0000), .INIT_52(16'h0000),
        .INIT_53(16'h0000), .INIT_54(16'h0000), .INIT_55(16'h0000),
        .INIT_56(16'h0000), .INIT_57(16'h0000), .INIT_58(16'h0000),
        .INIT_59(16'h0000), .INIT_5A(16'h0000), .INIT_5B(16'h0000),
        .INIT_5C(16'h0000), .INIT_5D(16'h0000), .INIT_5E(16'h0000),
        .INIT_5F(16'h0000),
        .SIM_DEVICE("7SERIES"),
        .SIM_MONITOR_FILE("mem/xadc_sim.txt")
    ) u_xadc (
        .DCLK(clk50),
        .RESET(~rst_n),
        .CONVST(1'b0), .CONVSTCLK(1'b0),
        .DADDR(7'h00), .DWE(1'b0), .DEN(1'b0), .DI(16'h0000),
        .DO(do), .DRDY(drdy), .CHANNEL(channel),
        .EOC(eoc), .EOS(eos), .BUSY(busy),
        .JTAGLOCKED(), .JTAGMODIFIED(), .JTAGBUSY(),
        .ALM(), .OT(), .MUXADDR(),
        .VP(1'b0), .VN(1'b0),
        .VAUXP({9'b0, vaux6_p, 6'b0}),
        .VAUXN({9'b0, vaux6_n, 6'b0})
    );

    // ---- 采样环形缓冲 (写: 50MHz域, 读: 25MHz域) ----
    reg [11:0] mem [0:1023];
    reg        we;
    reg [11:0] wdata;
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) begin
            we    <= 1'b0;
            wptr  <= 10'd0;
        end else begin
            we <= 1'b0;
            // 通道6: 兼容两种CHANNEL编码(DRP地址0x16 或 序号0x06)
            // EOC/DRDY 任一有效均触发
            if ((eoc || drdy) && (channel == 5'h16 || channel == 5'h06)) begin
                we    <= 1'b1;
                wdata <= do[15:4];
                wptr  <= wptr + 10'd1;
            end
        end
    end
    reg [9:0] waddr;
    always @(posedge clk50) waddr <= wptr;

    always @(posedge clk50) begin
        if (we) mem[waddr] <= wdata;
    end
    always @(posedge clk_pix) rd_data <= mem[rd_addr];
endmodule
