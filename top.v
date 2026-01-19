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

// clk is 12Mhz, 40 khz is a ratio of 300

module top(input clk, output [7:0] led, 
    input diff_in_sel,
    input diff_in_center,
    output diff_out,
    output sw_out0,
    output sw_out1,
    output [1:0] uplex,
    output [3:0] uinput
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

    wire [31:0] rand_out;
    LFSR_rng rng(.clk(pwm_clk), .rand_out(rand_out));


    assign sw_out0 = c[22];
    assign sw_out1 = 0;
//    assign sw_out1 = ~c[22]; 

    reg [2:0] rrowc = 0;
    reg [2:0] rcolc = 0;
    
    always @(posedge c[21]) begin
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


    wire [3:0] rrow = rrowc;
    wire [3:0] rcol = rcolc;

    // 0 is the last with only one row
    wire [1:0] urow = 3 - (rrow / 2);

    // urow pins are reversed
    assign uplex[0] = urow[0];
    assign uplex[1] = urow[1];
    assign uinput = rcol + ((rrow) % 2) * 9;

    assign diff_out = (sample_out_count_sel > rand_out[6:0]);
    assign led = (rrow == 3) && (rcol == 3);

endmodule


