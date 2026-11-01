// ---------------------------------------------------------------
// seq_divider.v   (FIXED for Quartus fitter)
// Small slow divider: quotient = num / den, one bit per clock.
// Takes NW+2 clocks. Used once per frame, so speed does not matter.
//   iStart : pulse for ONE clock, num/den must be stable at that clock
//   oDone  : pulse for ONE clock when oQuo is ready
//   den = 0 gives a quotient of all 1s (the user must clamp it).
//
// Fix: the data registers (n, d, r, oQuo, cnt) have NO async reset any
// more. This keeps the number of control signals per register low
// (the fitter allows only 4). Only busy and oDone have a reset.
// ---------------------------------------------------------------
module seq_divider #(
    parameter NW = 33,    // numerator bits
    parameter DW = 25     // denominator bits
)(
    input               clk,
    input               rst_n,
    input               iStart,
    input  [NW-1:0]     iNum,
    input  [DW-1:0]     iDen,
    output reg [NW-1:0] oQuo,
    output reg          oDone
);

    reg [NW-1:0] n;
    reg [DW-1:0] d;
    reg [DW:0]   r;
    reg [6:0]    cnt;
    reg          busy;

    wire         load  = iStart & ~busy;
    wire [DW:0]  r_sh  = {r[DW-1:0], n[NW-1]};
    wire         ge    = (r_sh >= {1'b0, d});
    wire [DW:0]  r_nxt = ge ? (r_sh - {1'b0, d}) : r_sh;

    // data path: no reset
    always @(posedge clk) begin
        if (load) begin
            n    <= iNum;
            d    <= iDen;
            r    <= {(DW+1){1'b0}};
            oQuo <= {NW{1'b0}};
            cnt  <= NW;
        end else if (busy) begin
            n    <= {n[NW-2:0], 1'b0};
            r    <= r_nxt;
            oQuo <= {oQuo[NW-2:0], ge};
            cnt  <= cnt - 1'b1;
        end
    end

    // control: with reset
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy  <= 1'b0;
            oDone <= 1'b0;
        end else begin
            oDone <= 1'b0;
            if (load) begin
                busy <= 1'b1;
            end else if (busy && cnt == 7'd1) begin
                busy  <= 1'b0;
                oDone <= 1'b1;
            end
        end
    end

endmodule
