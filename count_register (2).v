// ---------------------------------------------------------------
// count_register.v   (UPDATED)
// Holds the count shown on the LCD. A new value is accepted only
// when it was seen in STABLE frames in a row, so the LCD does not
// flicker when noise changes the count by 1 for a single frame.
// ---------------------------------------------------------------
module count_register #(
    parameter STABLE = 3
)(
    input        clk,
    input        rst_n,
    input        iClear,

    input  [7:0] iCount,
    input        iValid,     // one pulse per frame

    output reg [7:0] oCount
);

    reg [7:0] cand;
    reg [3:0] same;

    wire       match  = (iCount == cand);
    wire [3:0] same_n = !match ? 4'd1 :
                        (same >= STABLE) ? same : same + 1'b1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            oCount <= 8'd0; cand <= 8'd0; same <= 4'd0;
        end else if (iClear) begin
            oCount <= 8'd0; cand <= 8'd0; same <= 4'd0;
        end else if (iValid) begin
            cand <= iCount;
            same <= same_n;
            if (same_n >= STABLE) oCount <= iCount;
        end
    end

endmodule
