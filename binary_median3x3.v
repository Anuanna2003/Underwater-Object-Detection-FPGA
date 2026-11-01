// ---------------------------------------------------------------
// binary_median3x3.v   (NEW)  -  noise filter
// Looks at 3x3 pixels around each pixel. Output = 1 if 5 or more
// of the 9 are 1. Removes white and black specks (camera noise).
// Output is the inside picture only: (W-2) x (H-2) pixels,
// one clock later. Uses only iFrameStart + iValid for position.
// ---------------------------------------------------------------
module binary_median3x3 #(
    parameter W = 320,
    parameter H = 240
)(
    input      clk,
    input      rst_n,
    input      iValid,
    input      iBinary,
    input      iFrameStart,

    output reg oValid,
    output reg oBinary,
    output reg oFrameStart
);

    localparam CB = $clog2(W);
    localparam RB = $clog2(H);

    // two line buffers (one row each), they move only on valid pixels
    reg [W-1:0] lb1, lb2;
    always @(posedge clk) begin
        if (iValid) begin
            lb1 <= {lb1[W-2:0], iBinary};
            lb2 <= {lb2[W-2:0], lb1[W-1]};
        end
    end

    wire r_top = lb2[W-1];   // pixel (x, y-2)
    wire r_mid = lb1[W-1];   // pixel (x, y-1)
    wire r_bot = iBinary;    // pixel (x, y)

    reg t0, t1, m0, m1, b0, b1;   // older two columns of the 3x3 window

    reg [CB-1:0] x;
    reg [RB-1:0] y;

    wire [CB-1:0] x_eff = iFrameStart ? {CB{1'b0}} : x;
    wire [RB-1:0] y_eff = iFrameStart ? {RB{1'b0}} : y;
    wire last_col = (x_eff == W-1);

    wire [3:0] sum = t0 + t1 + r_top + m0 + m1 + r_mid + b0 + b1 + r_bot;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            t0 <= 0; t1 <= 0; m0 <= 0; m1 <= 0; b0 <= 0; b1 <= 0;
            x <= 0; y <= 0;
            oValid <= 1'b0; oBinary <= 1'b0; oFrameStart <= 1'b0;
        end else begin
            oValid      <= 1'b0;
            oFrameStart <= 1'b0;

            if (iValid) begin
                t0 <= t1; t1 <= r_top;
                m0 <= m1; m1 <= r_mid;
                b0 <= b1; b1 <= r_bot;

                oValid      <= (x_eff >= 2) && (y_eff >= 2);
                oBinary     <= (sum >= 4'd5);
                oFrameStart <= (x_eff == 2) && (y_eff == 2);

                if (last_col) begin
                    x <= 0;
                    y <= (y_eff == H-1) ? y_eff : y_eff + 1'b1;
                end else begin
                    x <= x_eff + 1'b1;
                    y <= y_eff;
                end
            end
        end
    end

endmodule
