// ---------------------------------------------------------------
// d5m_i2c_config.v   (NEW)   Terasic TRDB-D5M (MT9P031 sensor)
// Writes the camera set-up registers over I2C (address 0xBA).
// Each write = 4 bytes: 0xBA, register, data high, data low.
//
// What the set-up does:
//   - mirror rows and columns (same as Terasic demo)
//   - window 2560 x 1920, "skip" mode to make the picture smaller
//   - manual exposure and colour gains
//   - the sensor PLL is NOT used: PIXCLK = XCLKIN (25 MHz)
//
// If the picture is too white / too dark: change EXPOSURE.
// If the picture is noisy or torn: change PIXCLK_REG to 16'h0000.
// oDone goes HIGH when all registers are written (LED G0).
// The camera answer (ACK) is not checked.
// ---------------------------------------------------------------
module d5m_i2c_config #(
    parameter CLK_FREQ   = 50_000_000,
    parameter I2C_FREQ   = 100_000,
    parameter T_STARTUP  = 500_000,        // 10 ms at 50 MHz
    parameter [15:0] EXPOSURE   = 16'h0300,
    parameter [15:0] PIXCLK_REG = 16'h8000,
    parameter [15:0] ROW_MODE   = 16'h0003,
    parameter [15:0] COL_MODE   = 16'h0003
)(
    input        clk,
    input        rst_n,
    input        iStart,
    output       oSCLK,
    inout        oSDATA,
    output reg   oDone
);

    localparam [4:0] NUM_REGS = 5'd11;

    // {register address, 16-bit value}
    function [23:0] rom;
        input [4:0] idx;
        begin
            case (idx)
                5'd0:  rom = {8'h20, 16'hC000};     // mirror row + column
                5'd1:  rom = {8'h09, EXPOSURE};     // shutter width (exposure)
                5'd2:  rom = {8'h2B, 16'h000B};     // green 1 gain
                5'd3:  rom = {8'h2C, 16'h000F};     // blue gain
                5'd4:  rom = {8'h2D, 16'h000F};     // red gain
                5'd5:  rom = {8'h2E, 16'h000B};     // green 2 gain
                5'd6:  rom = {8'h0A, PIXCLK_REG};   // pixel clock control
                5'd7:  rom = {8'h03, 16'h077F};     // window height - 1 = 1919
                5'd8:  rom = {8'h04, 16'h09FF};     // window width  - 1 = 2559
                5'd9:  rom = {8'h22, ROW_MODE};     // row skip
                5'd10: rom = {8'h23, COL_MODE};     // column skip
                default: rom = 24'h000000;
            endcase
        end
    endfunction

    localparam [7:0] ID_WRITE = 8'hBA;

    localparam integer QUARTER = CLK_FREQ / (I2C_FREQ * 4);   // 125
    reg [15:0] tick_cnt;
    reg        tick;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            tick_cnt <= 0; tick <= 0;
        end else if (tick_cnt == QUARTER - 1) begin
            tick_cnt <= 0; tick <= 1;
        end else begin
            tick_cnt <= tick_cnt + 1; tick <= 0;
        end
    end

    localparam [3:0] S_IDLE=4'd0, S_WAIT=4'd1, S_FETCH=4'd2, S_START=4'd3,
                     S_BYTE=4'd4, S_ACK=4'd5, S_NEXTBYTE=4'd6,
                     S_STOP=4'd7, S_DONE=4'd8;

    reg [3:0]  state;
    reg [1:0]  phase;
    reg [1:0]  byte_sel;          // 0 = ID, 1 = reg, 2 = data hi, 3 = data lo
    reg [2:0]  bit_idx;
    reg [7:0]  cur_byte;
    reg [4:0]  reg_idx;
    reg [23:0] wait_cnt;
    reg        sda_drive, sda_val;
    reg        scl_r;

    assign oSCLK  = scl_r;
    assign oSDATA = sda_drive ? sda_val : 1'bz;

    function [7:0] byte_for_sel;
        input [1:0]  sel;
        input [23:0] w;
        begin
            case (sel)
                2'd0:    byte_for_sel = ID_WRITE;
                2'd1:    byte_for_sel = w[23:16];
                2'd2:    byte_for_sel = w[15:8];
                default: byte_for_sel = w[7:0];
            endcase
        end
    endfunction

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            state <= S_IDLE; phase <= 0; byte_sel <= 0; bit_idx <= 0;
            reg_idx <= 0; cur_byte <= 0;
            scl_r <= 1; sda_drive <= 1; sda_val <= 1;
            oDone <= 0; wait_cnt <= 0;
        end else begin
            case (state)
                S_IDLE: begin
                    if (iStart) begin wait_cnt <= 0; state <= S_WAIT; end
                end

                S_WAIT: begin
                    if (wait_cnt >= T_STARTUP) state <= S_FETCH;
                    else                       wait_cnt <= wait_cnt + 1'b1;
                end

                S_FETCH: begin
                    if (reg_idx == NUM_REGS) begin
                        oDone <= 1'b1;
                        state <= S_DONE;
                    end else begin
                        phase <= 0;
                        state <= S_START;
                    end
                end

                S_DONE: begin
                    // finished, stay here (oDone stays 1)
                end

                default: begin
                    if (tick) begin
                        case (state)
                            S_START: begin
                                case (phase)
                                    0: begin sda_drive <= 1; sda_val <= 1; scl_r <= 1; phase <= 1; end
                                    1: begin sda_val <= 0; phase <= 2; end
                                    2: begin scl_r <= 0; byte_sel <= 0; bit_idx <= 7;
                                             cur_byte <= byte_for_sel(2'd0, rom(reg_idx));
                                             state <= S_BYTE; phase <= 0; end
                                    default: ;
                                endcase
                            end

                            S_BYTE: begin
                                case (phase)
                                    0: begin sda_drive <= 1; sda_val <= cur_byte[bit_idx]; scl_r <= 0; phase <= 1; end
                                    1: begin scl_r <= 1; phase <= 2; end
                                    2: begin phase <= 3; end
                                    3: begin
                                        scl_r <= 0;
                                        if (bit_idx == 0) begin
                                            sda_drive <= 0;      // release SDA for the ACK
                                            state <= S_ACK; phase <= 0;
                                        end else begin
                                            bit_idx <= bit_idx - 1'b1; phase <= 0;
                                        end
                                    end
                                endcase
                            end

                            S_ACK: begin
                                case (phase)
                                    0: begin sda_drive <= 0; scl_r <= 0; phase <= 1; end
                                    1: begin scl_r <= 1; phase <= 2; end
                                    2: begin phase <= 3; end
                                    3: begin
                                        scl_r <= 0;
                                        if (byte_sel == 2'd3) state <= S_STOP;
                                        else                  state <= S_NEXTBYTE;
                                        phase <= 0;
                                    end
                                endcase
                            end

                            S_NEXTBYTE: begin
                                byte_sel <= byte_sel + 1'b1;
                                cur_byte <= byte_for_sel(byte_sel + 2'd1, rom(reg_idx));
                                bit_idx  <= 3'd7;
                                state    <= S_BYTE;
                                phase    <= 0;
                            end

                            S_STOP: begin
                                case (phase)
                                    0: begin sda_drive <= 1; sda_val <= 0; scl_r <= 0; phase <= 1; end
                                    1: begin scl_r <= 1; phase <= 2; end
                                    2: begin sda_val <= 1; phase <= 3; end
                                    3: begin
                                        reg_idx <= reg_idx + 1'b1;
                                        state   <= S_FETCH;
                                        phase   <= 0;
                                    end
                                endcase
                            end

                            default: state <= S_IDLE;
                        endcase
                    end
                end
            endcase
        end
    end

endmodule
