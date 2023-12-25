module DU (
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
    // localparam NUM_ITERATION = 31; //31+1
    localparam CORDIC_ITER = 6;
    localparam NUM_ITERATION = CORDIC_ITER*2+1; //17+1

    input                         i_clk, i_trig, i_rst, i_mode_y;
    input  signed [IN_WIDTH-1:0]  i_real_y, i_imag_y;
    output        [OUT_WIDTH-1:0] o_real_x, o_imag_x;
    output                        o_mode_x;
    output reg                    o_finish;
    
    reg [6-1:0]        count;
    reg                mode;
    reg [IN_WIDTH-1:0] real_y, imag_y;

    assign o_mode_x = mode;
    assign o_real_x = real_y;
    assign o_imag_x = imag_y;
    
    //Time 1
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            count <= NUM_ITERATION;
            o_finish <= 0;
            mode <= 0;
            real_y <= 0;
            imag_y <= 0;
        end
        else if (i_trig) begin
            count <= 0;
            o_finish <= 0;
            mode <= i_mode_y;
            real_y <= i_real_y;
            imag_y <= i_imag_y;
        end
        else if (count < NUM_ITERATION) begin //lock
            count <= count + 1;
            if (count == NUM_ITERATION - 1) begin
                o_finish <= 1;
            end
            else begin
                o_finish <= 0;
            end
        end
        else begin
            o_finish <= 0;
            // mode <= i_mode_y;
            // real_y <= i_real_y;
            // imag_y <= i_imag_y;
        end
    end
endmodule
