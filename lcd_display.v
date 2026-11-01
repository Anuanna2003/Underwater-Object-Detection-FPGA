
// ---------------------------------------------------------------
// lcd_display.v
// Shows the object count on the DE2-115 16x2 LCD (HD44780, 8-bit).
//   Line 1:  "Object Count"
//   Line 2:  "      005"
// Write-only. Runs forever: start-up steps once, then it
// rewrites both lines again and again with the newest digits.
// Time values are in clock cycles (default: 50 MHz clock).
// ---------------------------------------------------------------
module lcd_display #(
    parameter T_POWERUP = 1_000_000,  // 20 ms wait after power on
    parameter T_PRE     = 10,         // data ready before EN goes high
    parameter T_EN      = 25,         // EN high time (500 ns)
    parameter T_CMD     = 2_500,      // wait after normal byte (50 us)
    parameter T_LONG    = 250_000     // wait after 0x38 and clear (5 ms)
)(
    input            clk,
    input            rst_n,

    input      [3:0] iHundreds,
    input      [3:0] iTens,
    input      [3:0] iOnes,

    output reg [7:0] LCD_DATA,
    output reg       LCD_RS,
    output           LCD_RW,
    output reg       LCD_EN,
    output           LCD_ON,
    output           LCD_BLON
);

    assign LCD_RW   = 1'b0;   // write only
    assign LCD_ON   = 1'b1;
    assign LCD_BLON = 1'b1;

    localparam [5:0] N_INIT = 6'd6;        // 6 start-up bytes
    localparam [5:0] N_LAST = 6'd39;       // N_INIT + 34 - 1 (cmd + 16 chars + cmd + 16 chars)

    localparam [127:0] LINE1 = "Object Count    ";

    // item = {RS, byte}
    function [8:0] item;
        input [5:0] i;
        input [3:0] h, t, o;
        integer k;
        begin
            if (i < N_INIT) begin
                case (i)
                    0, 1, 2: item = {1'b0, 8'h38};  // 8-bit, 2 lines
                    3:       item = {1'b0, 8'h0C};  // display on, no cursor
                    4:       item = {1'b0, 8'h01};  // clear
                    default: item = {1'b0, 8'h06};  // cursor moves right
                endcase
            end else if (i == N_INIT) begin
                item = {1'b0, 8'h80};               // line 1, column 0
            end else if (i <= N_INIT + 16) begin
                k = i - (N_INIT + 1);               // 0..15
                item = {1'b1, LINE1[127 - 8*k -: 8]};
            end else if (i == N_INIT + 17) begin
                item = {1'b0, 8'hC0};               // line 2, column 0
            end else begin
                k = i - (N_INIT + 18);              // 0..15
                case (k)
                    6:       item = {1'b1, 8'h30 + {4'h0, h}};
                    7:       item = {1'b1, 8'h30 + {4'h0, t}};
                    8:       item = {1'b1, 8'h30 + {4'h0, o}};
                    default: item = {1'b1, 8'h20};  // space
                endcase
            end
        end
    endfunction

    localparam S_PWR = 3'd0, S_SETUP = 3'd1, S_PRE = 3'd2,
               S_EN  = 3'd3, S_DLY   = 3'd4;

    reg [2:0]  st;
    reg [31:0] cnt;
    reg [5:0]  idx;
    reg [8:0]  cur;
    reg [3:0]  rH, rT, rO;     // digits held for one full refresh

    wire        is_long = (!cur[8]) && (cur[7:0] == 8'h38 || cur[7:0] == 8'h01);
    wire [5:0]  nidx    = (idx == N_LAST) ? N_INIT : idx + 6'd1;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            st       <= S_PWR;
            cnt      <= 32'd0;
            idx      <= 6'd0;
            cur      <= 9'd0;
            rH       <= 4'd0;
            rT       <= 4'd0;
            rO       <= 4'd0;
            LCD_DATA <= 8'd0;
            LCD_RS   <= 1'b0;
            LCD_EN   <= 1'b0;
        end else begin
            case (st)
                S_PWR: begin
                    if (cnt >= T_POWERUP) begin
                        cnt <= 32'd0;
                        st  <= S_SETUP;
                    end else cnt <= cnt + 32'd1;
                end

                S_SETUP: begin
                    cur      <= item(idx, rH, rT, rO);
                    LCD_RS   <= item(idx, rH, rT, rO) >> 8;  // top bit = RS
                    LCD_DATA <= item(idx, rH, rT, rO);
                    cnt      <= 32'd0;
                    st       <= S_PRE;
                end

                S_PRE: begin
                    if (cnt >= T_PRE) begin
                        LCD_EN <= 1'b1;
                        cnt    <= 32'd0;
                        st     <= S_EN;
                    end else cnt <= cnt + 32'd1;
                end

                S_EN: begin
                    if (cnt >= T_EN) begin
                        LCD_EN <= 1'b0;
                        cnt    <= 32'd0;
                        st     <= S_DLY;
                    end else cnt <= cnt + 32'd1;
                end

                S_DLY: begin
                    if (cnt >= (is_long ? T_LONG : T_CMD)) begin
                        cnt <= 32'd0;
                        idx <= nidx;
                        if (nidx == N_INIT) begin   // new refresh: take new digits
                            rH <= iHundreds;
                            rT <= iTens;
                            rO <= iOnes;
                        end
                        st <= S_SETUP;
                    end else cnt <= cnt + 32'd1;
                end

                default: st <= S_PWR;
            endcase
        end
    end

endmodule