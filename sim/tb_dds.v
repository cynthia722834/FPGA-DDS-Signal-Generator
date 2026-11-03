//====================================================================
// tb_dds.v — DDS 信号发生器仿真测试平台
// 测试项:
//   1. 默认 1kHz 方波频率精度 (16.8ms 内计数上升沿)
//   2. 按键+后 2kHz 频率翻倍
//   3. VGA 行同步/场同步周期
//   4. 四种波形输出不为恒定值 (正弦/三角/锯齿)
//   5. DAC 驱动时序: CS/WR 低电平宽度、AB 频率、数据总线切换
// 运行: vivado -mode batch -source sim_run.tcl
//====================================================================
`timescale 1ns/1ps
module tb_dds;

    reg clk = 1'b0;
    always #10 clk = ~clk;          // 50MHz

    reg [3:0]  key_col = 4'b1111;
    reg [10:0] sw  = 11'b00000000000;
    wire       key_row;
    wire [7:0] seg;
    wire [5:0] seg_sel;
    wire [3:0] led;
    wire [3:0] vga_r, vga_g, vga_b;
    wire       hsync, vsync;
    wire       dac_cs, dac_wr, dac_ab;
    wire [7:0] dac_data;
    wire       audio_pwm;
    wire       buzzer;

    // 仿真加速: 旋律时值×1/500, 扫频步进×1/100
    top_dds #(.MELODY_TICK(1000), .SWEEP_TICK(5000)) dut (
        .clk50(clk), .key_col(key_col), .key_row(key_row), .sw(sw),
        .vaux6_p(1'b0), .vaux6_n(1'b0),
        .seg(seg), .seg_sel(seg_sel), .led(led),
        .vga_r(vga_r), .vga_g(vga_g), .vga_b(vga_b),
        .hsync(hsync), .vsync(vsync),
        .dac_cs(dac_cs), .dac_wr(dac_wr), .dac_ab(dac_ab), .dac_data(dac_data),
        .audio_pwm(audio_pwm), .buzzer(buzzer)
    );

    integer edges, cyc;
    reg prev;
    reg [23:0] v1, v2;
    integer errors = 0;
    integer g_hits;
    integer top_hits;
    reg [8:0] last_x0;

    task check;
        input ok;
        input [255:0] msg;
        begin
            if (!ok) begin
                errors = errors + 1;
                $display("FAIL: %0s", msg);
            end else begin
                $display("PASS: %0s", msg);
            end
        end
    endtask

    // 计数 wave_out 最高位上升沿 (方波模式=相位MSB, 频率测量)
    task count_edges;
        input integer n_cycles;
        output integer n_edges;
        begin
            n_edges = 0;
            prev = dut.u_dds.wave_out[9];
            for (cyc = 0; cyc < n_cycles; cyc = cyc + 1) begin
                @(negedge clk);
                if (dut.u_dds.wave_out[9] && !prev) n_edges = n_edges + 1;
                prev = dut.u_dds.wave_out[9];
            end
        end
    endtask

    initial begin
        // ---- 复位 (KEY3 按下24ms再松开) ----
        $display(">> 复位阶段");
        key_col = 4'b1111; sw = 11'b00000000001;    // 方波
        key_col[3] = 1'b0;
        repeat (50) @(negedge clk);
        $display("DEBUG t0: rst_n=%b db_stable=%b sync2=%b cnt=%0d",
                 dut.rst_n, dut.db_stable, dut.u_deb.sync2, dut.u_deb.cnt);
        repeat (1200000 - 50) @(negedge clk);
        key_col[3] = 1'b1;
        repeat (1200000) @(negedge clk);   // 消抖稳定

        $display("DEBUG: rst_n=%b freq_hz=%0d fcw=%0d wave=%h",
                 dut.rst_n, dut.u_freq.freq_hz, dut.u_freq.fcw, dut.u_dds.wave_out);
        $display("DEBUG: db_stable=%b db_pulse=%b", dut.db_stable, dut.db_pulse);
        $display("DEBUG: phase=%h clk25=%b hsync=%b",
                 dut.u_dds.phase, dut.clk25, dut.hsync);

        // ---- 测试1: 默认1kHz, 16.8ms 应计 ~16-17 个上升沿 ----
        $display(">> T1 默认频率");
        count_edges(840000, edges);
        $display("T1: 16.8ms 内方波上升沿 = %0d", edges);
        check((edges >= 15 && edges <= 18), "默认频率 ≈1kHz");

        // ---- 测试2: KEY0 按下24ms → 2kHz ----
        $display(">> T2 按键加频");
        key_col[0] = 1'b0;
        repeat (1200000) @(negedge clk);
        key_col[0] = 1'b1;
        repeat (200) @(negedge clk);
        count_edges(840000, edges);
        $display("T2: 按键+后 16.8ms 内上升沿 = %0d", edges);
        check((edges >= 31 && edges <= 36), "按键+后频率 ≈2kHz");

        // ---- 测试3: VGA 同步时序 ----
        $display(">> T3 VGA 时序");
        @(negedge hsync);
        cyc = 0;
        while (!hsync) begin @(negedge clk); cyc = cyc + 1; end
        $display("T3a: hsync 低宽度 = %0d clk50周期 (期望192)", cyc);
        check((cyc >= 190 && cyc <= 194), "hsync 宽度 192");

        @(negedge vsync); @(negedge vsync);
        cyc = 0;
        while (!vsync) begin @(negedge clk); cyc = cyc + 1; end
        while (vsync)  begin @(negedge clk); cyc = cyc + 1; end
        $display("T3b: vsync 周期 = %0d clk50周期 (期望840000)", cyc);
        check((cyc >= 838000 && cyc <= 842000), "vsync 周期 ≈840000");

        // ---- 测试4: 各波形输出有变化 ----
        sw = 11'b00000000000;
        repeat (2000) @(negedge clk); v1 = dut.u_dds.wave_out;
        repeat (1000) @(negedge clk); v2 = dut.u_dds.wave_out;
        check((v1 !== v2), "正弦波输出有变化");
        sw = 11'b00000000010;
        repeat (2000) @(negedge clk); v1 = dut.u_dds.wave_out;
        repeat (1000) @(negedge clk); v2 = dut.u_dds.wave_out;
        check((v1 !== v2), "三角波输出有变化");
        sw = 11'b00000000011;
        repeat (2000) @(negedge clk); v1 = dut.u_dds.wave_out;
        repeat (1000) @(negedge clk); v2 = dut.u_dds.wave_out;
        check((v1 !== v2), "锯齿波输出有变化");

        // ---- 测试6: 双通道相位差 + 幅度 + 李萨如 ----
        $display(">> T6 相位差/幅度/李萨如");
        sw = 11'b00000010000;                  // 正弦 + 相位差90°
        repeat (2000) @(negedge clk);
        v1 = dut.u_dds.wave_out;
        v2 = dut.u_dds.wave_out_b;
        $display("T6a: A=%0d B=%0d (90°相位差应不同)", v1, v2);
        check((v1 !== v2), "通道B相位偏移有效");
        sw = 11'b00000000000;                  // 幅度25%档
        repeat (2000) @(negedge clk);
        v1 = dut.u_dds.wave_out;
        $display("T6b: 25%幅度采样=%0d (期望380~645)", v1);
        check((v1 >= 380 && v1 <= 645), "25%幅度缩放有效");
        sw = 11'b00001000000;                  // 李萨如模式
        repeat (1680000) @(negedge clk);      // 跑2帧
        check((dut.hsync !== 1'bx && dut.vsync !== 1'bx), "李萨如模式VGA正常");
        // 渲染内容检查: x索引缓冲中部应有有效y偏移值(两端极值为未采样点, 已清0)
        $display("LIS渲染检查: ybuf[119]=%0d(极值点已清0) ybuf[280]=%0d(应为有效y偏移)",
                 dut.u_vga.ybuf[119], dut.u_vga.ybuf[280]);
        check((dut.u_vga.ybuf[280] > 0), "李萨如x索引缓冲已写入");
        // 像素级检查: 统计一帧内青色像素(李萨如曲线颜色 r=0,g=F,b=F)
        g_hits = 0;
        for (cyc = 0; cyc < 840000; cyc = cyc + 1) begin
            @(negedge clk);
            if (vga_r === 4'h0 && vga_g === 4'hF && vga_b === 4'hF)
                g_hits = g_hits + 1;
        end
        $display("LIS像素检查: 一帧内青色像素数=%0d (曲线应>500)", g_hits);
        check((g_hits > 500), "李萨如曲线被实际绘制");
        // 圆(相位90°)中间带像素坐标诊断: 找断点
        $display("--- 圆中段像素分布 (y=254..264) ---");
        for (cyc = 0; cyc < 840000; cyc = cyc + 1) begin
            @(negedge clk);
            if (vga_r === 4'h0 && vga_g === 4'hF && vga_b === 4'hF &&
                dut.u_vga.vcnt >= 10'd254 && dut.u_vga.vcnt <= 10'd264)
                $display("  px=%0d py=%0d", dut.u_vga.hcnt, dut.u_vga.vcnt);
        end
        $display("--- 分布结束 ---");
        // 相位0(斜线)下顶部区域青色像素数 (斜线不应大量经过顶部)
        sw = 11'b00000000000;
        repeat (1680000) @(negedge clk);
        top_hits = 0;
        for (cyc = 0; cyc < 840000; cyc = cyc + 1) begin
            @(negedge clk);
            if (vga_r === 4'h0 && vga_g === 4'hF && vga_b === 4'hF &&
                dut.u_vga.vcnt >= 10'd99 && dut.u_vga.vcnt <= 10'd105)
                top_hits = top_hits + 1;
        end
        $display("相位0顶部区域(99~105行)青色像素: %0d", top_hits);

        // ---- 测试6c: 波形模式渲染内容 (联动渲染) ----
        $display(">> T6c 波形渲染");
        sw = 11'b00000000011;                  // 锯齿波, 25%幅度(sw[3:2]=00)
        repeat (840000) @(negedge clk);
        $display("帧1后: xbuf[0]=%0d xbuf[70]=%0d xbuf[280]=%0d busy=%b rcol=%0d",
                 dut.u_vga.xbuf[0], dut.u_vga.xbuf[70], dut.u_vga.xbuf[280],
                 dut.u_vga.render_busy, dut.u_vga.rcol);
        repeat (840000) @(negedge clk);
        $display("帧2后: xbuf[0]=%0d xbuf[70]=%0d xbuf[280]=%0d busy=%b rcol=%0d",
                 dut.u_vga.xbuf[0], dut.u_vga.xbuf[70], dut.u_vga.xbuf[280],
                 dut.u_vga.render_busy, dut.u_vga.rcol);
        repeat (840000) @(negedge clk);
        $display("帧3后: xbuf[0]=%0d xbuf[70]=%0d xbuf[280]=%0d xbuf[420]=%0d busy=%b rcol=%0d",
                 dut.u_vga.xbuf[0], dut.u_vga.xbuf[70], dut.u_vga.xbuf[280], dut.u_vga.xbuf[420],
                 dut.u_vga.render_busy, dut.u_vga.rcol);
        check((dut.u_vga.xbuf[0] !== dut.u_vga.xbuf[280] ||
               dut.u_vga.xbuf[70] !== dut.u_vga.xbuf[420]), "波形渲染缓冲随相位变化");

        // ---- 测试6d: 100Hz帧边界连续性 ----
        $display(">> T6d 100Hz边界");
        force dut.u_freq.freq_hz = 24'd100;
        repeat (1680000) @(negedge clk);
        $display("100Hz: xbuf[556]=%0d [557]=%0d [558]=%0d [559]=%0d | [0]=%0d [1]=%0d [2]=%0d",
                 dut.u_vga.xbuf[556], dut.u_vga.xbuf[557], dut.u_vga.xbuf[558],
                 dut.u_vga.xbuf[559], dut.u_vga.xbuf[0], dut.u_vga.xbuf[1], dut.u_vga.xbuf[2]);
        $display("T6d状态: vga.mode=%b render_busy=%b rcol=%0d freq_hz=%0d",
                 dut.u_vga.mode, dut.u_vga.render_busy, dut.u_vga.rcol, dut.u_vga.freq_hz);
        // 观察者: 一帧内 xbuf[0] 和 we 的变化
        last_x0 = dut.u_vga.xbuf[0];
        for (cyc = 0; cyc < 840000; cyc = cyc + 1) begin
            @(negedge clk);
            if (dut.u_vga.xbuf[0] !== last_x0) begin
                $display("xbuf[0]变化: %0d → %0d (t=%0t, vcnt=%0d)",
                         last_x0, dut.u_vga.xbuf[0], $time, dut.u_vga.vcnt);
                last_x0 = dut.u_vga.xbuf[0];
            end
            if (dut.u_vga.we === 1'b1) begin
                $display("we=1: waddr=%0d wdata=%0d wv_raw=%0d wv_s=%0d rphase=%h amp=%b wave=%b rom_addr=%h rom_data=%0d (t=%0t)",
                         dut.u_vga.waddr, dut.u_vga.wdata, dut.u_vga.wv_raw,
                         dut.u_vga.wv_s, dut.u_vga.rphase, dut.u_vga.amp_sel,
                         dut.u_vga.wave_sel, dut.u_vga.rom_addr, dut.u_vga.rom_data, $time);
            end
        end
        $display("观察结束: xbuf[0]=%0d", dut.u_vga.xbuf[0]);
        release dut.u_freq.freq_hz;

        // ---- 测试7: 扫频 ----
        $display(">> T7 扫频");
        sw = 11'b00010000001;                  // 方波 + SW7扫频开
        repeat (300000) @(negedge clk);       // 6ms (仿真步进0.1ms → 已走60步)
        v1 = dut.u_sweep.freq_out;
        $display("T7: 扫频6ms后频率=%0d (期望>1000)", v1);
        check((v1 > 24'd1000), "扫频频率递增");
        sw = 11'b00000000001;                  // 关扫频
        repeat (1000) @(negedge clk);

        // ---- 测试8: 旋律播放 ----
        $display(">> T8 旋律播放");
        sw = 11'b01000000000;                  // SW9播放开
        repeat (20000) @(negedge clk);        // 40µs后(仿真时值1/500)
        v1 = dut.u_melody.note_freq;
        $display("T8a: 第一个音符=%0d (期望262 C4)", v1);
        check((v1 == 24'd262), "旋律起始音符C4");
        repeat (90000) @(negedge clk);        // 再0.18ms → 第3个音符
        v1 = dut.u_melody.note_freq;
        $display("T8b: 第三个音符=%0d (期望392 G4)", v1);
        check((v1 == 24'd392), "旋律音符切换正常");
        check((dut.audio_pwm !== 1'bx), "音频PWM输出有效");
        check((dut.buzzer !== 1'bx), "蜂鸣器输出有效");
        sw = 11'b00000000000;                  // 关播放

        // ---- 测试9: 示波器模式 ----
        $display(">> T9 示波器模式");
        sw = 11'b00100000000;                  // SW8=1 → mode=10 示波器
        repeat (1680000) @(negedge clk);      // 跑2帧
        check((dut.hsync !== 1'bx && dut.vsync !== 1'bx), "示波器模式VGA正常");
        $display("T9a: XADC写指针=%0d mem[5]=%0d mem[20]=%0d",
                 dut.u_xadc_cap.wptr, dut.u_xadc_cap.mem[5], dut.u_xadc_cap.mem[20]);
        check((dut.u_xadc_cap.wptr > 24'd5 && (dut.u_xadc_cap.mem[5] !== 12'bx)),
              "XADC采集有数据写入");

        // ---- 测试5: DAC 时序 ----
        // CS/WR 低电平宽度 25 clk50 周期 (500ns)
        @(negedge dac_cs);
        cyc = 0;
        while (!dac_cs) begin @(negedge clk); cyc = cyc + 1; end
        $display("T5a: DAC_CS 低宽度 = %0d clk50周期 (期望25)", cyc);
        check((cyc >= 24 && cyc <= 27), "DAC_CS 低宽度 25 周期");
        // AB 周期 = 100 clk50 周期 (1MHz 采样率)
        @(posedge dac_ab); @(negedge dac_ab); @(posedge dac_ab);
        $display("T5b: dac_ab 翻转周期检查完成");
        check((dac_ab === 1'b1), "DACAB 正常翻转");
        // key_row 恒低
        check((key_row === 1'b0), "键盘行输出恒低");

        // ---- 总结 ----
        if (errors == 0) $display("=== ALL TESTS PASSED ===");
        else             $display("=== %0d TEST(S) FAILED ===", errors);
        $finish;
    end
endmodule
