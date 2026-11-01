// ---------------------------------------------------------------
// d5m_capture.v   (NEW)   replaces camera_detect.v
// Takes the D5M raw (Bayer) stream and gives 8-bit R, G, B pixels
// with the SAME outputs as camera_detect:
//   oFval, oValid (one pulse per pixel), oRowEnd (same clock as the
//   last pixel of the row), oR, oG, oB.
//
// How it works:
//   1. Every 2x2 raw pixels (G B / R G, after the mirror setting)
//      make ONE colour pixel:  R = left-bottom, B = right-top,
//      G = average of the two greens.
//   2. The picture is made smaller to 320 x 240 by dropping pixels.
//      The camera size is MEASURED, so it works for 640x480,
//      1280x960 or 2560x1920 raw size (sizes of 2x steps):
//         raw width  <  960 : keep every colour pixel
//         raw width  < 1920 : keep every 2nd
//         otherwise         : keep every 4th   (same for the rows)
//      The row count is measured at the end of each frame, so the
//      very first frame after power-up can be wrong. This is normal.
//   3. SWAP_RB = 1 swaps red and blue (use it if colours look wrong).
//
// Needs one line of raw pixels in RAM (4096 x 8 bit).
// Valid pixels come at least every 2nd clock.
// ---------------------------------------------------------------
module d5m_capture #(
    parameter SWAP_RB = 0
)(
    input        pclk,
    input        rst_n,
    input        fval,        // D5M frame valid
    input        lval,        // D5M line valid
    input [11:0] data,        // D5M 12-bit raw data

    output       oFval,
    output reg   oValid,
    output reg   oRowEnd,
    output reg [7:0] oR,
    output reg [7:0] oG,
    output reg [7:0] oB
);

    // ---------------- position counters ----------------
    reg [11:0] c, row;
    reg        lval_d, fval_d;
    reg [11:0] cols_meas, rows_meas;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            c <= 0; row <= 0; lval_d <= 0; fval_d <= 0;
            cols_meas <= 12'd640; rows_meas <= 12'd480;
        end else begin
            lval_d <= lval;
            fval_d <= fval;

            if (lval) c <= c + 1'b1;
            else      c <= 12'd0;

            if (!fval) row <= 12'd0;
            else if (lval_d & ~lval) row <= row + 1'b1;

            if (lval_d & ~lval)  cols_meas <= c;      // pixels in the line that just ended
            if (fval_d & ~fval)  rows_meas <= row;    // lines in the frame that just ended
        end
    end

    wire [1:0] sx = (cols_meas >= 12'd1920) ? 2'd2 : (cols_meas >= 12'd960) ? 2'd1 : 2'd0;
    wire [1:0] sy = (rows_meas >= 12'd1440) ? 2'd2 : (rows_meas >= 12'd720) ? 2'd1 : 2'd0;

    // ---------------- one-line memory ----------------
    reg [7:0]  lb [0:4095];
    reg [7:0]  lb_q;
    reg        s1_v;
    reg [11:0] s1_c, s1_row;
    reg [7:0]  s1_d;

    always @(posedge pclk) begin
        lb_q <= lb[c];                       // pixel above (valid next clock)
        if (s1_v) lb[s1_c] <= s1_d;          // store pixel of the previous clock
    end

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            s1_v <= 0; s1_c <= 0; s1_row <= 0; s1_d <= 0;
        end else begin
            s1_v   <= lval;
            s1_c   <= c;
            s1_row <= row;
            s1_d   <= data[11:4];
        end
    end

    // neighbours from the clock before
    reg [7:0] prev_d, prev_top;
    always @(posedge pclk) begin
        prev_d   <= s1_d;
        prev_top <= lb_q;
    end

    // ---------------- make one colour pixel ----------------
    wire        blk = s1_v & s1_c[0] & s1_row[0];      // bottom-right raw pixel of a 2x2
    wire [10:0] mx  = (11'd1 << sx) - 11'd1;
    wire [10:0] my  = (11'd1 << sy) - 11'd1;
    wire        sel = blk && ((s1_c[11:1]   & mx) == 11'd0)
                          && ((s1_row[11:1] & my) == 11'd0);

    wire [7:0] rr = SWAP_RB ? lb_q   : prev_d;
    wire [7:0] bb = SWAP_RB ? prev_d : lb_q;
    wire [8:0] gs = {1'b0, prev_top} + {1'b0, s1_d};
    wire [7:0] gg = gs[8:1];

    // ---------------- hold one pixel so that the last one of a row
    //                  leaves together with oRowEnd ----------------
    reg       hold_v, s1_v_d;
    reg [7:0] hR, hG, hB;
    wire      row_end_ev = s1_v_d & ~s1_v;

    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) begin
            hold_v <= 0; s1_v_d <= 0; hR <= 0; hG <= 0; hB <= 0;
            oValid <= 0; oRowEnd <= 0; oR <= 0; oG <= 0; oB <= 0;
        end else begin
            oValid  <= 1'b0;
            oRowEnd <= 1'b0;
            s1_v_d  <= s1_v;

            if (sel) begin
                if (hold_v) begin
                    oValid <= 1'b1; oR <= hR; oG <= hG; oB <= hB;
                end
                hR <= rr; hG <= gg; hB <= bb; hold_v <= 1'b1;
            end else if (row_end_ev) begin
                if (hold_v) begin
                    oValid <= 1'b1; oRowEnd <= 1'b1;
                    oR <= hR; oG <= hG; oB <= hB;
                end
                hold_v <= 1'b0;
            end
        end
    end

    // ---------------- frame valid, delayed to stay behind the last pixel ----------------
    reg [5:0] fv_sh;
    always @(posedge pclk or negedge rst_n) begin
        if (!rst_n) fv_sh <= 6'd0;
        else        fv_sh <= {fv_sh[4:0], fval};
    end
    assign oFval = fv_sh[5];

endmodule
