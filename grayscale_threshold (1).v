
module grayscale_threshold (
    input             clk,
    input             rst_n,

    input      [7:0]  iR,
    input      [7:0]  iG,
    input      [7:0]  iB,
    input             iValid,
    input             iFrameStart,

    input      [7:0]  iThreshold,
    input             iInvert,

    output reg [7:0]  oGray,
    output reg        oBinary,
    output reg        oValid,
    output reg        oFrameStart
);

    reg [15:0] sum_s1;
    reg        valid_s1, fstart_s1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            sum_s1    <= 16'd0;
            valid_s1  <= 1'b0;
            fstart_s1 <= 1'b0;
        end else begin
            sum_s1    <= (iR * 8'd77) + (iG * 8'd150) + (iB * 8'd29);
            valid_s1  <= iValid;
            fstart_s1 <= iFrameStart;
        end
    end

    wire [7:0] gray_w = sum_s1[15:8];
    wire       above  = (gray_w >= iThreshold);

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            oGray       <= 8'd0;
            oBinary     <= 1'b0;
            oValid      <= 1'b0;
            oFrameStart <= 1'b0;
        end else begin
            oGray       <= gray_w;
            oBinary     <= valid_s1 ? (iInvert ? ~above : above) : 1'b0;
            oValid      <= valid_s1;
            oFrameStart <= fstart_s1;
        end
    end

endmodule