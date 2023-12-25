// `include "Cordic.v"
module RU (
    i_clk,
    i_rst,
    i_trig,
    i_real_y,
    i_imag_y,
    i_mode_y,
    o_real_x,
    o_imag_x,
    o_mode_x,
    o_finish
);

    localparam IN_WIDTH      = 12; //S3.22
    localparam OUT_WIDTH     = 12; //S3.22

    input                         i_clk, i_trig, i_rst, i_mode_y;
    input  signed [IN_WIDTH-1:0]  i_real_y, i_imag_y;
    output        [OUT_WIDTH-1:0] o_real_x, o_imag_x;
    output                        o_mode_x;
    output                        o_finish;

    reg mode_x;
    wire mode;

    assign o_mode_x = mode_x;

    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            mode_x <= 0;
        end
        else if (i_trig) begin
            mode_x <= i_mode_y;
        end
    end
    
    assign mode = i_trig ? i_mode_y : mode_x;

    //Time 1
    Cordic Cordic_1 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_trig(i_trig),
        .i_mode(mode),
        .i_x(i_real_y),
        .i_y(i_imag_y),
        .o_x(o_real_x),
        .o_y(o_imag_x),
        .o_finish(o_finish)
    );
 
    // DU DU #(
    //     .NUM_ITERATION(16)
    // )(
    //     .i_clk(i_clk),
    //     .i_rst(i_rst),
    //     .i_trig(tmp_finish),
    //     .i_real_y(tmp_real_x),
    //     .i_imag_y(tmp_imag_x),
    //     .i_mode_y(),
    //     .o_real_x(o_real_x),
    //     .o_imag_x(o_imag_x),
    //     .o_mode_x(),
    //     .o_finish(o_finish) //For debugging, could be deleted afterwards
    // );

endmodule