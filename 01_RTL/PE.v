// `include "Cordic.v"
module PE (
    i_clk,
    i_rst,
    i_trig,
    i_real_x,
    i_imag_x,
    i_real_y,
    i_imag_y,
    i_mode_x,
    i_mode_y,
    o_real_x,
    o_imag_x,
    o_real_y,
    o_imag_y,
    o_mode_x,
    o_mode_y,
    o_finish
);
    

    localparam M_VECTORING = 1'b1;
    localparam M_ROTATION = 1'b0;

    localparam IN_WIDTH      = 12; //S3.22
    localparam OUT_WIDTH     = 12; //S3.22
    localparam NUM_ITERATION = 6; //Angle precision is control by this localparam, fixed to 15 for hardware convenient
    localparam HIDDEN_WIDTH  = 12; //S3.22

    //Kn = 0.607253 when NUM_ITERATION > 8 (= 0.10011011011101001111 in binary)
    //max = 2.82/0.607253 = 4.643
    
    input                         i_clk, i_trig, i_rst, i_mode_x, i_mode_y;
    input  signed [IN_WIDTH-1:0]  i_real_x, i_imag_x, i_real_y, i_imag_y;
    output        [OUT_WIDTH-1:0] o_real_x, o_imag_x, o_real_y, o_imag_y;
    output                        o_mode_x, o_mode_y;
    output                        o_finish;
    
    wire          [HIDDEN_WIDTH-1:0] tmp_1_x, tmp_1_y, tmp_2_x, tmp_2_y, tmp_4_x_in, tmp_4_y_in, tmp_4_x;
    reg                              tmp_finish;
    wire                             mode;
    reg                              mode_x, mode_y;
    reg  [4-1:0]                     count;

    assign mode = i_trig ? i_mode_x : mode_x; //bug, mode would delay one cycle to change to i_mode_x

    reg select;

    // wire select_w = i_trig ? 1'b0 : tmp_finish ? 1'b1 : select; //priority i_trig > tmp 1 finish
    wire select_w = (count < NUM_ITERATION) ? select :
                                     i_trig ?   1'b0 : 1'b1; //priority i_trig > tmp 1 finish
    assign o_finish = select & tmp_finish; //global finish
    wire [IN_WIDTH-1:0] tmp_1_x_in = (select_w == 0) ? i_real_x : tmp_1_x;
    wire [IN_WIDTH-1:0] tmp_1_y_in = (select_w == 0) ? i_imag_x : tmp_2_x;
    wire [IN_WIDTH-1:0] tmp_2_x_in = (select_w == 0) ? i_real_y : tmp_4_x_in;
    wire [IN_WIDTH-1:0] tmp_2_y_in = (select_w == 0) ? i_imag_y : tmp_4_y_in;
    wire tmp_trig = i_trig | (tmp_finish & (select == 0)); //second one is local trig
    assign o_real_x = tmp_1_x;
    assign o_real_y = tmp_1_y;
    assign o_imag_x = (mode_x == M_VECTORING) ? o_real_y : tmp_2_x;
    assign o_imag_y = tmp_2_y;
    
    assign tmp_4_x_in = (mode_x == M_VECTORING) ? tmp_1_x : tmp_1_y;
    assign tmp_4_y_in = (mode_x == M_VECTORING) ? tmp_2_x : tmp_2_y;
    assign o_mode_x = mode_x;
    assign o_mode_y = mode_y;

    
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin //Could be deleted
            count <= NUM_ITERATION;
        end
        else begin
            if (tmp_trig) begin //Preprocessing, rotate to 1st or 4th octant
                count <= 0;
            end
            else if (count < NUM_ITERATION) begin
                count <= count + 1;
            end
        end
    end

    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin 
            tmp_finish <= 0;
        end
        else begin
            if (count == NUM_ITERATION - 1) begin
                tmp_finish <= 1;
            end
            else begin
                tmp_finish <= 0;
            end
        end
    end

    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            mode_x <= 0;
            mode_y <= 0;
        end
        else if (i_trig) begin
            mode_x <= i_mode_x;
            mode_y <= i_mode_y;
        end
    end
    
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            select <= 0;
        end
        else if (i_trig) begin //priority i_trig > tmp 1 finish
            select <= 0;
        end
        else if (tmp_finish) begin
            select <= 1;
        end
    end

    //Time 1
    Cordic_2 Cordic_1 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_trig(tmp_trig),
        .i_mode(mode),
        .i_x(tmp_1_x_in),
        .i_y(tmp_1_y_in),
        .i_select(select_w),
        .i_count(count),
        .o_x(tmp_1_x),
        .o_y(tmp_1_y)
        // .o_finish(tmp_finish)
    );

    Cordic_2 Cordic_2 (
        .i_clk(i_clk),
        .i_rst(i_rst),
        .i_trig(tmp_trig),
        .i_mode(mode),
        .i_x(tmp_2_x_in),
        .i_y(tmp_2_y_in),
        .i_select(select_w),
        .i_count(count),
        .o_x(tmp_2_x),
        .o_y(tmp_2_y)
        // .o_finish() //because Cordic_1 and 2 will finish at the same time
    );

    //Time 2
    // Cordic_2 Cordic_3 (
    //     .i_clk(i_clk),
    //     .i_rst(i_rst),
    //     .i_trig(tmp_finish),
    //     .i_mode(mode),
    //     .i_x(tmp_1_x),
    //     .i_y(tmp_2_x),
    //     .o_x(o_real_x),
    //     .o_y(o_real_y),
    //     .o_finish(o_finish)
    // );

    // Cordic_2 Cordic_4 (
    //     .i_clk(i_clk),
    //     .i_rst(i_rst),
    //     .i_trig(tmp_finish), //because Cordic_3 and 4 should be triggered at the same time
    //     .i_mode(mode),
    //     .i_x(tmp_4_x_in),
    //     .i_y(tmp_4_y_in),
    //     .o_x(tmp_4_x),
    //     .o_y(o_imag_y),
    //     .o_finish() //because Cordic_3 and 4 will finish at the same time
    // );

endmodule
//can share cordic...