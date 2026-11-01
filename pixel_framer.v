// ---------------------------------------------------------------
// pixel_framer.v   (REWRITTEN)
// Gives every pixel a frame-buffer address and makes frame markers.
//   - Row end comes from HREF (iRowEnd), so a wrong pixel count can
//     not break the whole frame any more.
//   - Each row snaps to its own start address (row * W).
//   - Only pixels inside W x H are passed on.
//   - oFrameOk = 1 when the last frame had exactly H rows of W pixels
//     (good debug check: show it on a LED).
// ---------------------------------------------------------------
module pixel_framer #(
    parameter W = 320,
    parameter H = 240
)(
    input         clk,
    input         rst_n,
    input         iFval,      // high during active frame
    input         iValid,     // one pulse per pixel
    input         iRowEnd,    // same cycle as last pixel of a row

    output        oValid,
    output        oFrameStart,
    output        oLineEnd,
    output        oFrameEnd,
    output [16:0] oAddr,
    output reg    oFrameOk
);

    reg [9:0]  col, row;
    reg [16:0] addr, row_base;
    reg        fval_d, bad;

    wire in_win = iValid && (col < W) && (row < H);

    assign oValid      = in_win;
    assign oFrameStart = in_win && (col == 0)   && (row == 0);
    assign oLineEnd    = in_win && (col == W-1);
    assign oFrameEnd   = in_win && (col == W-1) && (row == H-1);
    assign oAddr       = addr;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            col <= 0; row <= 0; addr <= 0; row_base <= 0;
            fval_d <= 1'b0; bad <= 1'b0; oFrameOk <= 1'b0;
        end else begin
            fval_d <= iFval;

            if (!iFval) begin
                // vertical sync: frame finished, next one starts
                if (fval_d) oFrameOk <= (row == H) && !bad;
                col <= 0; row <= 0; addr <= 0; row_base <= 0; bad <= 1'b0;
            end else if (iRowEnd) begin
                if (!(iValid && col == W-1)) bad <= 1'b1;
                col      <= 0;
                row      <= row + 1'b1;
                row_base <= row_base + W;
                addr     <= row_base + W;
            end else if (iValid) begin
                col  <= col + 1'b1;
                addr <= addr + 1'b1;
            end
        end
    end

endmodule
