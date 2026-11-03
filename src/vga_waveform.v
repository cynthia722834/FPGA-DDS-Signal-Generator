`timescale 1ns/1ps
//====================================================================
// vga_waveform.v — VGA 640x480@60Hz 显示 (25MHz 像素时钟)
//
// 两种显示模式 (拨码开关切换):
//   * 波形模式: 示波器风格, 固定 2 周期, 绿色波形 + 文字参数栏
//   * 李萨如模式: 两路正交正弦合成李萨如图(青色), 相位差可调
//
// 文字栏显示: 频率 / 波形名 / 幅度 / 相位差
// 渲染: 场消隐期把波形值渲染进两个行缓冲, 显示期逐像素绘制
//====================================================================
module vga_waveform #(
    parameter H_ACT = 640, H_FP = 16, H_SYNC = 96, H_BP = 48,
    parameter V_ACT = 480, V_FP = 10, V_SYNC = 2,  V_BP = 33,
    parameter X0 = 40,  X1 = 599,
    parameter Y0 = 100, Y1 = 419,
    parameter N_PERIODS = 2
)(
    input  wire        clk_pix,        // 25MHz
    input  wire        rst_n,
    input  wire [1:0]  wave_sel,
    input  wire [1:0]  mode,           // 00波形 01李萨如 1x示波器
    input  wire [1:0]  amp_sel,        // 幅度档位(仅显示用)
    input  wire [1:0]  phase_sel,      // 相位差档位(李萨如渲染用)
    input  wire [23:0] freq_hz,        // 当前频率(文字显示用)
    input  wire [31:0] fcw,            // 频率控制字(波形渲染周期数联动)
    input  wire [1:0]  step_sel,       // 步进档位(文字显示用)
    input  wire        playing_flag,   // 旋律播放中
    input  wire        sweep_flag,     // 扫频中
    input  wire        song_flag,      // 当前歌曲(0=小星星 1=生日快乐)
    output wire [11:0] rom_addr,       // 正弦ROM B口地址(通道A数据)
    input  wire [7:0]  rom_data,
    output wire [11:0] rom_addr_b,     // 正弦ROM B口地址(通道B数据)
    input  wire [7:0]  rom_data_b,
    input  wire [9:0]  scope_wptr,     // 示波器写指针(50MHz域, 帧头粗略同步)
    output wire [9:0]  scope_rd_addr,  // 示波器环形缓冲读地址
    input  wire [11:0] scope_rd_data,  // 12位采样值(0..4095)
    output reg  [3:0]  vga_r, vga_g, vga_b,
    output reg         hsync, vsync
);
    localparam H_TOTAL = H_ACT + H_FP + H_SYNC + H_BP;   // 800
    localparam V_TOTAL = V_ACT + V_FP + V_SYNC + V_BP;   // 525
    localparam WAVE_W  = X1 - X0 + 1;                    // 560
    localparam XC      = (X0 + X1) >> 1;                 // 319
    localparam YC      = (Y0 + Y1) >> 1;                 // 259
    localparam AMP     = (Y1 - Y0) >> 1;                 // 160
    // 波形模式每列相位增量: 每屏整数个周期(帧首尾无缝衔接)
    // N = round(f/500Hz) 钳位1..10; col_inc = N × 2^32/560
    localparam [31:0] INC_UNIT = 64'd4294967296 / WAVE_W;
    wire [24:0] n_raw = (freq_hz * 3'd2 + 25'd250) / 25'd1000;
    wire [24:0] n_clamp = (n_raw < 25'd1) ? 25'd1 :
                          (n_raw > 25'd10) ? 25'd10 : n_raw;
    wire [31:0] col_inc = n_clamp * INC_UNIT;

    // (wv_scaled 计算块已移至 rphase 声明之后, 避免前向引用)
    // 李萨如: 1周期/屏, 2倍过采样(1120列)保证x方向步进<1像素, 曲线无空洞
    localparam LIS_COLS = 1120;
    localparam [31:0] LIS_INC = 64'd4294967296 / LIS_COLS;
    // 显示模式
    localparam MODE_WAVE  = 2'd0;
    localparam MODE_LIS   = 2'd1;
    localparam MODE_SCOPE = 2'd2;
    wire lis_mode  = (mode == MODE_LIS);
    wire scope_mode = (mode == MODE_SCOPE) || (mode == 2'd3);

    // ---- 行/场计数器 ----
    reg [9:0] hcnt, vcnt;
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            hcnt <= 10'd0; vcnt <= 10'd0;
        end else begin
            if (hcnt == H_TOTAL - 1) begin
                hcnt <= 10'd0;
                vcnt <= (vcnt == V_TOTAL - 1) ? 10'd0 : vcnt + 10'd1;
            end else hcnt <= hcnt + 10'd1;
        end
    end

    // ---- 两个行缓冲 xbuf/ybuf (1024x9) ----
    // 波形/示波器模式: xbuf[c]=波形值(8位, 0..255)
    // 李萨如模式: 按曲线x位置索引存储屏幕y偏移(0..319):
    //   ybuf[x_abs]=第一分支y, xbuf[x_abs]=第二分支y
    reg [8:0] xbuf [0:1023];
    reg [8:0] ybuf [0:1023];
    reg [9:0] waddr;  reg [8:0] wdata; reg we;
    reg [9:0] raddr;  reg [8:0] xbuf_r, ybuf_r;
    reg wb_sel;
    always @(posedge clk_pix) begin
        if (we) begin
            if (wb_sel) ybuf[waddr] <= wdata;
            else        xbuf[waddr] <= wdata;
        end
        xbuf_r <= xbuf[raddr];
        ybuf_r <= ybuf[raddr];
    end
    // 李萨如"已写入"标志 (渲染期用, 区分两个分支)
    // 坐标计算提前声明(flag读地址依赖x_abs)
    // 1:1映射: 像素步进恰好1, 数学上保证曲线无量化空洞 (图形±127像素)
    wire signed [8:0] lx = {1'b0, rom_data}   - 9'sd128;
    wire signed [8:0] ly = {1'b0, rom_data_b} - 9'sd128;
    wire signed [9:0] x_plot_c = XC + lx;                   // 192..446
    wire signed [9:0] y_plot_c = YC - ly;                   // 132..386
    wire [9:0] x_abs = x_plot_c - X0;                       // 152..406 (x索引)
    wire [8:0] y_rel = y_plot_c - Y0;                       // 32..286
    // 分布式RAM: 避免BRAM地址被异步复位寄存器驱动导致的读写损坏
    (* ram_style = "distributed" *) reg [0:0] flag [0:1023];
    reg [9:0] flag_waddr;
    reg       flag_we, flag_wdata;
    reg       flag_r;
    reg       flag_disp;
    reg       wb_latch;
    always @(posedge clk_pix) begin
        if (flag_we) flag[flag_waddr] <= flag_wdata;
        flag_r <= flag[x_abs];
        flag_disp <= flag[raddr];
    end

    // ---- 波形取值 (与 dds_core 输出一致, 归一化 0..255) ----
    function [7:0] wave_val;
        input [31:0] ph;
        input [1:0]  sel;
        input [7:0]  rd;
        begin
            case (sel)
                2'd0:   wave_val = rd;
                2'd1:   wave_val = ph[31] ? 8'd255 : 8'd0;
                2'd2:   wave_val = (ph[31] ? (11'd2047 - ph[30:20]) : ph[30:20]) >> 3;
                2'd3:   wave_val = ph[31:24];
                default: wave_val = rd;
            endcase
        end
    endfunction

    // ---- 场消隐期渲染 ----
    wire [31:0] lis_off = {phase_sel, 30'b0};   // 相位差: 90°步进
    reg        render_busy = 1'b0;
    reg [31:0] rphase = 32'd0;
    reg [10:0] rcol = 11'd0;                  // 需容纳1120列
    reg [2:0]  rsub = 3'd0;
    reg [9:0]  sbase = 10'd0;                  // 示波器帧起始地址(帧头锁存写指针)

    // 波形值幅度缩放 (VGA显示与DAC输出一致)
    wire [7:0] wv_raw = wave_val(rphase, wave_sel, rom_data);
    wire signed [8:0] wv_s = {1'b0, wv_raw} - 9'sd128;
    wire [7:0] wv_scaled = 8'd128 +
        ((amp_sel == 2'd0) ? (wv_s >>> 2) :
         (amp_sel == 2'd1) ? (wv_s >>> 1) :
         (amp_sel == 2'd2) ? ((wv_s * 3'sd3) >>> 2) : wv_s);

    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            render_busy <= 1'b0; rphase <= 32'd0; rcol <= 10'd0; rsub <= 3'd0;
            we <= 1'b0; flag_we <= 1'b0; flag_wdata <= 1'b0;
            sbase <= 10'd0;
        end else begin
            we <= 1'b0; flag_we <= 1'b0;
            if (vcnt == 0 && hcnt == 1) begin
                render_busy <= 1'b1; rphase <= 32'd0; rcol <= 10'd0;
                // 李萨如模式先清标志+缓冲再画; 其他模式直接渲染
                rsub <= (mode == MODE_LIS) ? 3'd7 : 3'd0;
                sbase <= scope_wptr - 10'd560;   // 显示最近560个采样点
            end else if (render_busy) begin
                case (mode)
                MODE_WAVE: begin
                    // 波形模式: 1周期/列, 幅度缩放, 相位增量随频率联动
                    we <= 1'b1; wb_sel <= 1'b0; waddr <= rcol;
                    wdata <= {1'b0, wv_scaled};
                    rphase <= rphase + col_inc;
                    rcol <= rcol + 11'd1;
                    if (rcol == WAVE_W - 1) render_busy <= 1'b0;
                end
                MODE_LIS: begin
                    // 李萨如: 清flag→清xbuf→清ybuf → 发地址→锁存flag→按分支写y
                    case (rsub)
                        3'd7: begin                       // 清标志
                            flag_we <= 1'b1; flag_waddr <= rcol; flag_wdata <= 1'b0;
                            rsub <= 3'd6;
                        end
                        3'd6: begin                       // 清xbuf
                            we <= 1'b1; wb_sel <= 1'b0; waddr <= rcol; wdata <= 9'd0;
                            rsub <= 3'd5;
                        end
                        3'd5: begin                       // 清ybuf, 列前进(清0..559)
                            we <= 1'b1; wb_sel <= 1'b1; waddr <= rcol; wdata <= 9'd0;
                            rsub <= 3'd7;
                            rcol <= rcol + 10'd1;
                            if (rcol == WAVE_W - 1) begin rsub <= 3'd0; rcol <= 10'd0; end
                        end
                        3'd0: rsub <= 3'd1;              // 地址已由rom_addr输出
                        3'd1: rsub <= 3'd2;              // flag_r 在此沿锁存
                        3'd2: begin                      // 按分支写入y值 (1120列)
                            we <= 1'b1;
                            wb_sel <= flag_r;            // 第一分支→ybuf, 第二→xbuf
                            waddr <= x_abs;
                            wdata <= y_rel;
                            flag_we <= 1'b1; flag_waddr <= x_abs; flag_wdata <= 1'b1;
                            rsub <= 3'd0;
                            rphase <= rphase + LIS_INC;
                            rcol <= rcol + 11'd1;
                            if (rcol == LIS_COLS - 1) render_busy <= 1'b0;
                        end
                    endcase
                end
                default: begin
                    // 示波器模式: 2周期/列 (发地址→存采样值)
                    case (rsub)
                        2'd0: rsub <= 3'd1;                          // 地址由scope_rd_addr输出
                        2'd1: begin
                            we <= 1'b1; wb_sel <= 1'b0; waddr <= rcol;
                            wdata <= {1'b0, scope_rd_data[11:4]};     // 12位→8位
                            rsub <= 3'd0;
                            rcol <= rcol + 10'd1;
                            if (rcol == WAVE_W - 1) render_busy <= 1'b0;
                        end
                    endcase
                end
                endcase
            end
        end
    end
    assign scope_rd_addr = sbase + rcol;
    // 波形模式: 提前1列取正弦值(1周期延迟对齐); 李萨如: 直接取当前相位
    wire [31:0] rphase_look   = rphase + col_inc;
    wire [31:0] rphase_b_look = rphase_look + lis_off;
    wire [31:0] rphase_lis_b  = rphase + lis_off;
    assign rom_addr   = lis_mode ? rphase[31:20] : rphase_look[31:20];
    assign rom_addr_b = lis_mode ? rphase_lis_b[31:20] : rphase_b_look[31:20];

    // ---- 显示绘制 ----
    wire [9:0] px = hcnt;
    wire [9:0] py = vcnt;
    wire in_wave_x = (hcnt >= X0) && (hcnt <= X1);
    wire in_wave_y = (vcnt >= Y0) && (vcnt <= Y1);

    wire signed [8:0] xv = {1'b0, xbuf_r} - 9'sd128;
    wire signed [9:0] y_plot_wave = YC - ((xv * AMP) >>> 7);

    // 相邻列纵向连线: 前前列的y值, 与当前列之间画竖线连接
    reg [8:0] xbuf_r2;
    always @(posedge clk_pix) xbuf_r2 <= xbuf_r;
    wire signed [8:0] xv2 = {1'b0, xbuf_r2} - 9'sd128;
    wire signed [9:0] y_plot_wave2 = YC - ((xv2 * AMP) >>> 7);
    wire [9:0] y_lo = (y_plot_wave < y_plot_wave2) ? y_plot_wave : y_plot_wave2;
    wire [9:0] y_hi = (y_plot_wave < y_plot_wave2) ? y_plot_wave2 : y_plot_wave;
    wire on_wave = !lis_mode && in_wave_x && in_wave_y &&
                   (py >= y_lo - 1) && (py <= y_hi + 1);

    // 李萨如: 缓冲按x索引存屏幕y偏移, 显示时查表画两个分支
    wire [9:0] lis_y1 = Y0 + {1'b0, ybuf_r};
    wire [9:0] lis_y2 = Y0 + {1'b0, xbuf_r};
    wire in_lis_x = (px >= XC - AMP - 1) && (px <= XC + AMP + 1);
    wire on_lis = lis_mode && in_wave_x && in_wave_y && in_lis_x && flag_disp &&
                  ((py >= lis_y1 - 1 && py <= lis_y1 + 1) ||
                   (py >= lis_y2 - 1 && py <= lis_y2 + 1));
    wire on_grid = in_wave_x && in_wave_y && ((py == YC) || (px == XC));
    wire on_border = (in_wave_x && (py == Y0 || py == Y1)) ||
                     (in_wave_y && (px == X0 || px == X1));

    // ---- 文字层 ----
    // 4行文字: y = 8..15, 24..31, 40..47, 56..63; 每行最多32字符, x从8开始
    wire [2:0] tline = (vcnt[5:3] - 3'd1) >> 1;      // 1→0, 3→1, 5→2, 7→3, 9→4
    wire [2:0] trow  = vcnt[2:0];
    wire [4:0] tcol  = (hcnt - 9'd8) >> 3;
    wire in_text = (vcnt >= 9'd8 && vcnt <= 9'd95) &&
                   (hcnt >= 9'd8 && hcnt < 9'd264) &&
                   ((vcnt[5:3] == 3'd1) || (vcnt[5:3] == 3'd3) ||
                    (vcnt[5:3] == 3'd5) || (vcnt[5:3] == 3'd7) ||
                    (vcnt[5:3] == 3'd9) || (vcnt[5:3] == 3'd11));

    // 字符码: 0-9数字, 10-35 A-Z, 36':', 37'.', 38'%', 39空格
    localparam C_A=6'd10, C_B=6'd11, C_C=6'd12, C_D=6'd13, C_E=6'd14, C_F=6'd15;
    localparam C_G=6'd16, C_H=6'd17, C_I=6'd18, C_J=6'd19, C_K=6'd20, C_L=6'd21;
    localparam C_M=6'd22, C_N=6'd23, C_O=6'd24, C_P=6'd25, C_Q=6'd26, C_R=6'd27;
    localparam C_S=6'd28, C_T=6'd29, C_U=6'd30, C_V=6'd31, C_W=6'd32, C_X=6'd33;
    localparam C_Y=6'd34, C_Z=6'd35;
    localparam C_COLON=6'd36, C_DOT=6'd37, C_PCT=6'd38, C_SP=6'd39;

    wire [31:0] bcd;
    bin2bcd u_bin2bcd (.bin(freq_hz), .bcd(bcd));

    reg [5:0] text [0:5][0:31];
    integer i, j;
    reg [3:0] f1, f2, f3, f4, f5, f6;
    reg mhz_m;
    always @(*) begin
        for (i = 0; i < 6; i = i + 1)
            for (j = 0; j < 32; j = j + 1)
                text[i][j] = C_SP;
        // ---- 标题/状态行 (y=72..79) ----
        if (playing_flag) begin
            text[4][4]=C_P; text[4][5]=C_L; text[4][6]=C_A; text[4][7]=C_Y;
            text[4][8]=C_I; text[4][9]=C_N; text[4][10]=C_G; text[4][11]=C_COLON;
            text[4][13]=C_S; text[4][14]=C_O; text[4][15]=C_N; text[4][16]=C_G;
            text[4][18] = song_flag ? 6'd2 : 6'd1;
        end else if (sweep_flag) begin
            text[4][4]=C_S; text[4][5]=C_W; text[4][6]=C_E; text[4][7]=C_E;
            text[4][8]=C_P; text[4][9]=C_I; text[4][10]=C_N; text[4][11]=C_G;
        end else begin
            text[4][4]=C_D; text[4][5]=C_D; text[4][6]=C_S; text[4][8]=C_S;
            text[4][9]=C_I; text[4][10]=C_G; text[4][11]=C_N; text[4][12]=C_A; text[4][13]=C_L;
            text[4][15]=C_G; text[4][16]=C_E; text[4][17]=C_N; text[4][18]=C_E;
            text[4][19]=C_R; text[4][20]=C_A; text[4][21]=C_T; text[4][22]=C_O; text[4][23]=C_R;
        end
        // ---- 第6行: 步进档位 (y=88..95) ----
        text[5][4]=C_S; text[5][5]=C_T; text[5][6]=C_E; text[5][7]=C_P; text[5][8]=C_COLON;
        case (step_sel)
            2'd0: begin text[5][10]=6'd1; text[5][11]=C_K; end
            2'd1: begin text[5][10]=6'd1; text[5][11]=6'd0; text[5][12]=C_K; end
            2'd2: begin text[5][10]=6'd1; text[5][11]=6'd0; text[5][12]=6'd0; text[5][13]=C_K; end
            default: begin text[5][10]=6'd1; text[5][11]=C_M; end
        endcase
        // ---- 频率字段 ----
        mhz_m = (freq_hz >= 24'd1_000_000);
        if (mhz_m) begin
            f1 = bcd[31:28]; f2 = bcd[27:24]; f3 = bcd[23:20]; f4 = bcd[19:16];
        end else begin
            f1 = bcd[27:24]; f2 = bcd[23:20]; f3 = bcd[19:16];
            f4 = bcd[15:12]; f5 = bcd[11:8];  f6 = bcd[7:4];
            if (f1 == 4'd0) f1 = 4'd15;
            if (f1 == 4'd15 && f2 == 4'd0) f2 = 4'd15;
        end
        if (scope_mode) begin
            // 示波器模式文字
            text[0][0]=C_S; text[0][1]=C_C; text[0][2]=C_O; text[0][3]=C_P;
            text[0][4]=C_E; text[0][6]=C_M; text[0][7]=C_O; text[0][8]=C_D; text[0][9]=C_E;
            text[0][11]=C_C; text[0][12]=C_H; text[0][13]=6'd6;
            text[1][0]=C_A; text[1][1]=C_D; text[1][2]=C_C; text[1][4]=6'd1; text[1][5]=6'd2;
            text[1][6]=C_B; text[1][7]=C_I; text[1][8]=C_T; text[1][10]=6'd4; text[1][11]=6'd6;
            text[1][12]=C_K; text[1][13]=C_S; text[1][14]=C_P; text[1][15]=C_S;
            text[2][0]=C_I; text[2][1]=C_N; text[2][2]=C_P; text[2][3]=C_U; text[2][4]=C_T;
            text[2][5]=C_COLON; text[2][7]=C_A; text[2][8]=C_N; text[2][9]=C_A;
            text[2][10]=C_L; text[2][11]=C_O; text[2][12]=C_G; text[2][14]=C_B;
            text[3][0]=C_L; text[3][1]=C_O; text[3][2]=C_O; text[3][3]=C_P;
            text[3][4]=C_COLON; text[3][6]=C_D; text[3][7]=C_A; text[3][8]=C_C;
            text[3][9]=C_SP; text[3][10]=6'd2; text[3][11]=C_SP; text[3][12]=C_A;
            text[3][13]=C_D; text[3][14]=C_C;
        end else if (!lis_mode) begin
            // L1: FREQ:xxx
            text[0][0] = C_F; text[0][1] = C_R; text[0][2] = C_E; text[0][3] = C_Q;
            text[0][4] = C_COLON;
            text[0][6] = (f1 == 4'd15) ? C_SP : f1;
            if (mhz_m) begin
                text[0][7] = C_DOT; text[0][8] = f2; text[0][9] = f3; text[0][10] = f4;
                text[0][12] = C_M; text[0][13] = C_H; text[0][14] = C_Z;
            end else begin
                text[0][7] = (f2 == 4'd15) ? C_SP : f2;
                text[0][8] = f3; text[0][9] = C_DOT; text[0][10] = f4;
                text[0][11] = f5; text[0][12] = f6;
                text[0][14] = C_K; text[0][15] = C_H; text[0][16] = C_Z;
            end
            // L2: WAVE:名称
            text[1][0] = C_W; text[1][1] = C_A; text[1][2] = C_V; text[1][3] = C_E;
            text[1][4] = C_COLON;
            case (wave_sel)
                2'd0: begin text[1][6]=C_S; text[1][7]=C_I; text[1][8]=C_N; text[1][9]=C_E; end
                2'd1: begin text[1][6]=C_S; text[1][7]=C_Q; text[1][8]=C_U; text[1][9]=C_A;
                            text[1][10]=C_R; text[1][11]=C_E; end
                2'd2: begin text[1][6]=C_T; text[1][7]=C_R; text[1][8]=C_I; text[1][9]=C_A;
                            text[1][10]=C_N; text[1][11]=C_G; text[1][12]=C_L; text[1][13]=C_E; end
                2'd3: begin text[1][6]=C_S; text[1][7]=C_A; text[1][8]=C_W; text[1][9]=C_T;
                            text[1][10]=C_O; text[1][11]=C_O; text[1][12]=C_T; text[1][13]=C_H; end
            endcase
            // L3: AMP:xxx%
            text[2][0] = C_A; text[2][1] = C_M; text[2][2] = C_P; text[2][3] = C_COLON;
            case (amp_sel)
                2'd0: begin text[2][6]=6'd2; text[2][7]=6'd5; end
                2'd1: begin text[2][6]=6'd5; text[2][7]=6'd0; end
                2'd2: begin text[2][6]=6'd7; text[2][7]=6'd5; end
                2'd3: begin text[2][6]=6'd1; text[2][7]=6'd0; text[2][8]=6'd0; end
            endcase
            text[2][10] = C_PCT;
            // L4: PHASE:xxx
            text[3][0] = C_P; text[3][1] = C_H; text[3][2] = C_A; text[3][3] = C_S;
            text[3][4] = C_E; text[3][5] = C_COLON;
            case (phase_sel)
                2'd0: text[3][7] = 6'd0;
                2'd1: begin text[3][7]=6'd9; text[3][8]=6'd0; end
                2'd2: begin text[3][7]=6'd1; text[3][8]=6'd8; text[3][9]=6'd0; end
                2'd3: begin text[3][7]=6'd2; text[3][8]=6'd7; text[3][9]=6'd0; end
            endcase
        end else begin
            // 李萨如模式文字
            text[0][0]=C_L; text[0][1]=C_I; text[0][2]=C_S; text[0][3]=C_S;
            text[0][4]=C_A; text[0][5]=C_J; text[0][6]=C_O; text[0][7]=C_U;
            text[0][8]=C_S; text[0][10]=6'd1; text[0][11]=C_COLON; text[0][12]=6'd1;
            text[1][0]=C_P; text[1][1]=C_H; text[1][2]=C_A; text[1][3]=C_S;
            text[1][4]=C_E; text[1][5]=C_COLON;
            case (phase_sel)
                2'd0: text[1][7] = 6'd0;
                2'd1: begin text[1][7]=6'd9; text[1][8]=6'd0; end
                2'd2: begin text[1][7]=6'd1; text[1][8]=6'd8; text[1][9]=6'd0; end
                2'd3: begin text[1][7]=6'd2; text[1][8]=6'd7; text[1][9]=6'd0; end
            endcase
            // L3: 频率
            text[2][0]=C_F; text[2][1]=C_R; text[2][2]=C_E; text[2][3]=C_Q;
            text[2][4]=C_COLON;
            text[2][6] = (f1 == 4'd15) ? C_SP : f1;
            if (mhz_m) begin
                text[2][7]=C_DOT; text[2][8]=f2; text[2][9]=f3; text[2][10]=f4;
                text[2][12]=C_M; text[2][13]=C_H; text[2][14]=C_Z;
            end else begin
                text[2][7] = (f2 == 4'd15) ? C_SP : f2;
                text[2][8]=f3; text[2][9]=C_DOT; text[2][10]=f4;
                text[2][11]=f5; text[2][12]=f6;
                text[2][14]=C_K; text[2][15]=C_H; text[2][16]=C_Z;
            end
            text[3][0]=C_W; text[3][1]=C_A; text[3][2]=C_V; text[3][3]=C_E;
            text[3][4]=C_COLON; text[3][5]=C_S; text[3][6]=C_I; text[3][7]=C_N; text[3][8]=C_E;
        end
    end

    // ---- 8x8 字库 ----
    function [7:0] font_byte;
        input [5:0] code;
        input [2:0] row;
        reg [63:0] bm;
        begin
            case (code)
                6'd0:  bm = 64'h003C666E7666663C;
                6'd1:  bm = 64'h001838181818187E;
                6'd2:  bm = 64'h003C66060C18307E;
                6'd3:  bm = 64'h003C66061C06663C;
                6'd4:  bm = 64'h000C1C3C6C7E0C0C;
                6'd5:  bm = 64'h007E607C0606663C;
                6'd6:  bm = 64'h001C30607C66663C;
                6'd7:  bm = 64'h007E060C18303030;
                6'd8:  bm = 64'h003C66663C66663C;
                6'd9:  bm = 64'h003C66663E060C38;
                C_A:   bm = 64'h00183C66667E6666;
                C_B:   bm = 64'h007C66667C66667C;
                C_C:   bm = 64'h003C66606060663C;
                C_D:   bm = 64'h00786C6666666C78;
                C_E:   bm = 64'h007E60607C60607E;
                C_F:   bm = 64'h007E60607C606060;
                C_G:   bm = 64'h003C66606E66663C;
                C_H:   bm = 64'h006666667E666666;
                C_I:   bm = 64'h007E18181818187E;
                C_J:   bm = 64'h001E0C0C0C0C6C38;
                C_K:   bm = 64'h00666C7870786C66;
                C_L:   bm = 64'h006060606060607E;
                C_M:   bm = 64'h00667E7E66666666;
                C_N:   bm = 64'h0066767E7E6E6666;
                C_O:   bm = 64'h003C66666666663C;
                C_P:   bm = 64'h007C66667C606060;
                C_Q:   bm = 64'h003C6666666C663E;
                C_R:   bm = 64'h007C66667C786C66;
                C_S:   bm = 64'h003C66603C06663C;
                C_T:   bm = 64'h007E181818181818;
                C_U:   bm = 64'h006666666666663C;
                C_V:   bm = 64'h0066666666663C18;
                C_W:   bm = 64'h00666666667E7E66;
                C_X:   bm = 64'h0066663C183C6666;
                C_Y:   bm = 64'h0066663C18181818;
                C_Z:   bm = 64'h007E060C1830607E;
                C_COLON: bm = 64'h0000181800181800;
                C_DOT:   bm = 64'h0000000000001818;
                C_PCT:   bm = 64'h0062660C18306646;
                default: bm = 64'h0000000000000000;    // 空格等
            endcase
            font_byte = bm[63 - row*8 -: 8];
        end
    endfunction

    wire [5:0] char_code = text[tline][tcol];
    wire [7:0] fbyte = font_byte(char_code, trow);
    wire on_text = in_text && fbyte[7 - hcnt[2:0]];

    // ---- 像素输出 ----
    always @(posedge clk_pix or negedge rst_n) begin
        if (!rst_n) begin
            raddr <= 10'd0;
            vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;
            hsync <= 1'b1; vsync <= 1'b1;
        end else begin
            raddr <= (hcnt >= X0 && hcnt <= X1) ? (hcnt - X0) : 10'd0;
            if (on_text) begin
                vga_r <= 4'hF; vga_g <= 4'hF; vga_b <= 4'hF;   // 文字: 白
            end else if (on_lis) begin
                vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'hF;   // 李萨如: 青
            end else if (on_wave) begin
                // 波形颜色随类型: 正弦绿 方波黄 三角青 锯齿红
                case (wave_sel)
                    2'd0: begin vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'h0; end
                    2'd1: begin vga_r <= 4'hF; vga_g <= 4'hF; vga_b <= 4'h0; end
                    2'd2: begin vga_r <= 4'h0; vga_g <= 4'hF; vga_b <= 4'hF; end
                    default: begin vga_r <= 4'hF; vga_g <= 4'h0; vga_b <= 4'h0; end
                endcase
            end else if (on_grid) begin
                vga_r <= 4'h2; vga_g <= 4'h2; vga_b <= 4'h2;   // 网格线: 暗灰
            end else if (on_border) begin
                vga_r <= 4'h5; vga_g <= 4'h5; vga_b <= 4'h5;   // 边框: 灰
            end else begin
                vga_r <= 4'h0; vga_g <= 4'h0; vga_b <= 4'h0;
            end
            hsync <= ~((hcnt >= H_ACT + H_FP) && (hcnt < H_ACT + H_FP + H_SYNC));
            vsync <= ~((vcnt >= V_ACT + V_FP) && (vcnt < V_ACT + V_FP + V_SYNC));
        end
    end
endmodule
