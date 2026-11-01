// ---------------------------------------------------------------
// d5m_system_top.v   DE2-115 + Terasic TRDB-D5M camera
//
//  D5M -> d5m_capture -> pixel_framer -> underwater_enhance -+-> frame_buffer -> vga_display -> MONITOR
//                                                                 |
//                                                                 +-> grayscale_threshold -> median x2
//                                                -> blob_counter -> count_register
//                                                -> binary_to_bcd -> lcd_display (count)
//
// Switches: SW[7:0] = threshold (manual) or fine tune (adaptive)
//           SW[8]  = invert  (0 = objects bright, 1 = objects dark)
//           SW[9]  = view    (0 live colour, 1 black/white threshold view)
//           SW[10] = adaptive threshold ON  (0 = manual threshold)
//           SW[11] = water enhance ON (white balance + contrast stretch)
// LEDs: G0 = camera set-up done, G1 = FVAL, G2 = toggles each frame,
//       G3 = last frame had exactly 320x240 pixels (must be ON)
// Monitor: colour bars = camera sends no FVAL (check wiring/power).
//          Black screen = VGA cable/pins problem.
// ---------------------------------------------------------------
module d5m_system_top #(
    parameter FRAME_W = 320,
    parameter FRAME_H = 240
)(
    input            CLK_50,
    input            rst_n,

    input      [7:0] SW_THRESHOLD,
    input            SW_INVERT,
    input            SW_VIEW,
    input            SW_ADAPT,       // SW[10]: adaptive threshold
    input            SW_ENH,         // SW[11]: white balance + contrast stretch

    // Terasic D5M camera (same names as the Terasic demo)
    input      [11:0] D5M_D,
    input            D5M_FVAL,
    input            D5M_LVAL,
    input            D5M_PIXLCLK,
    output           D5M_RESET_N,
    output           D5M_SCLK,
    inout            D5M_SDATA,
    output           D5M_TRIGGER,
    output           D5M_XCLKIN,

    output     [7:0] LCD_DATA,
    output           LCD_RS,
    output           LCD_RW,
    output           LCD_EN,
    output           LCD_ON,
    output           LCD_BLON,

    output     [7:0] VGA_R,
    output     [7:0] VGA_G,
    output     [7:0] VGA_B,
    output           VGA_CLK,
    output           VGA_HS,
    output           VGA_VS,
    output           VGA_BLANK_N,
    output           VGA_SYNC_N,

    output           LEDG0_DEBUG,
    output           LEDG1_DEBUG,
    output           LEDG2_DEBUG,
    output           LEDG3_DEBUG
);

    // ---------------- 25 MHz clock: camera XCLK + VGA ----------------
    reg clk25 = 1'b0;
    always @(posedge CLK_50) clk25 <= ~clk25;

    // camera clock = 25 MHz (the sensor PLL is not used)
    assign D5M_XCLKIN  = clk25;
    assign D5M_TRIGGER = 1'b1;          // free running

    // keep the camera in reset for about 20 ms after power-up
    reg [20:0] rst_cnt;
    always @(posedge CLK_50 or negedge rst_n) begin
        if (!rst_n) rst_cnt <= 21'd0;
        else if (!rst_cnt[20]) rst_cnt <= rst_cnt + 1'b1;
    end
    assign D5M_RESET_N = rst_cnt[20];

    // ---------------- camera set-up (I2C) ----------------
    reg sccb_started;
    always @(posedge CLK_50 or negedge rst_n) begin
        if (!rst_n) sccb_started <= 1'b0;
        else if (rst_cnt[20]) sccb_started <= 1'b1;
    end
    wire sccb_start = rst_cnt[20] & !sccb_started;
    wire sccb_done;

    d5m_i2c_config #(.CLK_FREQ(50_000_000), .I2C_FREQ(100_000)) u_i2c (
        .clk(CLK_50), .rst_n(rst_n), .iStart(sccb_start),
        .oSCLK(D5M_SCLK), .oSDATA(D5M_SDATA), .oDone(sccb_done)
    );

    // ---------------- capture ----------------
    wire        cam_fval, cam_valid, cam_rowend;
    wire [7:0]  cam_r, cam_g, cam_b;

    d5m_capture #(.SWAP_RB(0)) u_cam (
        .pclk(D5M_PIXLCLK), .rst_n(rst_n),
        .fval(D5M_FVAL), .lval(D5M_LVAL), .data(D5M_D),
        .oFval(cam_fval), .oValid(cam_valid), .oRowEnd(cam_rowend),
        .oR(cam_r), .oG(cam_g), .oB(cam_b)
    );

    wire        pf_valid, pf_fstart, pf_lineend, pf_frameend, pf_ok;
    wire [16:0] pf_addr;

    pixel_framer #(.W(FRAME_W), .H(FRAME_H)) u_framer (
        .clk(D5M_PIXLCLK), .rst_n(rst_n),
        .iFval(cam_fval), .iValid(cam_valid), .iRowEnd(cam_rowend),
        .oValid(pf_valid), .oFrameStart(pf_fstart),
        .oLineEnd(pf_lineend), .oFrameEnd(pf_frameend),
        .oAddr(pf_addr), .oFrameOk(pf_ok)
    );

    // ---------------- camera alive check (for the test bars) ----------------
    // If FVAL does not toggle for about 100 ms, the monitor shows colour bars.
    reg        vs_s1, vs_s2, vs_s3;
    reg [21:0] alive_cnt;
    always @(posedge clk25 or negedge rst_n) begin
        if (!rst_n) begin
            vs_s1 <= 1'b0; vs_s2 <= 1'b0; vs_s3 <= 1'b0; alive_cnt <= 22'd0;
        end else begin
            vs_s1 <= D5M_FVAL; vs_s2 <= vs_s1; vs_s3 <= vs_s2;
            if (vs_s2 ^ vs_s3)                alive_cnt <= 22'd0;
            else if (alive_cnt != 22'h3FFFFF) alive_cnt <= alive_cnt + 1'b1;
        end
    end
    wire cam_alive = (alive_cnt < 22'd2_500_000);

    // ---------------- underwater enhance (NEW) ----------------
    wire [7:0]  en_r, en_g, en_b, thr_eff;
    wire        en_valid, en_fstart, en_fend;
    wire [16:0] en_addr;

    underwater_enhance u_enh (
        .clk(D5M_PIXLCLK), .rst_n(rst_n),
        .iEnable(SW_ENH), .iAdaptive(SW_ADAPT),
        .iInvert(SW_INVERT), .iFine(SW_THRESHOLD),
        .iR(cam_r), .iG(cam_g), .iB(cam_b),
        .iValid(pf_valid), .iFrameStart(pf_fstart), .iFrameEnd(pf_frameend),
        .iAddr(pf_addr),
        .oR(en_r), .oG(en_g), .oB(en_b),
        .oValid(en_valid), .oFrameStart(en_fstart), .oFrameEnd(en_fend),
        .oAddr(en_addr),
        .oThreshold(thr_eff)
    );

    // threshold into the 25 MHz VGA clock domain (changes slowly)
    reg [7:0] thr_v1, thr_v2;
    always @(posedge clk25 or negedge rst_n) begin
        if (!rst_n) begin thr_v1 <= 8'd0; thr_v2 <= 8'd0; end
        else begin thr_v1 <= thr_eff; thr_v2 <= thr_v1; end
    end

    // ---------------- live picture to the monitor ----------------
    wire [15:0] fb_wdata = {en_r[7:3], en_g[7:2], en_b[7:3]};
    wire [16:0] vga_addr;
    wire [15:0] fb_rdata;

    frame_buffer u_fb (
        .wclk(D5M_PIXLCLK), .we(en_valid), .waddr(en_addr), .wdata(fb_wdata),
        .rclk(clk25),       .raddr(vga_addr), .rdata(fb_rdata)
    );

    vga_display u_vga (
        .clk(clk25), .rst_n(rst_n),
        .iPixel(fb_rdata),
        .iView(SW_VIEW), .iThreshold(thr_v2), .iInvert(SW_INVERT),
        .iBars(~cam_alive),
        .oAddr(vga_addr),
        .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
        .VGA_HS(VGA_HS), .VGA_VS(VGA_VS), .VGA_BLANK_N(VGA_BLANK_N),
        .VGA_SYNC_N(VGA_SYNC_N), .VGA_CLK(VGA_CLK)
    );

    // ---------------- object detection ----------------
    wire [7:0] gray;
    wire       gt_binary, gt_valid, gt_fstart;

    grayscale_threshold u_gray (
        .clk(D5M_PIXLCLK), .rst_n(rst_n),
        .iR(en_r), .iG(en_g), .iB(en_b),
        .iValid(en_valid), .iFrameStart(en_fstart),
        .iThreshold(thr_eff), .iInvert(SW_INVERT),
        .oGray(gray), .oBinary(gt_binary),
        .oValid(gt_valid), .oFrameStart(gt_fstart)
    );

    wire m1_valid, m1_bin, m1_fstart;
    binary_median3x3 #(.W(FRAME_W), .H(FRAME_H)) u_med1 (
        .clk(D5M_PIXLCLK), .rst_n(rst_n),
        .iValid(gt_valid), .iBinary(gt_binary), .iFrameStart(gt_fstart),
        .oValid(m1_valid), .oBinary(m1_bin), .oFrameStart(m1_fstart)
    );

    wire m2_valid, m2_bin, m2_fstart;
    binary_median3x3 #(.W(FRAME_W-2), .H(FRAME_H-2)) u_med2 (
        .clk(D5M_PIXLCLK), .rst_n(rst_n),
        .iValid(m1_valid), .iBinary(m1_bin), .iFrameStart(m1_fstart),
        .oValid(m2_valid), .oBinary(m2_bin), .oFrameStart(m2_fstart)
    );

    wire [15:0] blob_count;
    wire        blob_valid;

    blob_counter #(.MAX_COLS(FRAME_W-4), .MAX_ROWS(FRAME_H-4)) u_blob (
        .clk(D5M_PIXLCLK), .rst_n(rst_n),
        .iValid(m2_valid), .iBinary(m2_bin), .iFrameStart(m2_fstart),
        .oCount(blob_count), .oCountValid(blob_valid)
    );

    // ---------------- count -> LCD ----------------
    wire [7:0] cnt8 = (blob_count > 16'd255) ? 8'd255 : blob_count[7:0];
    wire [7:0] reg_count;

    count_register #(.STABLE(3)) u_creg (
        .clk(D5M_PIXLCLK), .rst_n(rst_n), .iClear(1'b0),
        .iCount(cnt8), .iValid(blob_valid),
        .oCount(reg_count)
    );

    reg blob_valid_d;
    always @(posedge D5M_PIXLCLK or negedge rst_n) begin
        if (!rst_n) blob_valid_d <= 1'b0;
        else        blob_valid_d <= blob_valid;
    end

    wire [3:0] bcdH, bcdT, bcdO;
    wire       bcd_done;

    binary_to_bcd u_bcd (
        .clk(D5M_PIXLCLK), .rst_n(rst_n),
        .iBinary(reg_count), .iStart(blob_valid_d),
        .oHundreds(bcdH), .oTens(bcdT), .oOnes(bcdO), .oDone(bcd_done)
    );

    reg [3:0] bcdH_s1, bcdH_s2, bcdT_s1, bcdT_s2, bcdO_s1, bcdO_s2;
    always @(posedge CLK_50 or negedge rst_n) begin
        if (!rst_n) begin
            bcdH_s1<=0; bcdH_s2<=0; bcdT_s1<=0; bcdT_s2<=0; bcdO_s1<=0; bcdO_s2<=0;
        end else begin
            bcdH_s1 <= bcdH; bcdH_s2 <= bcdH_s1;
            bcdT_s1 <= bcdT; bcdT_s2 <= bcdT_s1;
            bcdO_s1 <= bcdO; bcdO_s2 <= bcdO_s1;
        end
    end

    lcd_display u_lcd (
        .clk(CLK_50), .rst_n(rst_n),
        .iHundreds(bcdH_s2), .iTens(bcdT_s2), .iOnes(bcdO_s2),
        .LCD_DATA(LCD_DATA), .LCD_RS(LCD_RS), .LCD_RW(LCD_RW),
        .LCD_EN(LCD_EN), .LCD_ON(LCD_ON), .LCD_BLON(LCD_BLON)
    );

    // ---------------- debug LEDs ----------------
    reg frame_toggle;
    always @(posedge D5M_PIXLCLK or negedge rst_n) begin
        if (!rst_n) frame_toggle <= 1'b0;
        else if (pf_frameend) frame_toggle <= ~frame_toggle;
    end

    assign LEDG0_DEBUG = sccb_done;
    assign LEDG1_DEBUG = D5M_FVAL;
    assign LEDG2_DEBUG = frame_toggle;
    assign LEDG3_DEBUG = pf_ok;

endmodule
