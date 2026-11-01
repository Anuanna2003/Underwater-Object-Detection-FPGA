// ---------------------------------------------------------------
// blob_counter.v   (REWRITTEN)
// Counts objects with the Euler number (8-connected):
//     objects = (Q1 - Q3 - 2*QD) / 4
// Q1 / Q3 = 2x2 windows with exactly one / three white pixels,
// QD = 2x2 windows with the two white pixels on a diagonal.
// Needs only 1 line buffer and gives the right answer for U shapes
// and diagonal shapes (the old counter counted them twice).
// The outer ring of pixels is forced to 0, so objects touching the
// picture edge are counted correctly too.
// Limit: an object with a big hole inside counts as (1 - holes).
// Output: oCount + oCountValid pulse once per frame.
// ---------------------------------------------------------------
module blob_counter #(
    parameter MAX_COLS = 316,
    parameter MAX_ROWS = 236
)(
    input             clk,
    input             rst_n,

    input             iValid,
    input             iBinary,
    input             iFrameStart,

    output reg [15:0] oCount,
    output reg        oCountValid
);

    localparam COL_BITS = $clog2(MAX_COLS);
    localparam ROW_BITS = $clog2(MAX_ROWS);

    reg [COL_BITS-1:0] col;
    reg [ROW_BITS-1:0] row;
    reg                left;      // pixel (x-1, y)
    reg                up_left;   // pixel (x-1, y-1)
    reg [19:0]         acc;       // running Q1 - Q3 - 2*QD

    reg prev_mem [0:MAX_COLS-1];  // previous row

    // iFrameStart restarts everything without losing this pixel
    wire [COL_BITS-1:0] col_eff    = iFrameStart ? {COL_BITS{1'b0}} : col;
    wire [ROW_BITS-1:0] row_eff    = iFrameStart ? {ROW_BITS{1'b0}} : row;
    wire                left_eff   = iFrameStart ? 1'b0  : left;
    wire                upleft_eff = iFrameStart ? 1'b0  : up_left;
    wire [19:0]         acc_eff    = iFrameStart ? 20'd0 : acc;

    wire first_col = (col_eff == 0);
    wire last_col  = (col_eff == MAX_COLS-1);
    wire first_row = (row_eff == 0);
    wire last_row  = (row_eff == MAX_ROWS-1);

    wire edge_pix = first_col | last_col | first_row | last_row;
    wire d = iBinary & ~edge_pix;                       // (x, y)
    wire b = first_row ? 1'b0 : prev_mem[col_eff];      // (x, y-1)
    wire a = upleft_eff;                                // (x-1, y-1)
    wire c = left_eff;                                  // (x-1, y)

    wire [2:0] s  = {2'b00, a} + {2'b00, b} + {2'b00, c} + {2'b00, d};
    wire q1 = (s == 3'd1);
    wire q3 = (s == 3'd3);
    wire qd = (s == 3'd2) && (a == d) && (b == c);
    wire win_ok = ~first_col & ~first_row;

    wire [19:0] delta    = !win_ok ? 20'd0 :
                           q1      ? 20'd1 :
                           q3      ? 20'hFFFFF :          // -1
                           qd      ? 20'hFFFFE : 20'd0;   // -2
    wire [19:0] acc_next = acc_eff + delta;
    wire [15:0] result   = acc_next[19] ? 16'd0 : acc_next[17:2];   // divide by 4

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col <= 0; row <= 0; left <= 1'b0; up_left <= 1'b0; acc <= 20'd0;
            oCount <= 16'd0; oCountValid <= 1'b0;
        end else begin
            oCountValid <= 1'b0;

            if (iValid) begin
                prev_mem[col_eff] <= d;
                acc     <= acc_next;
                left    <= last_col ? 1'b0 : d;
                up_left <= last_col ? 1'b0 : b;

                if (last_col) begin
                    col <= 0;
                    row <= last_row ? row_eff : row_eff + 1'b1;
                end else begin
                    col <= col_eff + 1'b1;
                    row <= row_eff;
                end

                if (last_col && last_row) begin
                    oCount      <= result;
                    oCountValid <= 1'b1;
                end
            end
        end
    end

endmodule
