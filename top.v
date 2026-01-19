module pll_linux
(
    input clkin, // 25 MHz, 0 deg
    output clkout0, // 125 MHz, 0 deg
    output clkout1, // 104.167 MHz, 270 deg
    output clkout2, // 52.0833 MHz, 0 deg
    output clkout3, // 25 MHz, 0 deg
    output locked
);
(* FREQUENCY_PIN_CLKI="25" *)
(* FREQUENCY_PIN_CLKOP="125" *)
(* FREQUENCY_PIN_CLKOS="104.167" *)
(* FREQUENCY_PIN_CLKOS2="52.0833" *)
(* FREQUENCY_PIN_CLKOS3="25" *)
(* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(1),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(5),
        .CLKOP_CPHASE(2),
        .CLKOP_FPHASE(0),
        .CLKOS_ENABLE("ENABLED"),
        .CLKOS_DIV(6),
        .CLKOS_CPHASE(6),
        .CLKOS_FPHASE(4),
        .CLKOS2_ENABLE("ENABLED"),
        .CLKOS2_DIV(12),
        .CLKOS2_CPHASE(2),
        .CLKOS2_FPHASE(0),
        .CLKOS3_ENABLE("ENABLED"),
        .CLKOS3_DIV(25),
        .CLKOS3_CPHASE(2),
        .CLKOS3_FPHASE(0),
        .FEEDBK_PATH("CLKOP"),
        .CLKFB_DIV(5)
    ) pll_i (
        .RST(1'b0),
        .STDBY(1'b0),
        .CLKI(clkin),
        .CLKOP(clkout0),
        .CLKOS(clkout1),
        .CLKOS2(clkout2),
        .CLKOS3(clkout3),
        .CLKFB(clkout0),
        .CLKINTFB(),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b1),
        .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .LOCK(locked)
    );
endmodule

module tft_driver(input clk, 
    output tft_clk,
    output hsync,
    output vsync,
    output de,
    output reg [9:0] pos_x = 0,
    output reg [9:0] pos_y = 0
    );


    localparam active_width = 480;
    localparam total_width = 525;
    localparam active_height = 272;
    localparam total_height = 288;

//    reg [9:0] pos_x = 0;
//    reg [9:0] pos_y = 0;

    reg slow_clk_reg = 0;
    always @(posedge clk) begin

//        if(slow_clk_reg == 0) begin
            if(pos_y >= total_height) begin
                pos_x <= 0;
                pos_y <= 0;
            end else begin
                if(pos_x >= total_width) begin
                    pos_x <= 0;
                    pos_y <= pos_y + 1;
                end else begin
                    pos_x <= pos_x + 1;
                end
            end
//        end

        slow_clk_reg <= ~slow_clk_reg;
    end

    assign hsync = ~(pos_x > (active_width-1));
    assign vsync = ~(pos_y > (active_height-1));
    assign de = hsync;
    assign tft_clk = clk;
endmodule

module LFSR_rng
(
    input clk,
    output [31:0] rand_out
);

    reg [31:0] rand_ff=32'b01011111011;

        always @(posedge clk)
        begin
           rand_ff<={(rand_ff[31]^rand_ff[30]^rand_ff[10]^rand_ff[0]),rand_ff[31:1]};
           rand_out<=rand_ff;
        end
endmodule

module diff_sampler(
    input pwm_clk,
    input diff_in,
    output [15:0] sample_high_count_out);

    reg [15:0] last_sample_high_count = 0;
    assign sample_high_count_out = last_sample_high_count;

    localparam sampling_cycles = 128;

    reg [15:0] sampling_counter = sampling_cycles - 1;
    reg [15:0] sample_high_count = 0;
    reg [15:0] last_sample_high_count = 0;
    always @(posedge pwm_clk) begin
        if(sampling_counter == 0) begin
            sampling_counter <= sampling_cycles - 1;
            last_sample_high_count <= sample_high_count;
            sample_high_count <= 0;
        end else begin
            sampling_counter <= sampling_counter - 1;
            if(diff_in) begin
                sample_high_count <= sample_high_count + 1;
            end
        end
    end
endmodule

module selector(
    input [2:0] row,
    input [2:0] col,
    output [1:0] uplex,
    output [3:0] uinput
    );

    wire [3:0] rrow = row;
    wire [3:0] rcol = col;

    // 0 is the last with only one row
    wire [1:0] urow = 3 - (rrow / 2);

    // urow pins are reversed
    assign uplex[0] = urow[0];
    assign uplex[1] = urow[1];
    assign uinput = rcol + ((rrow) % 2) * 9;

endmodule

// clk is 12Mhz, 40 khz is a ratio of 300

module top(input clk, output [7:0] led, 
    input diff_in_sel,
    input diff_in_center,
    output diff_out,
    output [1:0] uplex,
    output [3:0] uinput,
    // TFT
    output tft_clk,
    output hsync,
    output vsync,
    output reg blue = 0,
    output de
    );


    // 60Mhz, 1500 to 1 ratio
    wire pwm_clk;


    pll_linux pll(
        .clkin(clk), // 12 MHz, 0 deg
        .clkout0(pwm_clk), // 60 MHz, 0 deg
        .clkout1(),
        .clkout2(), 
        .clkout3(), 
        .locked()
    );

    reg [25:0] c = 0;

    always @(posedge clk) begin
        c <= c + 1;
    end

    // Single 40khz cycle
    localparam sampling_cycles = 128;

    wire [15:0] sample_out_count_center;
    wire [15:0] sample_out_count_sel;

    diff_sampler center_sampler(
        .pwm_clk(pwm_clk),
        .diff_in(diff_in_center),
        .sample_high_count_out(sample_out_count_center));

    diff_sampler sel_sampler(
        .pwm_clk(pwm_clk),
        .diff_in(diff_in_sel),
        .sample_high_count_out(sample_out_count_sel));


    reg [15:0] mixed = 0;
    reg [31:0] last_mixed_accum = 0;
    reg [31:0] mixed_accum = 0;
    localparam mixed_accum_cycles = 1200;
    reg [15:0] mixed_accum_count = 0;
    always @(posedge pwm_clk) begin
        mixed <= sample_out_count_sel * sample_out_count_center;

        if (mixed_accum_count == mixed_accum_cycles) begin
            mixed_accum_count <= 0;
            last_mixed_accum <= mixed_accum;
            mixed_accum <= 0;
        end else begin
            mixed_accum_count <= mixed_accum_count + 1;
            mixed_accum <= mixed_accum + mixed;
        end
    end

    wire [31:0] rand_out;
    LFSR_rng rng(.clk(pwm_clk), .rand_out(rand_out));


    reg [2:0] rrowc = 0;
    reg [2:0] rcolc = 0;
    
    reg [15:0] display[7][7];

//    always @(posedge c[21]) begin
    always @(posedge c[14]) begin
        // TODO: Magic
        display[rrowc][rcolc] <= last_mixed_accum >> 16;

        if (rcolc == 6) begin
            rcolc <= 0;
            if (rrowc == 6) begin
                rrowc <= 0;
            end else begin
                rrowc <= rrowc + 1;
            end
        end else begin
            rcolc <= rcolc + 1;
        end
    end


    selector selector(
//        .row(rrowc),
//        .col(rcolc),
        .row(rrowc),
        .col(rcolc),
        .uplex(uplex),
        .uinput(uinput)
    );




//    assign diff_out = (sample_out_count_sel > rand_out[6:0]);
    assign diff_out = (mixed > rand_out[6:0]);
//    assign led = (rrow == 3) && (rcol == 3);
    assign led = 0;


    wire [9:0] pos_x;
    wire [9:0] pos_y;

    tft_driver tft_driver(.clk(clk), 
        .tft_clk(tft_clk),
        .hsync(hsync),
        .vsync(vsync),
        .de(de),
        .pos_x(pos_x),
        .pos_y(pos_y));


    reg [22:0] timer = 0;

    always @(posedge clk) begin
        timer <= timer + 1;
    end

//    wire [9:0] added_x = pos_x + timer[22:19];
//    wire [9:0] added_y = pos_y + timer[22:19];
//    assign blue = added_x[3] ^ added_y[3];

    wire [31:0] rand_out_slow;
    LFSR_rng rng_slow(.clk(clk), .rand_out(rand_out_slow));


    always @(posedge clk) begin
//        blue <= (mixed > rand_out_fast[6:0]);
        if (pos_x < (32*7) && (pos_y < (32*7))) begin
            // TODO: Magic
            blue <= display[7 - pos_y / 32][7 - pos_x / 32] > rand_out_slow[6:0];
        end else begin
            blue <= 0;
        end
    end


endmodule


