//Cordic 2 has two tables
module Cordic_2 (
    i_clk,
    i_rst,
    i_trig,
    i_x,
    i_y,
    i_mode,
    i_select,
    i_count,
    o_x,
    o_y
);

    localparam M_VECTORING = 1'b1;
    localparam M_ROTATION = 1'b0;

    localparam IN_WIDTH      = 12; //S3.22 //originally S1.22 and S2.22, take all to be S3.22 for fixed modulization
    localparam OUT_WIDTH     = 12; //S3.22 //Fraction width can be changed to trade precision //max = 2.82
    localparam NUM_ITERATION = 6; //Angle precision is control by this localparam, fixed to 15 for hardware convenient
    // localparam NUM_ITERATION = 31; //Angle precision is control by this localparam, fixed to 15 for hardware convenient
    // localparam HIDDEN_WIDTH  = 1  +  26  +  0; //S? + 3.22 + ?
    // localparam HIDDEN_WIDTH  = 0 + 26  +  0; //S? + 3.22 + ?
    localparam HIDDEN_WIDTH  = 12; //S? + 3.22 + ?

    //Kn = 0.607253 when NUM_ITERATION > 8 (= 0.10011011011101001111 in binary)
    //max = 2.82/0.607253 = 4.643
    
    input                         i_clk, i_trig, i_rst, i_mode, i_select;
    input         [4-1:0]         i_count;
    input  signed [IN_WIDTH-1:0]  i_x, i_y;
    // output                  o_angle_rotate_sequence;
    output        [OUT_WIDTH-1:0] o_x, o_y;
    // output reg                    o_finish;

    reg signed [HIDDEN_WIDTH-1:0] x;
    reg signed [HIDDEN_WIDTH-1:0] y;
    // reg  [4-1:0]              count;
    reg                       rotate_sequence[0:1][0:NUM_ITERATION];
    // wire signed [HIDDEN_WIDTH-1:0] x_shift_by_count;
    // wire signed [HIDDEN_WIDTH-1:0] y_shift_by_count;
    // assign x_shift_by_count = x >>> i_count;
    // assign y_shift_by_count = y >>> i_count;
    // reg signed [HIDDEN_WIDTH-1:0] x_shift_by_count;
    // reg signed [HIDDEN_WIDTH-1:0] y_shift_by_count;

    // always @(*) begin
        // case (i_count) //NUM_ITERATION = 6
        //     3'd0: begin
        //         x_shift_by_count = x;
        //         y_shift_by_count = y;
        //     end
        //     3'd1: begin
        //         x_shift_by_count = {x[HIDDEN_WIDTH-1], x[HIDDEN_WIDTH-1:1]};
        //         y_shift_by_count = {y[HIDDEN_WIDTH-1], y[HIDDEN_WIDTH-1:1]};
        //     end
        //     3'd2: begin
        //         x_shift_by_count = {{2{x[HIDDEN_WIDTH-1]}}, x[HIDDEN_WIDTH-1:2]};
        //         y_shift_by_count = {{2{y[HIDDEN_WIDTH-1]}}, y[HIDDEN_WIDTH-1:2]};
        //     end
        //     3'd3: begin
        //         x_shift_by_count = {{3{x[HIDDEN_WIDTH-1]}}, x[HIDDEN_WIDTH-1:3]};
        //         y_shift_by_count = {{3{y[HIDDEN_WIDTH-1]}}, y[HIDDEN_WIDTH-1:3]};
        //     end
        //     3'd4: begin
        //         x_shift_by_count = {{4{x[HIDDEN_WIDTH-1]}}, x[HIDDEN_WIDTH-1:4]};
        //         y_shift_by_count = {{4{y[HIDDEN_WIDTH-1]}}, y[HIDDEN_WIDTH-1:4]};
        //     end
        //     3'd5: begin
        //         x_shift_by_count = {{5{x[HIDDEN_WIDTH-1]}}, x[HIDDEN_WIDTH-1:5]};
        //         y_shift_by_count = {{5{y[HIDDEN_WIDTH-1]}}, y[HIDDEN_WIDTH-1:5]};
        //     end
        //     default: begin
        //         x_shift_by_count = x;
        //         y_shift_by_count = y;
        //     end
        // endcase
    // end

    // wire [HIDDEN_WIDTH-1:0] x_positive_rotate;
    // wire [HIDDEN_WIDTH-1:0] y_positive_rotate;
    // wire [HIDDEN_WIDTH-1:0] x_negative_rotate;
    // wire [HIDDEN_WIDTH-1:0] y_negative_rotate;

    // assign x_positive_rotate = x - y_shift_by_count;
    // assign y_positive_rotate = y + x_shift_by_count;
    // assign x_negative_rotate = x + y_shift_by_count;
    // assign y_negative_rotate = y - x_shift_by_count;
    
    // wire [HIDDEN_WIDTH-1:0] x_positive_rotate = x - (y >>> i_count);
    // wire [HIDDEN_WIDTH-1:0] y_positive_rotate = y + (x >>> i_count);
    // wire [HIDDEN_WIDTH-1:0] x_negative_rotate = x + (y >>> i_count);
    // wire [HIDDEN_WIDTH-1:0] y_negative_rotate = y - (x >>> i_count);

    wire [HIDDEN_WIDTH-1:0] x_count = x >>> i_count;
    wire [HIDDEN_WIDTH-1:0] y_count = y >>> i_count;
    wire condition_0 = (i_mode == M_VECTORING) ? i_x[IN_WIDTH-1] : rotate_sequence[i_select][NUM_ITERATION];
    wire condition   = (i_mode == M_VECTORING) ? y[HIDDEN_WIDTH-1] : rotate_sequence[i_select][i_count];
    wire signed [HIDDEN_WIDTH-1:0] x_shift_by_count = condition ? x_count : - x_count;
    wire signed [HIDDEN_WIDTH-1:0] y_shift_by_count = condition ? -y_count : y_count;

    ///////////////////////////////
    // wire signed [HIDDEN_WIDTH-1:0] a = (i_count == NUM_ITERATION) ? (x >>> 1) : x;
    // wire signed [HIDDEN_WIDTH-1:0] b = (i_count == NUM_ITERATION) ? (x >>> 3) : y_shift_by_count;
    // wire signed [HIDDEN_WIDTH-1:0] c = (i_count == NUM_ITERATION) ? (y >>> 1) : y;
    // wire signed [HIDDEN_WIDTH-1:0] d = (i_count == NUM_ITERATION) ? (y >>> 3) : x_shift_by_count;

    // wire signed [HIDDEN_WIDTH-1:0] x_rotate = a + b;
    // wire signed [HIDDEN_WIDTH-1:0] y_rotate = c + d;
    // assign o_x = x_rotate[HIDDEN_WIDTH-1-:OUT_WIDTH];
    // assign o_y = y_rotate[HIDDEN_WIDTH-1-:OUT_WIDTH];
    
    ////////////////////////////////
    wire [HIDDEN_WIDTH-1:0] x_rotate = x + y_shift_by_count;
    wire [HIDDEN_WIDTH-1:0] y_rotate = y + x_shift_by_count;

    // // wire [HIDDEN_WIDTH-1:0] x_times_Kn = (x >>> 1) + (x >>> 3); //0.10011011011101001111
    // wire [HIDDEN_WIDTH-1:0] y_times_Kn = (y >>> 1) + (y >>> 3);
    wire [HIDDEN_WIDTH-1:0] x_times_Kn = (i_count == NUM_ITERATION) ? (x >>> 1) + (x >>> 3) : 0; //0.10011011011101001111
    wire [HIDDEN_WIDTH-1:0] y_times_Kn = (i_count == NUM_ITERATION) ? (y >>> 1) + (y >>> 3) : 0;
    assign o_x = x_times_Kn[HIDDEN_WIDTH-1-:OUT_WIDTH];
    assign o_y = y_times_Kn[HIDDEN_WIDTH-1-:OUT_WIDTH];
    ////////////////////////////////

    integer i;

    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin 
            x <= 0;
            y <= 0;
        end
        else if (i_count < NUM_ITERATION) begin
            // if (y[HIDDEN_WIDTH-1]) begin
            //     x <= x_positive_rotate;
            //     y <= y_positive_rotate;
            // end
            // else begin
            //     x <= x_negative_rotate;
            //     y <= y_negative_rotate;
            // end
            x <= x_rotate;
            y <= y_rotate;
        end
        // else if (i_count == NUM_ITERATION) begin
        else if (i_trig) begin
            x <= condition_0 ? -i_x : i_x;
            y <= condition_0 ? -i_y : i_y;
        end
        // else begin
        //     if (i_mode == M_VECTORING) begin
        //         if (i_count < NUM_ITERATION) begin
        //             if (y[HIDDEN_WIDTH-1]) begin
        //                 x <= x_positive_rotate;
        //                 y <= y_positive_rotate;
        //             end
        //             else begin
        //                 x <= x_negative_rotate;
        //                 y <= y_negative_rotate;
        //             end
        //         end
        //         // else if (i_count == NUM_ITERATION) begin
        //         else if (i_trig) begin
        //             x <= (i_x[IN_WIDTH-1]) ? -i_x : i_x;
        //             y <= (i_x[IN_WIDTH-1]) ? -i_y : i_y;
        //         end
        //     end
        //     else begin //i_mode = M_ROTATION
        //         if (i_count < NUM_ITERATION) begin
        //             if (rotate_sequence[i_select][i_count]) begin
        //                 x <= x_positive_rotate;
        //                 y <= y_positive_rotate;
        //             end
        //             else begin
        //                 x <= x_negative_rotate;
        //                 y <= y_negative_rotate;
        //             end
        //         end
        //         else if (i_trig) begin
        //         // else if (i_count == NUM_ITERATION) begin
        //             x <= (rotate_sequence[i_select][NUM_ITERATION]) ? -i_x : i_x;
        //             y <= (rotate_sequence[i_select][NUM_ITERATION]) ? -i_y : i_y;
        //         end
        //     end
        // end
    end

    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            for (i = 0; i <= NUM_ITERATION; i = i + 1) begin
                rotate_sequence[0][i] <= 0;
                rotate_sequence[1][i] <= 0;
            end
        end
        else begin
            if (i_mode == M_VECTORING) begin
                if (i_trig) begin //Preprocessing, rotate to 1st or 4th octant
                    rotate_sequence[i_select][NUM_ITERATION] <= i_x[IN_WIDTH-1];
                end
                else if (i_count < NUM_ITERATION) begin
                    rotate_sequence[i_select][i_count] <= y[HIDDEN_WIDTH-1];
                end
            end
        end
    end

    // always @(posedge i_clk or posedge i_rst) begin
    //     if (i_rst) begin //Could be deleted
    //         count <= NUM_ITERATION;
    //     end
    //     else begin
    //         if (i_trig) begin //Preprocessing, rotate to 1st or 4th octant
    //             count <= 0;
    //         end
    //         else if (count < NUM_ITERATION) begin
    //             count <= count + 1;
    //         end
    //     end
    // end

    // always @(posedge i_clk or posedge i_rst) begin
    //     if (i_rst) begin 
    //         o_finish <= 0;
    //     end
    //     else begin
    //         if (count == NUM_ITERATION - 1) begin
    //             o_finish <= 1;
    //         end
    //         else begin
    //             o_finish <= 0;
    //         end
    //     end
    // end




    // wire [HIDDEN_WIDTH-1:0] x_times_Kn = (x >>> 1) + (x >>> 3) + 64; //0.10011011011101001111
    // wire [HIDDEN_WIDTH-1:0] y_times_Kn = (y >>> 1) + (y >>> 3) + 64;
    // wire [HIDDEN_WIDTH-1:0] x_times_Kn = (count >= NUM_ITERATION) ? ((x >>> 1) + (x >>> 3)) : 0; //0.10011011011101001111
    // wire [HIDDEN_WIDTH-1:0] y_times_Kn = (count >= NUM_ITERATION) ? ((y >>> 1) + (y >>> 3)) : 0; //0.10100(-1)00(-1)00(-1)0101000(-1)

    //For iter=6, Kn=0.1001101101111011011
    // wire [HIDDEN_WIDTH-1:0]  x_times_Kn = (x >>> 1) + (x >>> 4) + (x >>> 5) + (x >>> 7) + (x >>> 8) + (x >>> 10) + (x >>> 11) + (x >>> 12) + (x >>> 13) + (x >>> 15) + (x >>> 16) + (x >>> 18) + (x >>> 19); //0.100110   110   111   01001111
    // wire [HIDDEN_WIDTH-1:0]  y_times_Kn = (y >>> 1) + (y >>> 4) + (y >>> 5) + (y >>> 7) + (y >>> 8) + (y >>> 10) + (y >>> 11) + (y >>> 12) + (y >>> 13) + (y >>> 15) + (y >>> 16) + (y >>> 18) + (y >>> 19); //0.10100(-1)00(-1)00(-1)0101000(-1)
    // wire [HIDDEN_WIDTH-1:0]  x_times_Kn = (x >>> 1) + (x >>> 4) + (x >>> 5) + (x >>> 7) + (x >>> 8) + (x >>> 10) + (x >>> 11) + (x >>> 12) + (x >>> 14) + (x >>> 16); //0.100110   110   111   01001111
    // wire [HIDDEN_WIDTH-1:0]  y_times_Kn = (y >>> 1) + (y >>> 4) + (y >>> 5) + (y >>> 7) + (y >>> 8) + (y >>> 10) + (y >>> 11) + (y >>> 12) + (y >>> 14) + (y >>> 16); //0.10100(-1)00(-1)00(-1)0101000(-1)
    // wire [HIDDEN_WIDTH+12-1:0]  x_times_Kn = (x << 11) + (x << 8) + (x << 7) + (x << 5) + (x << 4) + (x << 2) + (x << 1) + x; //0.10011011011101001111
    // wire [HIDDEN_WIDTH+12-1:0]  y_times_Kn = (y << 11) + (y << 8) + (y << 7) + (y << 5) + (y << 4) + (y << 2) + (y << 1) + y;

    // assign o_x = x_times_Kn[HIDDEN_WIDTH-2-:OUT_WIDTH];
    // assign o_y = y_times_Kn[HIDDEN_WIDTH-2-:OUT_WIDTH];
    // assign o_x = x_times_Kn[HIDDEN_WIDTH+12-1-:OUT_WIDTH];
    // assign o_y = y_times_Kn[HIDDEN_WIDTH+12-1-:OUT_WIDTH];
