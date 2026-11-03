`timescale 1ns/1ps
//====================================================================
// top_dds.v — DDS 信号发生器顶层 (硬木课堂 ACE1-AR7, XC7A35TFTG256-2)
//
// 功能:
//   * 输出 正弦/方波/三角波/锯齿波 (SW1:SW0 选择)
//   * 矩阵键盘第一行 4 键: KEY0+ KEY1- KEY2步进 KEY3复位
//   * 6位数码管实时显示频率 (kHz/MHz 自动切换, LED 指示单位)
//   * VGA 显示: 波形模式(示波器风格)/李萨如模式(SW6 切换), 带文字参数栏
//   * 板载 TLC7528 双通道 DAC: A=主波形, B=相位偏移波形(相位差 SW5:SW4)
//   * 幅度调节 SW3:SW2 (25%/50%/75%/100%)
//
// 拨码开关总表:
//   SW1:0 波形 | SW3:2 幅度 | SW5:4 相位差(0/90/180/270) | SW6 显示模式
//====================================================================
module top_dds #(
    parameter MELODY_TICK = 500000,   // 旋律时值单位周期数(仿真可调小)
    parameter SWEEP_TICK  = 500000    // 扫频步进周期数(仿真可调小)
)(
    input  wire        clk50,        // 50MHz 系统时钟
    input  wire [3:0]  key_col,      // 矩阵键盘列输入(第一行4键, 按下为低)
    output wire        key_row,      // 矩阵键盘行输出(恒为低, 选中第一行)
    input  wire [10:0] sw,           // 拨码开关 (SW10=歌曲切换)
    input  wire        vaux6_p,      // XADC 通道6 正输入(±5V模拟输入B, 引脚C3)
    input  wire        vaux6_n,      // XADC 通道6 负输入(引脚C2, 使用时接地)
    output wire [7:0]  seg,          // 数码管段码 {dp,g,f,e,d,c,b,a}
    output wire [5:0]  seg_sel,      // 数码管位选 (低有效)
    output wire [3:0]  led,          // [3]kHz [2]MHz [1:0]步进档位
    output wire [3:0]  vga_r, vga_g, vga_b,
    output wire        hsync, vsync,
    output wire        dac_cs, dac_wr, dac_ab,
    output wire [7:0]  dac_data,
    output wire        audio_pwm,    // 音频输出(板载3.5mm口, PWM驱动)
    output wire        buzzer        // 无源蜂鸣器(引脚L2, 播放旋律时发声)
);
    // 矩阵键盘: 第一行恒输出低电平, 4 列即 4 个按键(列输入内部上拉)
    assign key_row = 1'b0;

    // ---- 按键消抖 (低有效按键) ----
    wire [3:0] db_stable, db_pulse;
    debounce #(.WIDTH(4)) u_deb (
        .clk(clk50),
        .rst_n(1'b1),
        .btn_in(key_col),
        .btn_stable(db_stable),
        .btn_pulse(db_pulse)
    );
    wire rst_n      = db_stable[3];         // KEY3 复位
    wire btn_up     = db_pulse[0];          // KEY0 频率+
    wire btn_down   = db_pulse[1];          // KEY1 频率-
    wire btn_step   = db_pulse[2];          // KEY2 步进切换

    // ---- 25MHz 像素时钟 (翻转寄存器 + BUFG 全局时钟网络) ----
    // 直接使用翻转寄存器的输出做时钟会导致巨大时钟歪斜, 必须过 BUFG
    reg clk25_raw = 1'b0;
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) clk25_raw <= 1'b0;
        else        clk25_raw <= ~clk25_raw;
    end
    wire clk25;
    BUFG u_bufg_clk25 (.I(clk25_raw), .O(clk25));

    // ---- 频率控制 ----
    wire [23:0] freq_hz;
    wire [1:0]  step_sel;
    wire [31:0] fcw;
    freq_ctrl u_freq (
        .clk(clk50), .rst_n(rst_n),
        .btn_up(btn_up), .btn_down(btn_down), .btn_step(btn_step),
        .up_hold(~db_stable[0]), .down_hold(~db_stable[1]),
        .freq_hz(freq_hz), .step_sel(step_sel), .fcw(fcw)
    );

    // ---- 两块正弦查找表 ----
    // rom1: A口=通道A正弦, B口=VGA渲染(波形/李萨如X)
    // rom2: A口=通道B正弦(相位偏移), B口=VGA渲染(李萨如Y)
    wire [11:0] rom1_a_addr, rom1_b_addr, rom2_a_addr, rom2_b_addr;
    wire [7:0]  rom1_a_data, rom1_b_data, rom2_a_data, rom2_b_data;
    wave_rom u_rom1 (
        .clk_a(clk50), .addr_a(rom1_a_addr), .dout_a(rom1_a_data),
        .clk_b(clk25), .addr_b(rom1_b_addr), .dout_b(rom1_b_data)
    );
    wave_rom u_rom2 (
        .clk_a(clk50), .addr_a(rom2_a_addr), .dout_a(rom2_a_data),
        .clk_b(clk25), .addr_b(rom2_b_addr), .dout_b(rom2_b_data)
    );

    // ---- 拨码开关同步 (异步输入 → clk50 两级同步) ----
    reg [10:0] sw_s1 = 11'd0, sw_s2 = 11'd0;
    always @(posedge clk50) begin
        sw_s1 <= sw;
        sw_s2 <= sw_s1;
    end
    wire [10:0] sw_s = sw_s2;

    // ---- 开关功能分配 ----
    wire [1:0] wave_sel   = sw_s[1:0];
    wire [1:0] amp_sel    = sw_s[3:2];
    wire [1:0] phase_sel  = sw_s[5:4];
    wire [1:0] mode       = {sw_s[8], sw_s[6]};  // 00波形 01李萨如 1x示波器
    wire       sweep_en   = sw_s[7];   // 扫频
    wire       play_en    = sw_s[9];   // 旋律播放
    wire [31:0] phase_offset = {phase_sel, 30'b0};   // 90°步进

    // ---- 扫频控制器 ----
    wire [23:0] sweep_step = (step_sel == 2'd0) ? 24'd1000 :
                              (step_sel == 2'd1) ? 24'd10000 :
                              (step_sel == 2'd2) ? 24'd100000 : 24'd1000000;
    wire [23:0] sweep_freq;
    sweep_ctrl #(.STEP_TICKS(SWEEP_TICK)) u_sweep (
        .clk(clk50), .rst_n(rst_n),
        .sweep_en(sweep_en),
        .step_hz(sweep_step),
        .f_min(24'd100), .f_max(24'd9_999_999),
        .init_freq(24'd1000),
        .freq_out(sweep_freq)
    );

    // ---- 旋律播放器 ----
    wire [23:0] note_freq;
    wire        playing, note_on;
    wire        song_sel = sw_s[10];    // SW10: 0=小星星 1=生日快乐
    melody_player #(.DUR_UNIT(MELODY_TICK)) u_melody (
        .clk(clk50), .rst_n(rst_n),
        .play_en(play_en),
        .song_sel(song_sel),
        .note_freq(note_freq),
        .playing(playing),
        .note_on(note_on)
    );

    // ---- 有效频率选择: 播放 > 扫频 > 手动 ----
    wire [23:0] active_freq = playing ? note_freq :
                               (sweep_en ? sweep_freq : freq_hz);
    wire [1:0]  active_wave = playing ? 2'd0 : wave_sel;
    // 通用频率→相位增量 (fcw = f * 2^32 / 50MHz)
    // 除法器输出打一拍: 切断长组合路径(频率选择→除法→累加器)
    wire [31:0] active_fcw = (active_freq * 64'd4294967296) / 64'd50_000_000;
    reg  [31:0] fcw_reg = 32'd0;
    always @(posedge clk50 or negedge rst_n) begin
        if (!rst_n) fcw_reg <= 32'd0;
        else        fcw_reg <= active_fcw;
    end

    // ---- DDS 内核 (双通道) ----
    wire [9:0] wave_out, wave_out_b;
    wire dds_square;
    dds_core u_dds (
        .clk(clk50), .rst_n(rst_n),
        .fcw(fcw_reg), .phase_offset(phase_offset),
        .wave_sel(active_wave), .amp_sel(amp_sel),
        .wave_out(wave_out), .wave_out_b(wave_out_b),
        .square_out(dds_square),
        .rom_addr(rom1_a_addr), .rom_data(rom1_a_data),
        .rom_addr_b(rom2_a_addr), .rom_data_b(rom2_a_data)
    );

    // ---- 蜂鸣器: 播放时输出与音符同频方波 (取DDS相位最高位, 免除法器) ----
    // 非播放时按键提示音(不同键不同音调)
    wire key_beep_sig;
    key_beep u_key_beep (
        .clk(clk50), .rst_n(rst_n),
        .btn_up(btn_up), .btn_down(btn_down), .btn_step(btn_step),
        .playing(playing),
        .beep_out(key_beep_sig)
    );
    assign buzzer = (playing && note_on) ? dds_square : key_beep_sig;

    // ---- 音频输出 (Sigma-Delta PWM → 板载3.5mm音频口) ----
    sd_pwm u_audio (
        .clk(clk50), .rst_n(rst_n),
        .sample(wave_out),
        .pwm_out(audio_pwm)
    );

    // ---- 数码管频率显示 (共阴: 段码高有效, 位选低有效) ----
    wire led_mhz, led_khz;
    seg7_display #(
        .SEG_ACTIVE_LOW(1'b0),
        .SEL_ACTIVE_LOW(1'b1)
    ) u_seg (
        .clk(clk50), .rst_n(rst_n),
        .freq_hz(active_freq),
        .seg(seg), .seg_sel(seg_sel),
        .led_mhz(led_mhz), .led_khz(led_khz)
    );

    // ---- XADC 示波器采集 ----
    wire [9:0]  scope_wptr, scope_rd_addr;
    wire [11:0] scope_rd_data;
    xadc_cap u_xadc_cap (
        .clk50(clk50), .rst_n(rst_n),
        .vaux6_p(vaux6_p),
        .vaux6_n(vaux6_n),
        .clk_pix(clk25),
        .rd_addr(scope_rd_addr),
        .rd_data(scope_rd_data),
        .wptr(scope_wptr)
    );

    // ---- VGA 显示 (波形/李萨如/示波器 + 文字) ----
    // clk50→clk25 跨时钟域两级同步 (消除时序违例, 显示晚2像素无影响)
    reg [23:0] vfreq_s1 = 24'd0, vfreq_s2 = 24'd0;
    reg [31:0] vfcw_s1  = 32'd0, vfcw_s2  = 32'd0;
    reg [1:0]  vmode_s1 = 2'd0,  vmode_s2 = 2'd0;
    reg [1:0]  vwave_s1 = 2'd0,  vwave_s2 = 2'd0;
    reg [1:0]  vamp_s1  = 2'd0,  vamp_s2  = 2'd0;
    reg [1:0]  vphase_s1 = 2'd0, vphase_s2 = 2'd0;
    reg [1:0]  vstep_s1 = 2'd0,  vstep_s2 = 2'd0;
    reg        vplay_s1 = 1'b0,  vplay_s2 = 1'b0;
    reg        vswp_s1  = 1'b0,  vswp_s2  = 1'b0;
    reg        vsong_s1 = 1'b0,  vsong_s2 = 1'b0;
    always @(posedge clk25) begin
        vfreq_s1 <= active_freq; vfreq_s2 <= vfreq_s1;
        vfcw_s1  <= fcw_reg;    vfcw_s2  <= vfcw_s1;
        vmode_s1 <= mode;       vmode_s2 <= vmode_s1;
        vwave_s1 <= wave_sel;   vwave_s2 <= vwave_s1;
        vamp_s1  <= amp_sel;    vamp_s2  <= vamp_s1;
        vphase_s1 <= phase_sel; vphase_s2 <= vphase_s1;
        vstep_s1 <= step_sel;   vstep_s2 <= vstep_s1;
        vplay_s1 <= playing;    vplay_s2 <= vplay_s1;
        vswp_s1  <= sweep_en;   vswp_s2  <= vswp_s1;
        vsong_s1 <= song_sel;   vsong_s2 <= vsong_s1;
    end
    vga_waveform u_vga (
        .clk_pix(clk25), .rst_n(rst_n),
        .wave_sel(vwave_s2),
        .mode(vmode_s2),
        .amp_sel(vamp_s2),
        .phase_sel(vphase_s2),
        .freq_hz(vfreq_s2),
        .fcw(vfcw_s2),
        .step_sel(vstep_s2),
        .playing_flag(vplay_s2),
        .sweep_flag(vswp_s2),
        .song_flag(vsong_s2),
        .rom_addr(rom1_b_addr), .rom_data(rom1_b_data),
        .rom_addr_b(rom2_b_addr), .rom_data_b(rom2_b_data),
        .scope_wptr(scope_wptr),
        .scope_rd_addr(scope_rd_addr),
        .scope_rd_data(scope_rd_data),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .hsync(hsync), .vsync(vsync)
    );

    // ---- 板载 TLC7528 双通道 DAC: A=主波形, B=相位偏移波形 ----
    tlc7528_drv u_dac (
        .clk(clk50), .rst_n(rst_n),
        .data_a(wave_out[9:2]),
        .data_b(wave_out_b[9:2]),
        .dac_cs(dac_cs), .dac_wr(dac_wr), .dac_ab(dac_ab),
        .dac_data(dac_data)
    );

    // ---- LED 指示 ----
    assign led = {led_khz, led_mhz, step_sel};

    // ---- STARTUPE2: 打通JTAG间接烧写板载Flash的通道 ----
    startupe2_inst u_startupe2 ();
endmodule
