module binary_to_bcd (
    input        clk,
    input        rst_n,

    input  [7:0] iBinary,
    input        iStart,     // pulse: begin conversion of iBinary

    output reg [3:0] oHundreds,
    output reg [3:0] oTens,
    output reg [3:0] oOnes,
    output reg       oDone    // pulse: outputs are valid
);

    localparam S_IDLE = 0, S_SHIFT = 1, S_DONE = 2;

    reg [1:0]  state;
    reg [3:0]  shift_cnt;
    reg [19:0] shreg;   // [19:12]=hundreds/tens/ones bcd nibbles work area, [7:0]=binary

    // shreg layout while shifting: {hundreds(4), tens(4), ones(4), binary(8)}
    wire [3:0] hund_adj = (shreg[19:16] >= 5) ? shreg[19:16] + 4'd3 : shreg[19:16];
    wire [3:0] tens_adj = (shreg[15:12] >= 5) ? shreg[15:12] + 4'd3 : shreg[15:12];
    wire [3:0] ones_adj = (shreg[11:8]  >= 5) ? shreg[11:8]  + 4'd3 : shreg[11:8];

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state     <= S_IDLE;
            shift_cnt <= 0;
            shreg     <= 20'd0;
            oHundreds <= 4'd0;
            oTens     <= 4'd0;
            oOnes     <= 4'd0;
            oDone     <= 1'b0;
        end else begin
            oDone <= 1'b0;

            case (state)
                S_IDLE: begin
                    if (iStart) begin
                        shreg     <= {12'd0, iBinary};  // load binary into low 8 bits
                        shift_cnt <= 0;
                        state     <= S_SHIFT;
                    end
                end

                S_SHIFT: begin
                    if (shift_cnt == 8) begin
                        state <= S_DONE;
                    end else begin
                        // add-3 correction, then shift left by 1
                        shreg     <= {hund_adj, tens_adj, ones_adj, shreg[7:0]} << 1;
                        shift_cnt <= shift_cnt + 1'b1;
                    end
                end

                S_DONE: begin
                    oHundreds <= shreg[19:16];
                    oTens     <= shreg[15:12];
                    oOnes     <= shreg[11:8];
                    oDone     <= 1'b1;
                    state     <= S_IDLE;
                end

                default: state <= S_IDLE;
            endcase
        end
    end

endmodule