endmodule

//can change to add x>>>12 and x>>>11 early, ... because that would not change much


/*//Cordic 2 has two tables
module Cordic_2 (
    i_clk,
    i_rst,
    i_trig,
    i_x,
    i_y,
    i_mode,
    i_select,
    // o_angle_rotate_sequence, //no need to determine the precision of angle
    o_x,
    o_y,
    o_finish //For debugging, could be deleted afterwards
);

    localparam M_VECTORING = 1'b1;
    localparam M_ROTATION = 1'b0;

    localparam IN_WIDTH      = 26; //S3.22 //originally S1.22 and S2.22, take all to be S3.22 for fixed modulization
    localparam OUT_WIDTH     = 26; //S3.22 //Fraction width can be changed to trade precision //max = 2.82
    localparam NUM_ITERATION = 6; //Angle precision is control by this localparam, fixed to 15 for hardware convenient
    // localparam NUM_ITERATION = 31; //Angle precision is control by this localparam, fixed to 15 for hardware convenient
    localparam HIDDEN_WIDTH  = 1  +  26  +  0; //S? + 3.22 + ?

    //Kn = 0.607253 when NUM_ITERATION > 8 (= 0.10011011011101001111 in binary)
    //max = 2.82/0.607253 = 4.643
    
    input                         i_clk, i_trig, i_rst, i_mode, i_select;
    input  signed [IN_WIDTH-1:0]  i_x, i_y;
    // output                  o_angle_rotate_sequence;
    output        [OUT_WIDTH-1:0] o_x, o_y;
    output reg                    o_finish;

    reg signed [HIDDEN_WIDTH-1:0] x;
    reg signed [HIDDEN_WIDTH-1:0] y;
    reg  [4-1:0]              count;
    // reg  [5-1:0]              count;
    reg                       rotate_sequence[0:1][0:NUM_ITERATION];

    integer i;

    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin 
            x <= 0;
            y <= 0;
        end
        else if (i_select) begin
            if (i_mode == M_VECTORING) begin
                if (count < NUM_ITERATION) begin
                    if (y[HIDDEN_WIDTH-1]) begin
                        x <= x - (y >>> count);
                        y <= (x >>> count) + y;
                    end
                    else begin
                        x <= x + (y >>> count);
                        y <= -(x >>> count) + y;
                    end
                end
                else begin
                    x <= (i_x[IN_WIDTH-1]) ? -i_x : i_x;
                    y <= (i_x[IN_WIDTH-1]) ? -i_y : i_y;
                end
            end
            else begin //i_mode = M_ROTATION
                if (count < NUM_ITERATION) begin
                    if (rotate_sequence[1][count]) begin
                        x <= x - (y >>> count);
                        y <= (x >>> count) + y;
                    end
                    else begin
                        x <= x + (y >>> count);
                        y <= -(x >>> count) + y;
                    end
                end
                else begin
                    x <= (rotate_sequence[1][NUM_ITERATION]) ? -i_x : i_x;
                    y <= (rotate_sequence[1][NUM_ITERATION]) ? -i_y : i_y;
                end
            end
        end
        else begin
            if (i_mode == M_VECTORING) begin
                if (count < NUM_ITERATION) begin
                    if (y[HIDDEN_WIDTH-1]) begin
                        x <= x - (y >>> count);
                        y <= (x >>> count) + y;
                    end
                    else begin
                        x <= x + (y >>> count);
                        y <= -(x >>> count) + y;
                    end
                end
                else begin
                    x <= (i_x[IN_WIDTH-1]) ? -i_x : i_x;
                    y <= (i_x[IN_WIDTH-1]) ? -i_y : i_y;
                end
            end
            else begin //i_mode = M_ROTATION
                if (count < NUM_ITERATION) begin
                    if (rotate_sequence[0][count]) begin
                        x <= x - (y >>> count);
                        y <= (x >>> count) + y;
                    end
                    else begin
                        x <= x + (y >>> count);
                        y <= -(x >>> count) + y;
                    end
                end
                else begin
                    x <= (rotate_sequence[0][NUM_ITERATION]) ? -i_x : i_x;
                    y <= (rotate_sequence[0][NUM_ITERATION]) ? -i_y : i_y;
                end
            end
        end
    end

    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin 
            o_finish <= 0;
        end
        else if (i_select) begin
            if (i_mode == M_VECTORING) begin
                if (count == NUM_ITERATION - 1) begin
                    o_finish <= 1;
                end
                else begin
                    o_finish <= 0;
                end
            end
            else begin //i_mode = M_ROTATION
                if (count == NUM_ITERATION - 1) begin
                    o_finish <= 1;
                end
                else begin
                    o_finish <= 0;
                end
            end
        end
        else begin
            if (i_mode == M_VECTORING) begin
                if (count == NUM_ITERATION - 1) begin
                    o_finish <= 1;
                end
                else begin
                    o_finish <= 0;
                end
            end
            else begin //i_mode = M_ROTATION
                if (count == NUM_ITERATION - 1) begin
                    o_finish <= 1;
                end
                else begin
                    o_finish <= 0;
                end
            end
        end
    end


    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin //Could be deleted
            count <= NUM_ITERATION;
            for (i = 0; i <= NUM_ITERATION; i = i + 1) begin
                rotate_sequence[0][i] <= 0;
                rotate_sequence[1][i] <= 0;
            end
        end
        else if (i_select) begin
            if (i_mode == M_VECTORING) begin
                if (i_trig) begin //Preprocessing, rotate to 1st or 4th octant
                    count <= 0;
                    rotate_sequence[1][NUM_ITERATION] <= i_x[IN_WIDTH-1];
                end
                else if (count < NUM_ITERATION) begin
                    count <= count + 1;
                    rotate_sequence[1][count] <= y[HIDDEN_WIDTH-1];
                end
            end
            else begin //i_mode = M_ROTATION
                if (i_trig) begin
                    count <= 0;
                end
                else if (count < NUM_ITERATION) begin
                    count <= count + 1;
                end
            end
        end
        else begin
            if (i_mode == M_VECTORING) begin
                if (i_trig) begin //Preprocessing, rotate to 1st or 4th octant
                    count <= 0;
                    rotate_sequence[0][NUM_ITERATION] <= i_x[IN_WIDTH-1];
                end
                else if (count < NUM_ITERATION) begin
                    count <= count + 1;
                    rotate_sequence[0][count] <= y[HIDDEN_WIDTH-1];
                end
            end
            else begin //i_mode = M_ROTATION
                if (i_trig) begin
                    count <= 0;
                end
                else if (count < NUM_ITERATION) begin
                    count <= count + 1;
                end
            end
        end
    end

    wire [HIDDEN_WIDTH-1:0] x_times_Kn = (x >>> 1) + (x >>> 3); //0.10011011011101001111
    wire [HIDDEN_WIDTH-1:0] y_times_Kn = (y >>> 1) + (y >>> 3);

    // wire [HIDDEN_WIDTH-1:0] x_times_Kn = (count >= NUM_ITERATION) ? ((x >>> 1) + (x >>> 3)) : 0; //0.10011011011101001111
    // wire [HIDDEN_WIDTH-1:0] y_times_Kn = (count >= NUM_ITERATION) ? ((y >>> 1) + (y >>> 3)) : 0; //0.10100(-1)00(-1)00(-1)0101000(-1)

    // wire [HIDDEN_WIDTH-1:0]  x_times_Kn = (x >>> 1) + (x >>> 4) + (x >>> 5) + (x >>> 7) + (x >>> 8) + (x >>> 10) + (x >>> 11) + (x >>> 12) + (x >>> 14) + (x >>> 16); //0.100110   110   111   01001111
    // wire [HIDDEN_WIDTH-1:0]  y_times_Kn = (y >>> 1) + (y >>> 4) + (y >>> 5) + (y >>> 7) + (y >>> 8) + (y >>> 10) + (y >>> 11) + (y >>> 12) + (y >>> 14) + (y >>> 16); //0.10100(-1)00(-1)00(-1)0101000(-1)
    // wire [HIDDEN_WIDTH+12-1:0]  x_times_Kn = (x << 11) + (x << 8) + (x << 7) + (x << 5) + (x << 4) + (x << 2) + (x << 1) + x; //0.10011011011101001111
    // wire [HIDDEN_WIDTH+12-1:0]  y_times_Kn = (y << 11) + (y << 8) + (y << 7) + (y << 5) + (y << 4) + (y << 2) + (y << 1) + y;
    assign o_x = x_times_Kn[HIDDEN_WIDTH-2-:OUT_WIDTH];
    assign o_y = y_times_Kn[HIDDEN_WIDTH-2-:OUT_WIDTH];
    // assign o_x = x_times_Kn[HIDDEN_WIDTH+12-1-:OUT_WIDTH];
    // assign o_y = y_times_Kn[HIDDEN_WIDTH+12-1-:OUT_WIDTH];
endmodule

//can change to add x>>>12 and x>>>11 early, ... because that would not change much


*/