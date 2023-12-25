`include "PE.v"
`include "DU.v"
`include "RU.v"
`include "Cordic.v"
`include "Cordic_2.v"

module QR_Engine (
    i_clk,
    i_rst,
    i_trig,
    i_data,
    o_rd_vld,
    o_last_data,
    o_y_hat,
    o_r
);

    // IO description
    input          i_clk;
    input          i_rst;
    input          i_trig;
    input  [ 47:0] i_data;
    output         o_rd_vld;
    output         o_last_data;
    output [159:0] o_y_hat;
    output [319:0] o_r;


    //In this project, H and y are S1.22, output y and R are S3.16
    localparam IN_WIDTH      = 12; //S3.22
    localparam OUT_WIDTH     = 20; //S3.16
    localparam CORDIC_ITER   = 6;
    localparam NUM_ITERATION = CORDIC_ITER*2+2; //17+1

    integer i, j;

    reg                    i_trig_buf;
    reg  [47:0]            i_data_buf;
    reg [48-1:0]           FIFO[0:3][0:4]; //ex. H11 H12 H13 H14 y1
    reg [3-1:0]            count_to_4_for_intra_FIFO; //input FIFO
    reg [3-1:0]            count_to_4_for_pipeline; //based on PE trig signal to count. for loading new column. y finish
    reg [2-1:0]            count_to_3_for_inter_FIFO; //select FIFO
    reg [4-1:0]            count_to_9_for_inter_RE; //RE
    reg [3-1:0]            count_to_4_for_row_0_out;
    reg [2-1:0]            count_to_3_for_row_1_out;
    reg [2-1:0]            count_to_2_for_row_2_out;
    reg                    count_to_1_for_row_3_out;
    wire                   sram_wen; //sram 0, sram 1, ..., sram 5
    wire                   sram_cen = 0; //active low
    reg  [8-1:0]           sram_addr_r; //address of sram 0, sram 1, ..., sram 5
    wire [8-1:0]           sram_out_data[0:5];
    reg                    start_write_sram; //start to write sram
    wire                   first_trig;
    reg                    y_finish[0:3];
    wire                   rows_finish[0:3]; //used for counting for r position in array
    wire [IN_WIDTH-1:0]    rows_real_x[0:3]; //to r or y hat
    wire [IN_WIDTH-1:0]    rows_imag_x[0:3];
    wire                   rows_mode_x[0:3]; //used for distinguish the first one, vectoring mode is the first one
    wire                   PE1_and_DU0_trig, PE2_and_PE3_trig, PE3_trig, PE4_and_DU1_trig, PE5_trig; //RU0 trig use row finish signal
    wire                   PE1_mode_x, PE2_mode_x, PE3_mode_x, PE3_mode_y, PE4_mode_x, PE4_mode_y, PE5_mode_x, PE5_mode_y, DU0_mode_y, DU1_mode_y, RU0_mode_y;
    wire [IN_WIDTH-1:0]    PE1_real_x, PE1_imag_x, PE2_real_x, PE2_imag_x, PE3_real_x, PE3_imag_x, PE3_real_y, PE3_imag_y, PE4_real_x, PE4_imag_x, PE4_real_y, PE4_imag_y, PE5_real_x, PE5_imag_x, PE5_real_y, PE5_imag_y, DU0_real_y, DU0_imag_y, DU1_real_y, DU1_imag_y, RU0_real_y, RU0_imag_y;
    reg  [OUT_WIDTH-1:0]   r11_tmp; //overlap of RE output
    reg  [2*OUT_WIDTH-1:0] r12_tmp; //overlap of RE output
    reg  [320-1:0]         r_buffer; //output buffer
    reg  [160-1:0]         y_hat_buffer; //output buffer
    reg                    finish_buffer; //output buffer
    reg                    last_data_buffer; //output buffer
    

    assign                 o_rd_vld    = finish_buffer;
    assign                 o_last_data = last_data_buffer;
    assign                 o_r         = r_buffer;
    assign                 o_y_hat     = y_hat_buffer;

    assign                 first_trig  = (sram_addr_r == (180-NUM_ITERATION*4)) & i_trig_buf; //trigger at this moment so that y finish [0] can fetch data in sram right at the boundary
    assign                 sram_wen    = ~start_write_sram; //active low. only when FIFOs are full and in the loading stage, write RE1~RE9 to sram

    wire [8-1:0]           sram_addr_w = sram_addr_r + 1;
    // wire [8-1:0]           sram_addr   = (i_trig_buf | ~(y_finish[0] | y_finish[1] | y_finish[2] | y_finish[3])) ? sram_addr_r : sram_addr_w; //fetch +1 address if y_finish
    wire [8-1:0]           sram_addr   = sram_addr_r; //fetch +1 address if y_finish
    // wire [8-1:0]           sram_addr   = (y_finish[0] | y_finish[1] | y_finish[2] | y_finish[3]) ? sram_addr_w : sram_addr_r; //fetch +1 address if y_finish
    wire                   PE0_mode_x  = (count_to_4_for_pipeline == 4); //initial mode
    wire                   PE0_mode_y  = (count_to_4_for_pipeline == 0);
    wire                   PE1_mode_y  = (count_to_4_for_pipeline == 2);
    wire                   PE2_mode_y  = (count_to_4_for_pipeline == 4);
    wire                   PE0_trig    = first_trig | (PE1_and_DU0_trig & ((sram_addr_r <= 180) & (count_to_9_for_inter_RE != 9))); //prevent wrong trig signal in next 10RE i trig stage
    wire                   RU0_trig    = rows_finish[2];
    wire [2-1:0] tail_i = 1;
    wire [IN_WIDTH-1:0]    PE0_real_x  = {{2{FIFO[0][0][23]}}, FIFO[0][0][23:16], tail_i}; //sign extension
    wire [IN_WIDTH-1:0]    PE0_imag_x  = {{2{FIFO[0][0][47]}}, FIFO[0][0][47:40], tail_i};
    wire [IN_WIDTH-1:0]    PE0_real_y  = {{2{FIFO[1][0][23]}}, FIFO[1][0][23:16], tail_i};
    wire [IN_WIDTH-1:0]    PE0_imag_y  = {{2{FIFO[1][0][47]}}, FIFO[1][0][47:40], tail_i};
    wire [IN_WIDTH-1:0]    PE1_real_y  = {{2{FIFO[2][0][23]}}, FIFO[2][0][23:16], tail_i};
    wire [IN_WIDTH-1:0]    PE1_imag_y  = {{2{FIFO[2][0][47]}}, FIFO[2][0][47:40], tail_i}; //Use S3.10, with input S1.10
    wire [IN_WIDTH-1:0]    PE2_real_y  = {{2{FIFO[3][0][23]}}, FIFO[3][0][23:16], tail_i}; //But test if can use less bits
    wire [IN_WIDTH-1:0]    PE2_imag_y  = {{2{FIFO[3][0][47]}}, FIFO[3][0][47:40], tail_i}; //S1.16 to fit output S3.16
    
    // wire [IN_WIDTH-1:0]    PE0_real_x  = {{2{FIFO[0][0][23]}}, FIFO[0][0][23:16]}; //sign extension
    // wire [IN_WIDTH-1:0]    PE0_imag_x  = {{2{FIFO[0][0][47]}}, FIFO[0][0][47:40]};
    // wire [IN_WIDTH-1:0]    PE0_real_y  = {{2{FIFO[1][0][23]}}, FIFO[1][0][23:16]};
    // wire [IN_WIDTH-1:0]    PE0_imag_y  = {{2{FIFO[1][0][47]}}, FIFO[1][0][47:40]};
    // wire [IN_WIDTH-1:0]    PE1_real_y  = {{2{FIFO[2][0][23]}}, FIFO[2][0][23:16]};
    // wire [IN_WIDTH-1:0]    PE1_imag_y  = {{2{FIFO[2][0][47]}}, FIFO[2][0][47:40]}; //Use S3.10, with input S1.10
    // wire [IN_WIDTH-1:0]    PE2_real_y  = {{2{FIFO[3][0][23]}}, FIFO[3][0][23:16]}; //But test if can use less bits
    // wire [IN_WIDTH-1:0]    PE2_imag_y  = {{2{FIFO[3][0][47]}}, FIFO[3][0][47:40]}; //S1.16 to fit output S3.16
    wire [8-1:0] tail = 150;
    //Input buffer
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            i_trig_buf <= 0;
            i_data_buf <= 0;
        end
        else begin
            i_trig_buf <= i_trig;
            i_data_buf <= i_data;
        end
    end
    
    //Handle y hat buffer
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            y_hat_buffer <= 0;
        end
        else begin
            if (rows_finish[0]) begin
                if (count_to_4_for_row_0_out == 4) begin
                    y_hat_buffer[39:0] <= {rows_imag_x[0][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[0][IN_WIDTH-1-:IN_WIDTH], tail}; //y hat 1
                end
            end
            if (rows_finish[1]) begin
                if (count_to_3_for_row_1_out == 3) begin
                    y_hat_buffer[79:40] <= {rows_imag_x[1][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[1][IN_WIDTH-1-:IN_WIDTH], tail}; //y hat 2
                end
            end
            if (rows_finish[2]) begin
                if (count_to_2_for_row_2_out == 2) begin
                    y_hat_buffer[119:80] <= {rows_imag_x[2][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[2][IN_WIDTH-1-:IN_WIDTH], tail}; //y hat 3
                end
            end
            if (rows_finish[3]) begin
                if (count_to_1_for_row_3_out == 1) begin
                    y_hat_buffer[159:120] <= {rows_imag_x[3][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[3][IN_WIDTH-1-:IN_WIDTH], tail}; //y hat 4
                end
            end
        end
    end

    //Handle r11 tmp
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            r11_tmp <= 0;
        end
        else if (rows_finish[0] & (rows_mode_x[0] == 1)) begin
            r11_tmp <= {rows_real_x[0][IN_WIDTH-1-:IN_WIDTH], tail};
        end
    end

    //Handle r12 tmp
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            r12_tmp <= 0;
        end
        else if (rows_finish[0] & (count_to_4_for_row_0_out == 1)) begin
            r12_tmp <= {rows_imag_x[0][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[0][IN_WIDTH-1-:IN_WIDTH], tail};
        end
    end

    //Handle r buffer
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            r_buffer <= 0;
        end
        else begin
            if (rows_finish[0]) begin
                if (rows_mode_x[0] == 1) begin //vectoring mode
                    r_buffer[19:0] <= r11_tmp; //r11
                end
                if (count_to_4_for_row_0_out == 1) begin
                    r_buffer[59:20] <= r12_tmp; //r12
                end
                if (count_to_4_for_row_0_out == 2) begin
                    r_buffer[119:80] <= {rows_imag_x[0][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[0][IN_WIDTH-1-:IN_WIDTH], tail}; //r13
                end
                if (count_to_4_for_row_0_out == 3) begin
                    r_buffer[219:180] <= {rows_imag_x[0][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[0][IN_WIDTH-1-:IN_WIDTH], tail}; //r14
                end
            end
            if (rows_finish[1]) begin
                if (rows_mode_x[1] == 1) begin //vectoring mode
                    r_buffer[79:60] <= {rows_real_x[1][IN_WIDTH-1-:IN_WIDTH], tail}; //r22
                end
                if (count_to_3_for_row_1_out == 1) begin
                    r_buffer[159:120] <= {rows_imag_x[1][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[1][IN_WIDTH-1-:IN_WIDTH], tail}; //r23
                end
                if (count_to_3_for_row_1_out == 2) begin
                    r_buffer[259:220] <= {rows_imag_x[1][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[1][IN_WIDTH-1-:IN_WIDTH], tail}; //r24
                end
            end
            if (rows_finish[2]) begin
                if (rows_mode_x[2] == 1) begin //vectoring mode
                    r_buffer[179:160] <= {rows_real_x[2][IN_WIDTH-1-:IN_WIDTH], tail}; //r33
                end
                if (count_to_2_for_row_2_out == 1) begin
                    r_buffer[299:260] <= {rows_imag_x[2][IN_WIDTH-1-:IN_WIDTH], tail, rows_real_x[2][IN_WIDTH-1-:IN_WIDTH], tail}; //r34
                end
            end
            if (rows_finish[3]) begin
                if (rows_mode_x[3] == 1) begin //vectoring mode
                    r_buffer[319:300] <= {rows_real_x[3][IN_WIDTH-1-:IN_WIDTH], tail}; //r44
                end
                if (count_to_1_for_row_3_out == 1) begin
                    if (count_to_9_for_inter_RE == 9) begin //zero out all regs except finish and last data
                        r_buffer[19:0] <= r11_tmp; //dump r11
                        r_buffer[59:20] <= r12_tmp; //dump r12 because no next trig signal
                    end
                end
            end
        end
    end

    //Handle finish buffer
    // always @(posedge i_clk) begin
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            finish_buffer <= 0;
        end
        else if (rows_finish[3] & (count_to_1_for_row_3_out == 1)) begin
            finish_buffer <= 1;
        end
        else begin
            finish_buffer <= 0;
        end
    end

    //Handle row 3 out count //must need reset
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            count_to_1_for_row_3_out <= 0;
        end
        else if (rows_finish[3]) begin
            if (rows_mode_x[3] == 1) begin //vectoring mode
                count_to_1_for_row_3_out <= 1;
            end
            else begin
                count_to_1_for_row_3_out <= 0;
            end
        end
    end

    //Handle row 2 out count //May need reset
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            count_to_2_for_row_2_out <= 0;
        end
        else if (rows_finish[2]) begin
            if (rows_mode_x[2] == 1) begin //vectoring mode
                count_to_2_for_row_2_out <= 1;
            end
            else begin
                count_to_2_for_row_2_out <= count_to_2_for_row_2_out + 1;
            end
        end
    end

    //Handle row 1 out count //May need reset
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            count_to_3_for_row_1_out <= 0;
        end
        else if (rows_finish[1]) begin
            if (rows_mode_x[1] == 1) begin //vectoring mode
                count_to_3_for_row_1_out <= 1;
            end
            else begin
                count_to_3_for_row_1_out <= count_to_3_for_row_1_out + 1;
            end
        end
    end
    
    //Handle row 0 out count //May need reset
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            count_to_4_for_row_0_out <= 0;
        end
        else if (rows_finish[0]) begin
            if (rows_mode_x[0] == 1) begin //vectoring mode
                count_to_4_for_row_0_out <= 1;
            end
            else begin
                count_to_4_for_row_0_out <= count_to_4_for_row_0_out + 1;
            end
        end
    end

    //Handle y finish
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                y_finish[i] <= 0;
            end
        end
        else begin
            if (PE1_and_DU0_trig) begin
                y_finish[0] <= (count_to_4_for_pipeline == 3); //From i_trig_buf period to here, the 1st cycle should set this
                y_finish[1] <= (count_to_4_for_pipeline == 3);
                y_finish[2] <= (count_to_4_for_pipeline == 4); //Although use this feedback for PE0 trig signal, count to 4 for pipeline must be 4 at the last time PE1 and DU0 trig, it will not set another y finish[0]
            end
            if (PE2_and_PE3_trig) begin
                y_finish[3] <= (count_to_4_for_pipeline == 0);
            end
            if (count_to_4_for_intra_FIFO == 4) begin
                if (y_finish[0]) begin
                    y_finish[0] <= 0;
                end
                else if (y_finish[1]) begin
                    y_finish[1] <= 0;
                end
                if (y_finish[2]) begin
                    y_finish[2] <= 0;
                end
                if (y_finish[3]) begin
                    y_finish[3] <= 0;
                end
                // if (rows_finish[3] & (count_to_1_for_row_3_out == 1)) begin //resoure share count to nine //same as o finish logic
                //     if (count_to_9_for_inter_RE == 9) begin //zero out everything for next 10RE, same as reset logic
                //         for (i = 0; i < 4; i = i + 1) begin
                //             y_finish[i] <= 0;
                //         end
                //     end
                // end
            end
        end
    end

    //Handle FIFO
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            for (i = 0; i < 4; i = i + 1) begin
                for (j = 0; j < 5; j = j + 1) begin
                    FIFO[i][j] <= 0;
                end
            end
        end
        //RE0
        else if (i_trig_buf & (~start_write_sram)) begin //Load i data and compute RE0
            FIFO[count_to_3_for_inter_FIFO][4] <= i_data_buf;
            for (j = 0; j < 4; j = j + 1) begin
                FIFO[count_to_3_for_inter_FIFO][j] <= FIFO[count_to_3_for_inter_FIFO][j+1];
            end
        end
        else begin
            //Compute
            if (first_trig | PE1_and_DU0_trig) begin
                for (j = 0; j < 4; j = j + 1) begin
                    FIFO[0][j] <= FIFO[0][j+1]; //0 1 2 3 4 -> 1 2 3 4 4 -> 2 3 4 4 4 -> 3 4 4 4 4 -> 4 4 4 4 4
                    FIFO[1][j] <= FIFO[1][j+1];
                end
            end
            if (PE1_and_DU0_trig) begin
                for (j = 0; j < 4; j = j + 1) begin
                    FIFO[2][j] <= FIFO[2][j+1];
                end
            end
            if (PE2_and_PE3_trig) begin
                for (j = 0; j < 4; j = j + 1) begin
                    FIFO[3][j] <= FIFO[3][j+1];
                end
            end

            //Load new RE
            if (y_finish[0]) begin //fetch new column 0
                FIFO[0][4] <= {sram_out_data[5], sram_out_data[4], sram_out_data[3], sram_out_data[2], sram_out_data[1], sram_out_data[0]};
                for (j = 0; j < 4; j = j + 1) begin
                    FIFO[0][j] <= FIFO[0][j+1];
                end
            end
            else if (y_finish[1]) begin
                FIFO[1][4] <= {sram_out_data[5], sram_out_data[4], sram_out_data[3], sram_out_data[2], sram_out_data[1], sram_out_data[0]};
                for (j = 0; j < 4; j = j + 1) begin
                    FIFO[1][j] <= FIFO[1][j+1];
                end
            end
            if (y_finish[2]) begin
                FIFO[2][4] <= {sram_out_data[5], sram_out_data[4], sram_out_data[3], sram_out_data[2], sram_out_data[1], sram_out_data[0]};
                for (j = 0; j < 4; j = j + 1) begin
                    FIFO[2][j] <= FIFO[2][j+1];
                end
            end
            if (y_finish[3]) begin
                FIFO[3][4] <= {sram_out_data[5], sram_out_data[4], sram_out_data[3], sram_out_data[2], sram_out_data[1], sram_out_data[0]};
                for (j = 0; j < 4; j = j + 1) begin
                    FIFO[3][j] <= FIFO[3][j+1];
                end
            end
        end
    end

    //Handle pipeline count for loading sram data into FIFO (y finish)
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            count_to_4_for_pipeline <= 4;
        end
        else begin
            if (first_trig | PE1_and_DU0_trig) begin
                if (count_to_4_for_pipeline == 4) begin
                    count_to_4_for_pipeline <= 0;
                end
                else begin
                    count_to_4_for_pipeline <= count_to_4_for_pipeline + 1;
                end
            end
            if (rows_finish[3] & (count_to_1_for_row_3_out == 1) & (count_to_9_for_inter_RE == 9)) begin //resoure share count to nine //same as o finish logic
                count_to_4_for_pipeline <= 4;
            end
        end
    end

    //Handle intra FIFO count
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            count_to_4_for_intra_FIFO <= 0; //H11 H12 H13 H14 y1
        end
        else if (i_trig_buf) begin //Load i data and compute RE0
        // else if (i_trig_buf & ~start_compute_RE) begin //Load i data and compute RE0 clk gate
            if (count_to_4_for_intra_FIFO == 4) begin //change FIFO
                count_to_4_for_intra_FIFO <= 0;
            end
            else begin
                count_to_4_for_intra_FIFO <= count_to_4_for_intra_FIFO + 1;
            end
        end
        else if (y_finish[0] | y_finish[1] | y_finish[2] | y_finish[3]) begin //Load i data and compute RE0
        // else if (i_trig_buf & ~start_compute_RE) begin //Load i data and compute RE0 clk gate
            if (count_to_4_for_intra_FIFO == 4) begin //change FIFO
                count_to_4_for_intra_FIFO <= 0;
            end
            else begin
                count_to_4_for_intra_FIFO <= count_to_4_for_intra_FIFO + 1;
            end
        end
    end

    //Handle inter FIFO count
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            count_to_3_for_inter_FIFO <= 0; //FIFO 1, 2, 3, 4
        end
        else if (i_trig_buf & (count_to_4_for_intra_FIFO == 4) & (~start_write_sram)) begin //Load i data and compute RE0
            count_to_3_for_inter_FIFO <= count_to_3_for_inter_FIFO + 1; //zero self automatically
        end
    end

    //Handle inter RE count
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            count_to_9_for_inter_RE <= 0; //RE1 ~ RE10
            // start_compute_RE <= 0;
        end
        // else if (i_trig_buf) begin //Load i data and compute RE0
        //     if ((count_to_4_for_intra_FIFO == 4) & (count_to_3_for_inter_FIFO == 3)) begin //change RE
        //         // count_to_9_for_inter_RE <= 1'b1;
        //         start_compute_RE <= 1'b1;
        //     end
        //     if (~i_trig) begin //falling edge of i trig
        //         // count_to_9_for_inter_RE <= 1'b0;
        //         start_compute_RE <= 1'b0;
        //     end
        // end
        // else if (start_compute_RE) begin //Computing RE1~RE9
        else if (rows_finish[3] & (count_to_1_for_row_3_out == 1)) begin
            if (count_to_9_for_inter_RE == 9) begin //zero out everything for next 10RE, same as reset logic
                count_to_9_for_inter_RE <= 0;
            end
            else begin
                count_to_9_for_inter_RE <= count_to_9_for_inter_RE + 1;
            end
        end
        // end
    end

    //Handle sram write signal
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            // count_to_9_for_inter_RE <= 0; //RE1 ~ RE10
            start_write_sram <= 0;
        end
        else if (i_trig_buf) begin //Load i data and compute RE0
            if ((count_to_4_for_intra_FIFO == 4) & (count_to_3_for_inter_FIFO == 3)) begin //change RE
                // count_to_9_for_inter_RE <= 1'b1;
                start_write_sram <= 1;
            end
            if (~i_trig) begin //falling edge of i trig
        //         // count_to_9_for_inter_RE <= 1'b0;
                start_write_sram <= 0;
            end
        end
        // else if (start_compute_RE) begin //Computing RE1~RE9
        // else if (rows_finish[3] & (count_to_1_for_row_3_out == 1)) begin
        //     if (count_to_9_for_inter_RE == 9) begin //zero out everything for next 10RE, same as reset logic
        //         count_to_9_for_inter_RE <= 0;
        //     end
        //     else begin
        //         count_to_9_for_inter_RE <= count_to_9_for_inter_RE + 1;
        //     end
        // end
        // end
    end

    //Handle last data buffer
    // always @(posedge i_clk) begin
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            last_data_buffer <= 0;
        end
        // else if (rows_finish[3] & (count_to_1_for_row_3_out == 1) & (count_to_9_for_inter_RE == 9)) begin
        // if ((PE5.count == 4) & (sram_addr_r == 190)) begin //resoure share count to nine //same as o finish logic
        else if (sram_addr_r == 188) begin //resoure share count to nine //same as o finish logic
            last_data_buffer <= 1;
        end
        else begin
            last_data_buffer <= 0; //reset last data and finish after 10RE
        end
    end

    //Handle sram addr reg
    always @(posedge i_clk or posedge i_rst) begin
        if (i_rst) begin
            sram_addr_r <= 0;
        end
        else if (i_trig_buf) begin //Load i data and compute RE0
            if (start_write_sram) begin //Store RE1~RE9 input data to sram
                sram_addr_r <= sram_addr_w;
            end
            if (~i_trig) begin //Same as sram addr reg == 179
                sram_addr_r <= 0; //jump to next stage
            end
        end
        else begin
        // else if (start_compute_RE) begin //Computing RE1~RE9
        
            if (PE1_and_DU0_trig & ((count_to_4_for_pipeline == 3) | (count_to_4_for_pipeline == 4))) begin
                // y_finish[0] <= (count_to_4_for_pipeline == 3); //From i_trig_buf period to here, the 1st cycle should set this
                // y_finish[1] <= (count_to_4_for_pipeline == 3);
                // y_finish[2] <= (count_to_4_for_pipeline == 4); //Although use this feedback for PE0 trig signal, count to 4 for pipeline must be 4 at the last time PE1 and DU0 trig, it will not set another y finish[0]
                sram_addr_r <= sram_addr_w;
            end
            if (PE2_and_PE3_trig & (count_to_4_for_pipeline == 0)) begin
                // y_finish[3] <= (count_to_4_for_pipeline == 0);
                sram_addr_r <= sram_addr_w;
            end
            if (y_finish[0] | y_finish[1] | y_finish[2] | y_finish[3]) begin
                sram_addr_r <= sram_addr_w;
            end
            if ((count_to_4_for_intra_FIFO == 4) & ((~y_finish[0] & y_finish[1]) | y_finish[2] | y_finish[3])) begin
                // if (y_finish[0]) begin
                //     y_finish[0] <= 0;
                // end
                // else if (y_finish[1]) begin
                //     y_finish[1] <= 0;
                // end
                // if (y_finish[2]) begin
                //     y_finish[2] <= 0;
                // end
                // if (y_finish[3]) begin
                //     y_finish[3] <= 0;
                // end
                sram_addr_r <= sram_addr_r;
            end
            // if (rows_finish[3] & (count_to_1_for_row_3_out == 1) & (count_to_9_for_inter_RE == 9)) begin //resoure share count to nine //same as o finish logic
            if (sram_addr_r == 190) begin //resoure share count to nine //same as o finish logic
                sram_addr_r <= 0;
            end
        end
    end

    // always @(posedge i_clk or posedge i_rst) begin
    //     if (i_rst) begin
    //         start_compute_RE <= 0; //start compute at some time such that sram read right after sram write
    //     end
    //     else if (i_trig_buf) begin //Load i data and compute RE0
    //         if (sram_addr_r == (180-NUM_ITERATION*4-1)) begin
    //             start_compute_RE <= 1;
    //         end
    //     end
    //     else if (start_compute_RE) begin //Computing RE1~RE9
    //         if (rows_finish[3] & (count_to_1_for_row_3_out == 1) & (count_to_9_for_inter_RE == 9)) begin //resoure share count to nine //same as o finish logic
    //             start_compute_RE <= 0; //turn off everything and become idle
    //         end
    //     end
    // end
    wire [IN_WIDTH-1:0]    raw_rows_real_x[0:3]; //to r or y hat
    wire [IN_WIDTH-1:0]    raw_rows_imag_x[0:3];
    assign rows_real_x[0] = raw_rows_real_x[0];
    assign rows_imag_x[0] = raw_rows_imag_x[0];
    assign rows_real_x[1] = raw_rows_real_x[1];
    assign rows_imag_x[1] = raw_rows_imag_x[1];
    assign rows_real_x[2] = raw_rows_real_x[2];
    assign rows_imag_x[2] = raw_rows_imag_x[2];
    assign rows_real_x[3] = raw_rows_real_x[3];
    assign rows_imag_x[3] = raw_rows_imag_x[3];

    PE PE0 (.i_clk(i_clk), .i_rst(i_rst), .i_trig(PE0_trig),         .i_real_x(PE0_real_x), .i_imag_x(PE0_imag_x), .i_real_y(PE0_real_y), .i_imag_y(PE0_imag_y), .i_mode_x(PE0_mode_x), .i_mode_y(PE0_mode_y), .o_real_x(PE1_real_x),     .o_imag_x(PE1_imag_x),     .o_real_y(DU0_real_y), .o_imag_y(DU0_imag_y), .o_mode_x(PE1_mode_x),     .o_mode_y(DU0_mode_y), .o_finish(PE1_and_DU0_trig));
    PE PE1 (.i_clk(i_clk), .i_rst(i_rst), .i_trig(PE1_and_DU0_trig), .i_real_x(PE1_real_x), .i_imag_x(PE1_imag_x), .i_real_y(PE1_real_y), .i_imag_y(PE1_imag_y), .i_mode_x(PE1_mode_x), .i_mode_y(PE1_mode_y), .o_real_x(PE2_real_x),     .o_imag_x(PE2_imag_x),     .o_real_y(PE3_real_y), .o_imag_y(PE3_imag_y), .o_mode_x(PE2_mode_x),     .o_mode_y(PE3_mode_y), .o_finish(PE2_and_PE3_trig));
    PE PE2 (.i_clk(i_clk), .i_rst(i_rst), .i_trig(PE2_and_PE3_trig), .i_real_x(PE2_real_x), .i_imag_x(PE2_imag_x), .i_real_y(PE2_real_y), .i_imag_y(PE2_imag_y), .i_mode_x(PE2_mode_x), .i_mode_y(PE2_mode_y), .o_real_x(raw_rows_real_x[0]), .o_imag_x(raw_rows_imag_x[0]), .o_real_y(PE4_real_y), .o_imag_y(PE4_imag_y), .o_mode_x(rows_mode_x[0]), .o_mode_y(PE4_mode_y), .o_finish(rows_finish[0])); //to real output
    DU DU0 (.i_clk(i_clk), .i_rst(i_rst), .i_trig(PE1_and_DU0_trig),                                               .i_real_y(DU0_real_y), .i_imag_y(DU0_imag_y),                        .i_mode_y(DU0_mode_y), .o_real_x(PE3_real_x),     .o_imag_x(PE3_imag_x),                                                   .o_mode_x(PE3_mode_x),                            .o_finish(PE3_trig));       //trig from left, can change
    PE PE3 (.i_clk(i_clk), .i_rst(i_rst), .i_trig(PE3_trig),         .i_real_x(PE3_real_x), .i_imag_x(PE3_imag_x), .i_real_y(PE3_real_y), .i_imag_y(PE3_imag_y), .i_mode_x(PE3_mode_x), .i_mode_y(PE3_mode_y), .o_real_x(PE4_real_x),     .o_imag_x(PE4_imag_x),     .o_real_y(DU1_real_y), .o_imag_y(DU1_imag_y), .o_mode_x(PE4_mode_x),     .o_mode_y(DU1_mode_y), .o_finish(PE4_and_DU1_trig));
    PE PE4 (.i_clk(i_clk), .i_rst(i_rst), .i_trig(PE4_and_DU1_trig), .i_real_x(PE4_real_x), .i_imag_x(PE4_imag_x), .i_real_y(PE4_real_y), .i_imag_y(PE4_imag_y), .i_mode_x(PE4_mode_x), .i_mode_y(PE4_mode_y), .o_real_x(raw_rows_real_x[1]), .o_imag_x(raw_rows_imag_x[1]), .o_real_y(PE5_real_y), .o_imag_y(PE5_imag_y), .o_mode_x(rows_mode_x[1]), .o_mode_y(PE5_mode_y), .o_finish(rows_finish[1])); //to real output
    DU DU1 (.i_clk(i_clk), .i_rst(i_rst), .i_trig(PE4_and_DU1_trig),                                               .i_real_y(DU1_real_y), .i_imag_y(DU1_imag_y),                        .i_mode_y(DU1_mode_y), .o_real_x(PE5_real_x),     .o_imag_x(PE5_imag_x),                                                   .o_mode_x(PE5_mode_x),                            .o_finish(PE5_trig));
    PE PE5 (.i_clk(i_clk), .i_rst(i_rst), .i_trig(PE5_trig),         .i_real_x(PE5_real_x), .i_imag_x(PE5_imag_x), .i_real_y(PE5_real_y), .i_imag_y(PE5_imag_y), .i_mode_x(PE5_mode_x), .i_mode_y(PE5_mode_y), .o_real_x(raw_rows_real_x[2]), .o_imag_x(raw_rows_imag_x[2]), .o_real_y(RU0_real_y), .o_imag_y(RU0_imag_y), .o_mode_x(rows_mode_x[2]), .o_mode_y(RU0_mode_y), .o_finish(rows_finish[2])); //to real output
    RU RU0 (.i_clk(i_clk), .i_rst(i_rst), .i_trig(RU0_trig),                                                       .i_real_y(RU0_real_y), .i_imag_y(RU0_imag_y),                        .i_mode_y(RU0_mode_y), .o_real_x(raw_rows_real_x[3]), .o_imag_x(raw_rows_imag_x[3]),                                               .o_mode_x(rows_mode_x[3]),                        .o_finish(rows_finish[3])); //to real output
    
    assign sram_out_data[0] = 0;
    assign sram_out_data[1] = 0;
    assign sram_out_data[3] = 0;
    assign sram_out_data[4] = 0;
    // wire [8-1:0] a = i_data_buf[23:16] + i_data_buf[15];
    // wire [8-1:0] b = i_data_buf[47:40] + i_data_buf[39];
    // sram_256x8 sram_256x8_0 (.Q(sram_out_data[0]), .CLK(i_clk), .CEN(sram_cen), .WEN(sram_wen), .A(sram_addr), .D(i_data_buf[7:0]));
    // sram_256x8 sram_256x8_1 (.Q(sram_out_data[1]), .CLK(i_clk), .CEN(sram_cen), .WEN(sram_wen), .A(sram_addr), .D(i_data_buf[15:8]));
    sram_256x8 sram_256x8_2 (.Q(sram_out_data[2]), .CLK(i_clk), .CEN(sram_cen), .WEN(sram_wen), .A(sram_addr), .D(i_data_buf[23:16]));
    // sram_256x8 sram_256x8_3 (.Q(sram_out_data[3]), .CLK(i_clk), .CEN(sram_cen), .WEN(sram_wen), .A(sram_addr), .D(i_data_buf[31:24]));
    // sram_256x8 sram_256x8_4 (.Q(sram_out_data[4]), .CLK(i_clk), .CEN(sram_cen), .WEN(sram_wen), .A(sram_addr), .D(i_data_buf[39:32]));
    sram_256x8 sram_256x8_5 (.Q(sram_out_data[5]), .CLK(i_clk), .CEN(sram_cen), .WEN(sram_wen), .A(sram_addr), .D(i_data_buf[47:40]));

endmodule
//Total 48*20*10 = 1200*8 bits data
//ues 6 256*8 srams, depth up to 180 because first is stored in FIFO registers
//Pipeline load total 20 entry before start to run
//The operation latency are 3*32 + 6*32 + 16 = 304 cycles, throuput is 1/32/5
//After the last data y4 gets into the systolic array, there are 32*3+16=112 cycles //useless
//Every 32 cycles can input a data
//if count_to_4_for_pipeline = 4 and trig fetch new column 1
//use finish to trigger rather than latency count
//check if PE2_and_PE3_trig & PE3_trig rise at the same time, row finish[0] and PE4_trig, PE5_trig and row finish[1]
//if o last data, compute RE = 0, mask_n = compute RE = 0
//can use o mode x of output to find the first non zero entry of row. * means starting to take and real
//y_finish delay from input by one cycle to fetch new data


    // always @(posedge i_clk or posedge i_rst) begin
    //     if (i_rst) begin
    //         count_to_4_for_intra_FIFO <= 0; //H11 H12 H13 H14 y1
    //         count_to_3_for_inter_FIFO <= 0; //FIFO 1, 2, 3, 4
    //         count_to_9_for_inter_RE <= 0; //RE1 ~ RE10
    //         count_to_4_for_pipeline <= 4; //For loading sram data into FIFO
    //         sram_addr_r <= 0;
    //         start_compute_RE <= 0; //start compute at some time such that sram read right after sram write
    //         for (i = 0; i < 4; i = i + 1) begin
    //             // for (j = 0; j < 5; j = j + 1) begin
    //             //     FIFO[i][j] <= 0;
    //             // end
    //             y_finish[i] <= 0;
    //         end
    //     end
    //     else if (i_trig_buf) begin //Load i data and compute RE0
    //         if (count_to_4_for_intra_FIFO == 4) begin //change FIFO
    //             if (count_to_3_for_inter_FIFO == 3) begin //change RE
    //                 // if (count_to_9_for_inter_RE == 9) begin
    //                 //     count_to_9_for_inter_RE <= 0; //for o last data
    //                 // end
    //                 // else begin
    //                 //     count_to_9_for_inter_RE <= count_to_9_for_inter_RE + 1;
    //                 // end
    //                 count_to_9_for_inter_RE <= 1'b1;
    //             end
    //             count_to_4_for_intra_FIFO <= 0;
    //             count_to_3_for_inter_FIFO <= count_to_3_for_inter_FIFO + 1; //zero self automatically
    //         end
    //         else begin
    //             count_to_4_for_intra_FIFO <= count_to_4_for_intra_FIFO + 1;
    //         end
    //         if (count_to_9_for_inter_RE[0]) begin
    //             sram_addr_r <= sram_addr_w;
    //         end
    //         else begin //count_to_9_for_inter_RE == 0
    //             FIFO[count_to_3_for_inter_FIFO][4] <= i_data_buf;
    //             for (j = 0; j < 4; j = j + 1) begin
    //                 FIFO[count_to_3_for_inter_FIFO][j] <= FIFO[count_to_3_for_inter_FIFO][j+1];
    //             end
    //             //synthesis larger area
    //             // FIFO[3][4] <= i_data_buf;
    //             // FIFO[2][4] <= FIFO[3][0];
    //             // FIFO[1][4] <= FIFO[2][0];
    //             // FIFO[0][4] <= FIFO[1][0];
    //             // for (i = 0; i < 4; i = i + 1) begin
    //             //     for (j = 0; j < 4; j = j + 1) begin
    //             //         FIFO[i][j] <= FIFO[i][j+1];
    //             //     end
    //             // end
    //         end
    //         if (sram_addr_r == 179) begin
    //             count_to_9_for_inter_RE <= 1'b0;
    //             sram_addr_r <= 0; //jump to next stage
    //             // count_to_4_for_intra_FIFO <= 0; //useless, zero out automatically
    //         end
    //         if (sram_addr_r == (180-NUM_ITERATION*4-1)) begin
    //             start_compute_RE <= 1;
    //         end
    //         if (start_compute_RE) begin
    //             // if (first_trig) begin
    //             //     for (j = 0; j < 4; j = j + 1) begin
    //             //         FIFO[0][j] <= FIFO[0][j+1];
    //             //         FIFO[1][j] <= FIFO[1][j+1];
    //             //     end
    //             //     count_to_4_for_pipeline <= 0;
    //             // end
    //             if (first_trig | PE1_and_DU0_trig) begin
    //                 for (j = 0; j < 4; j = j + 1) begin
    //                     FIFO[0][j] <= FIFO[0][j+1]; //0 1 2 3 4 -> 1 2 3 4 4 -> 2 3 4 4 4 -> 3 4 4 4 4 -> 4 4 4 4 4
    //                     FIFO[1][j] <= FIFO[1][j+1];
    //                 end
    //                 if (count_to_4_for_pipeline == 4) begin                                           //chhearnege
    //                     count_to_4_for_pipeline <= 0;
    //                 end
    //                 else begin
    //                     count_to_4_for_pipeline <= count_to_4_for_pipeline + 1;
    //                 end
    //             end
    //             if (PE1_and_DU0_trig) begin
    //                 for (j = 0; j < 4; j = j + 1) begin
    //                     FIFO[2][j] <= FIFO[2][j+1];
    //                 end
    //             end
    //             if (PE2_and_PE3_trig) begin
    //                 for (j = 0; j < 4; j = j + 1) begin
    //                     FIFO[3][j] <= FIFO[3][j+1];
    //                 end
    //             end
    //         end
    //     end
    //     else if (start_compute_RE) begin //Computing RE1~RE9
    //         if (PE1_and_DU0_trig) begin //start compute RE would be turned off afterwards
    //             for (j = 0; j < 4; j = j + 1) begin
    //                 FIFO[0][j] <= FIFO[0][j+1];
    //                 FIFO[1][j] <= FIFO[1][j+1];
    //             end
    //             if (count_to_4_for_pipeline == 4) begin                                                //chahnegree
    //                 count_to_4_for_pipeline <= 0;
    //             end
    //             else begin
    //                 count_to_4_for_pipeline <= count_to_4_for_pipeline + 1;
    //             end
    //             y_finish[0] <= (count_to_4_for_pipeline == 3); //From i_trig_buf period to here, the 1st cycle should set this
    //             y_finish[1] <= (count_to_4_for_pipeline == 3);
    //         end
    //         if (PE1_and_DU0_trig) begin
    //             for (j = 0; j < 4; j = j + 1) begin
    //                 FIFO[2][j] <= FIFO[2][j+1];
    //             end
    //             y_finish[2] <= (count_to_4_for_pipeline == 4);
    //         end
    //         if (PE2_and_PE3_trig) begin
    //             for (j = 0; j < 4; j = j + 1) begin
    //                 FIFO[3][j] <= FIFO[3][j+1];
    //             end
    //             y_finish[3] <= (count_to_4_for_pipeline == 0);
    //         end
    //         if (rows_finish[3] & (count_to_1_for_row_3_out == 1)) begin //resoure share count to nine //same as o finish logic
    //             count_to_9_for_inter_RE <= count_to_9_for_inter_RE + 1;
    //             if (count_to_9_for_inter_RE == 9) begin //zero out everything for next 10RE, same as reset logic
    //                 count_to_4_for_intra_FIFO <= 0;
    //                 count_to_3_for_inter_FIFO <= 0;
    //                 count_to_9_for_inter_RE <= 0;
    //                 count_to_4_for_pipeline <= 4;
    //                 sram_addr_r <= 0;
    //                 start_compute_RE <= 0; //turn off everything and become idle
    //                 for (i = 0; i < 4; i = i + 1) begin
    //                     for (j = 0; j < 5; j = j + 1) begin
    //                         FIFO[i][j] <= 0;
    //                     end
    //                     y_finish[i] <= 0;
    //                 end
    //             end
    //         end
    //         if (y_finish[0]) begin //fetch new column 0
    //             FIFO[0][4] <= {sram_out_data[5], sram_out_data[4], sram_out_data[3], sram_out_data[2], sram_out_data[1], sram_out_data[0]};
    //             for (j = 0; j < 4; j = j + 1) begin
    //                 FIFO[0][j] <= FIFO[0][j+1];
    //             end
    //             if (count_to_4_for_intra_FIFO == 4) begin
    //                 count_to_4_for_intra_FIFO <= 0;
    //                 y_finish[0] <= 0;
    //             end
    //             else begin
    //                 count_to_4_for_intra_FIFO <= count_to_4_for_intra_FIFO + 1;
    //             end
    //             sram_addr_r <= sram_addr_w;
    //         end
    //         else if (y_finish[1]) begin
    //             FIFO[1][4] <= {sram_out_data[5], sram_out_data[4], sram_out_data[3], sram_out_data[2], sram_out_data[1], sram_out_data[0]};
    //             for (j = 0; j < 4; j = j + 1) begin
    //                 FIFO[1][j] <= FIFO[1][j+1];
    //             end
    //             if (count_to_4_for_intra_FIFO == 4) begin
    //                 count_to_4_for_intra_FIFO <= 0;
    //                 y_finish[1] <= 0;
    //             end
    //             else begin
    //                 count_to_4_for_intra_FIFO <= count_to_4_for_intra_FIFO + 1;
    //             end
    //             sram_addr_r <= sram_addr_w;
    //         end
    //         else if (y_finish[2]) begin
    //             FIFO[2][4] <= {sram_out_data[5], sram_out_data[4], sram_out_data[3], sram_out_data[2], sram_out_data[1], sram_out_data[0]};
    //             for (j = 0; j < 4; j = j + 1) begin
    //                 FIFO[2][j] <= FIFO[2][j+1];
    //             end
    //             if (count_to_4_for_intra_FIFO == 4) begin
    //                 count_to_4_for_intra_FIFO <= 0;
    //                 y_finish[2] <= 0;
    //             end
    //             else begin
    //                 count_to_4_for_intra_FIFO <= count_to_4_for_intra_FIFO + 1;
    //             end
    //             sram_addr_r <= sram_addr_w;
    //         end
    //         else if (y_finish[3]) begin
    //             FIFO[3][4] <= {sram_out_data[5], sram_out_data[4], sram_out_data[3], sram_out_data[2], sram_out_data[1], sram_out_data[0]};
    //             for (j = 0; j < 4; j = j + 1) begin
    //                 FIFO[3][j] <= FIFO[3][j+1];
    //             end
    //             if (count_to_4_for_intra_FIFO == 4) begin
    //                 count_to_4_for_intra_FIFO <= 0;
    //                 y_finish[3] <= 0;
    //             end
    //             else begin
    //                 count_to_4_for_intra_FIFO <= count_to_4_for_intra_FIFO + 1;
    //             end
    //             sram_addr_r <= sram_addr_w;
    //         end
    //     end
    // end
