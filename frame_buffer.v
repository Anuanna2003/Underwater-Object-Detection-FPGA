// ---------------------------------------------------------------
// frame_buffer.v   (NEW)
// One 320x240 RGB565 picture in on-chip RAM (about 150 M9K blocks).
// Camera writes with PCLK, VGA reads with the 25 MHz VGA clock.
// ---------------------------------------------------------------
module frame_buffer (
    input         wclk,
    input         we,
    input  [16:0] waddr,
    input  [15:0] wdata,

    input         rclk,
    input  [16:0] raddr,
    output reg [15:0] rdata
);

    (* ramstyle = "M9K" *) reg [15:0] mem [0:76799];

    always @(posedge wclk) begin
        if (we) mem[waddr] <= wdata;
    end

    always @(posedge rclk) begin
        rdata <= mem[raddr];
    end

endmodule
