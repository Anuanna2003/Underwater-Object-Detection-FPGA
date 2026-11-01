// ---------------------------------------------------------------
// underwater_enhance.v   (NEW)
//
// Three features in one block (all work on the camera pixel stream):
//   1. WHITE BALANCE (gray-world): water cuts red light, so the
//      picture looks blue/green. Each frame, we measure the average
//      of R, G and B. Next frame, R, G and B are multiplied by a
//      gain so all three averages become equal.
//   2. BRIGHTNESS STRETCH: each frame we find the bright level (hi)
//      of the picture (98.5% point of a 64-bin histogram). Next frame,
//      R, G and B are all multiplied by the same gain so that hi -> 255.
//      The gain is limited to 1x ... 4x. There is no black-level cut,
//      so the colours can never be crushed to 0 or 255 on their own.
//   3. ADAPTIVE THRESHOLD: each frame we measure the average
//      brightness (mean) of the enhanced picture. The threshold for
//      object detection follows it:
//          SW_INVERT = 0 (objects bright) : T = mean + margin
//          SW_INVERT = 1 (objects dark)   : T = mean - margin
//          margin = 16 + iFine[7:2]    (16 ... 79)
//
// "Next frame" = the numbers are measured during one frame and used
// from the next frame. They change only in the gap between frames.
// The first 2-3 frames after power-up are used to settle.
//
// Switches (already synchronised inside this module):
//   iEnable   = 0 : picture passes through unchanged (gain 1.0)
//   iAdaptive = 0 : oThreshold = iFine  (old manual threshold)
//   iAdaptive = 1 : oThreshold follows the picture (see above)
//
// Gains are 8.8 fixed point (256 = 1.0). Limits: WB 0.25x ... 16x,
// stretch 1.0x ... 4x.
//
// Latency: 5 clocks. oAddr/oValid/oFrameStart/oFrameEnd are delayed
// by the same 5 clocks, so they stay in step with the pixel.
// ---------------------------------------------------------------
module underwater_enhance (
    input             clk,           // camera PCLK
    input             rst_n,

    input             iEnable,
    input             iAdaptive,
    input             iInvert,
    input      [7:0]  iFine,

    input      [7:0]  iR,
    input      [7:0]  iG,
    input      [7:0]  iB,
    input             iValid,
    input             iFrameStart,
    input             iFrameEnd,
    input      [16:0] iAddr,

    output reg [7:0]  oR,
    output reg [7:0]  oG,
    output reg [7:0]  oB,
    output reg        oValid,
    output reg        oFrameStart,
    output reg        oFrameEnd,
    output reg [16:0] oAddr,

    output     [7:0]  oThreshold
);

    // ---------------- switches: 2-flop synchroniser ----------------
    reg [10:0] sw_s1, sw_s2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin sw_s1 <= 11'd0; sw_s2 <= 11'd0; end
        else begin
            sw_s1 <= {iEnable, iAdaptive, iInvert, iFine};
            sw_s2 <= sw_s1;
        end
    end
    wire       en   = sw_s2[10];
    wire       ad   = sw_s2[9];
    wire       inv  = sw_s2[8];
    wire [7:0] fine = sw_s2[7:0];

    // ---------------- numbers measured last frame ----------------
    reg [11:0] gR, gG, gB;     // white balance gains (256 = 1.0)
    reg [7:0]  lo;             // dark level
    reg [10:0] gS;             // stretch gain (256 = 1.0)
    reg [7:0]  mean8;          // average brightness after enhancing

    // ---------------- stage 0: add up raw R, G, B ----------------
    reg [24:0] sumR, sumG, sumB;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sumR <= 25'd0; sumG <= 25'd0; sumB <= 25'd0;
        end else if (iValid) begin
            sumR <= (iFrameStart ? 25'd0 : sumR) + iR;
            sumG <= (iFrameStart ? 25'd0 : sumG) + iG;
            sumB <= (iFrameStart ? 25'd0 : sumB) + iB;
        end
    end

    function [7:0] clamp8;
        input [11:0] x;
        begin clamp8 = (x > 12'd255) ? 8'd255 : x[7:0]; end
    endfunction

    // ---------------- stage 1: white balance multiply ----------------
    wire [11:0] gR_e = en ? gR : 12'd256;
    wire [11:0] gG_e = en ? gG : 12'd256;
    wire [11:0] gB_e = en ? gB : 12'd256;

    reg [19:0] m1r, m1g, m1b;
    reg        v1, fs1, fe1;
    reg [16:0] a1;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m1r <= 0; m1g <= 0; m1b <= 0;
            v1 <= 0; fs1 <= 0; fe1 <= 0; a1 <= 0;
        end else begin
            m1r <= iR * gR_e;
            m1g <= iG * gG_e;
            m1b <= iB * gB_e;
            v1  <= iValid; fs1 <= iFrameStart; fe1 <= iFrameEnd; a1 <= iAddr;
        end
    end

    // ---------------- stage 2: clamp to 8 bits ----------------
    reg [7:0]  w_r, w_g, w_b;
    reg        v2, fs2, fe2;
    reg [16:0] a2;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            w_r <= 0; w_g <= 0; w_b <= 0;
            v2 <= 0; fs2 <= 0; fe2 <= 0; a2 <= 0;
        end else begin
            w_r <= clamp8(m1r[19:8]);
            w_g <= clamp8(m1g[19:8]);
            w_b <= clamp8(m1b[19:8]);
            v2 <= v1; fs2 <= fs1; fe2 <= fe1; a2 <= a1;
        end
    end

    // ---------------- stage 3: brightness + subtract dark level ----------------
    wire [7:0] lo_e = en ? lo : 8'd0;

    reg [15:0] g3;
    reg [7:0]  sub_r, sub_g, sub_b;
    reg        v3, fs3, fe3;
    reg [16:0] a3;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            g3 <= 0; sub_r <= 0; sub_g <= 0; sub_b <= 0;
            v3 <= 0; fs3 <= 0; fe3 <= 0; a3 <= 0;
        end else begin
            g3    <= w_r * 16'd77 + w_g * 16'd150 + w_b * 16'd29;
            sub_r <= (w_r > lo_e) ? (w_r - lo_e) : 8'd0;
            sub_g <= (w_g > lo_e) ? (w_g - lo_e) : 8'd0;
            sub_b <= (w_b > lo_e) ? (w_b - lo_e) : 8'd0;
            v3 <= v2; fs3 <= fs2; fe3 <= fe2; a3 <= a2;
        end
    end

    // ---------------- histogram of brightness (64 bins) ----------------
    reg [16:0] hist [0:63];
    reg [16:0] tot;
    integer k;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (k = 0; k < 64; k = k + 1) hist[k] <= 17'd0;
            tot <= 17'd0;
        end else if (v3) begin
            for (k = 0; k < 64; k = k + 1)
                hist[k] <= (fs3 ? 17'd0 : hist[k]) + ((g3[15:10] == k) ? 17'd1 : 17'd0);
            tot <= (fs3 ? 17'd0 : tot) + 17'd1;
        end
    end

    // ---------------- stage 4: stretch multiply ----------------
    wire [10:0] gS_e = en ? gS : 11'd256;

    reg [18:0] m4r, m4g, m4b;
    reg        v4, fs4, fe4;
    reg [16:0] a4;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            m4r <= 0; m4g <= 0; m4b <= 0;
            v4 <= 0; fs4 <= 0; fe4 <= 0; a4 <= 0;
        end else begin
            m4r <= sub_r * gS_e;
            m4g <= sub_g * gS_e;
            m4b <= sub_b * gS_e;
            v4 <= v3; fs4 <= fs3; fe4 <= fe3; a4 <= a3;
        end
    end

    // ---------------- stage 5: clamp -> output pixel ----------------
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            oR <= 0; oG <= 0; oB <= 0;
            oValid <= 0; oFrameStart <= 0; oFrameEnd <= 0; oAddr <= 0;
        end else begin
            oR <= clamp8(m4r[18:8]);
            oG <= clamp8(m4g[18:8]);
            oB <= clamp8(m4b[18:8]);
            oValid <= v4; oFrameStart <= fs4; oFrameEnd <= fe4; oAddr <= a4;
        end
    end

    // ---------------- stage 6/7: average brightness of output ----------------
    reg [15:0] g6;
    reg        v6, fs6, fe6;
    reg [24:0] sumOut;
    reg        fe7;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            g6 <= 0; v6 <= 0; fs6 <= 0; fe6 <= 0; sumOut <= 0; fe7 <= 0;
        end else begin
            g6  <= oR * 16'd77 + oG * 16'd150 + oB * 16'd29;
            v6  <= oValid; fs6 <= oFrameStart; fe6 <= oFrameEnd;
            if (v6) sumOut <= (fs6 ? 25'd0 : sumOut) + g6[15:8];
            fe7 <= v6 & fe6;       // 1 clock after the last pixel was added
        end
    end

    // ---------------- end-of-frame calculation ----------------
    wire [26:0] sum3  = {2'b00, sumR} + {2'b00, sumG} + {2'b00, sumB};
    wire [36:0] avg_w = sum3 * 10'd171;          // x171/512 = about /3
    wire [16:0] lo_thr = tot >> 6;               // about 1.5 %
    wire [16:0] hi_thr = tot - lo_thr;           // about 98.5 %

    reg  [24:0] avg_r;
    reg         div_start;
    reg  [32:0] div_num;
    reg  [24:0] div_den;
    wire [32:0] div_q;
    wire        div_done;

    seq_divider #(.NW(33), .DW(25)) u_div (
        .clk(clk), .rst_n(rst_n), .iStart(div_start),
        .iNum(div_num), .iDen(div_den),
        .oQuo(div_q), .oDone(div_done)
    );

    function [11:0] clampWB;      // 64 ... 4095  (0.25x ... 16x)
        input [32:0] q;
        begin clampWB = (q > 33'd4095) ? 12'd4095 : (q < 33'd64) ? 12'd64 : q[11:0]; end
    endfunction
    function [10:0] clampS;       // 256 ... 1024 (1x ... 4x)
        input [32:0] q;
        begin clampS = (q > 33'd1024) ? 11'd1024 : (q < 33'd256) ? 11'd256 : q[10:0]; end
    endfunction

    localparam [3:0] ST_IDLE = 4'd0, ST_DR = 4'd1, ST_DG = 4'd2, ST_DB = 4'd3,
                     ST_SCAN = 4'd4, ST_RANGE = 4'd5, ST_DS = 4'd6, ST_DM = 4'd7;

    reg [3:0]  st;
    reg        issued;
    reg [5:0]  scan_idx;
    reg [17:0] cum;
    wire [17:0] cum_n = cum + {1'b0, hist[scan_idx]};
    reg        found_lo, found_hi;
    reg [5:0]  lo_bin, hi_bin;
    reg [7:0]  range_c;
    wire [7:0] lo_new = {lo_bin, 2'b00};
    wire [7:0] hi_new = {hi_bin, 2'b11};

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st <= ST_IDLE; issued <= 1'b0; div_start <= 1'b0;
            div_num <= 0; div_den <= 1; avg_r <= 0;
            gR <= 12'd256; gG <= 12'd256; gB <= 12'd256;
            lo <= 8'd0; gS <= 11'd256; mean8 <= 8'd128;
            scan_idx <= 0; cum <= 0; found_lo <= 0; found_hi <= 0;
            lo_bin <= 0; hi_bin <= 6'd63; range_c <= 8'd255;
        end else begin
            div_start <= 1'b0;
            case (st)
                ST_IDLE: begin
                    issued <= 1'b0;
                    if (fe7) begin
                        avg_r <= avg_w[33:9];
                        st    <= ST_DR;
                    end
                end

                ST_DR: begin
                    if (!issued) begin
                        div_num <= {avg_r, 8'd0}; div_den <= sumR;
                        div_start <= 1'b1; issued <= 1'b1;
                    end else if (div_done) begin
                        gR <= clampWB(div_q); issued <= 1'b0; st <= ST_DG;
                    end
                end

                ST_DG: begin
                    if (!issued) begin
                        div_num <= {avg_r, 8'd0}; div_den <= sumG;
                        div_start <= 1'b1; issued <= 1'b1;
                    end else if (div_done) begin
                        gG <= clampWB(div_q); issued <= 1'b0; st <= ST_DB;
                    end
                end

                ST_DB: begin
                    if (!issued) begin
                        div_num <= {avg_r, 8'd0}; div_den <= sumB;
                        div_start <= 1'b1; issued <= 1'b1;
                    end else if (div_done) begin
                        gB <= clampWB(div_q); issued <= 1'b0;
                        scan_idx <= 6'd0; cum <= 18'd0;
                        found_lo <= 1'b0; found_hi <= 1'b0;
                        lo_bin <= 6'd0;   hi_bin <= 6'd63;
                        st <= ST_SCAN;
                    end
                end

                ST_SCAN: begin
                    cum <= cum_n;
                    if (!found_lo && cum_n >= {1'b0, lo_thr}) begin
                        found_lo <= 1'b1; lo_bin <= scan_idx;
                    end
                    if (!found_hi && cum_n >= {1'b0, hi_thr}) begin
                        found_hi <= 1'b1; hi_bin <= scan_idx;
                    end
                    scan_idx <= scan_idx + 1'b1;
                    if (scan_idx == 6'd63) st <= ST_RANGE;
                end

                ST_RANGE: begin
                    lo <= 8'd0;                        // no black-level cut
                    range_c <= (hi_new > 8'd63) ? hi_new : 8'd64;   // gain is at most 4x
                    st <= ST_DS;
                end

                ST_DS: begin
                    if (!issued) begin
                        div_num <= 33'd65280; div_den <= {17'd0, range_c};
                        div_start <= 1'b1; issued <= 1'b1;
                    end else if (div_done) begin
                        gS <= clampS(div_q); issued <= 1'b0; st <= ST_DM;
                    end
                end

                ST_DM: begin
                    if (!issued) begin
                        div_num <= {8'd0, sumOut}; div_den <= {8'd0, tot};
                        div_start <= 1'b1; issued <= 1'b1;
                    end else if (div_done) begin
                        mean8 <= (div_q > 33'd255) ? 8'd255 : div_q[7:0];
                        issued <= 1'b0; st <= ST_IDLE;
                    end
                end

                default: st <= ST_IDLE;
            endcase
        end
    end

    // ---------------- adaptive threshold ----------------
    wire [7:0] margin = 8'd16 + {2'b00, fine[7:2]};            // 16 ... 79
    wire [8:0] t_up   = {1'b0, mean8} + {1'b0, margin};
    wire [7:0] t_hi   = t_up[8] ? 8'd255 : t_up[7:0];
    wire [7:0] t_lo   = (mean8 > margin) ? (mean8 - margin) : 8'd0;

    assign oThreshold = !ad ? fine : (inv ? t_lo : t_hi);

endmodule
