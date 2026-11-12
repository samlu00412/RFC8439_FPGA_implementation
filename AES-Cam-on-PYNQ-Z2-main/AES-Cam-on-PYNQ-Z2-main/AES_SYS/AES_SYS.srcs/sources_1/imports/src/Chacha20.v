module Chacha20 (
    input  wire          clk,        // ?t?????
    input  wire          rst,        // ???]?T?? (High Active)
    input  wire          start,      // ???[?K?y???????o?T??
    output reg           ready,      // ?i?D FSM?G512-bit ?K?_?y?w?p????
    input  wire [255:0]  key,        // 256-bit ChaCha20 ???_
    input  wire [95:0]   nonce,      // 96-bit ?H???? (IV)
    input  wire [31:0]   counter,    // ????p??? (0: ???? MAC Key, 1+: ????[?K?K?_?y)
    output wire [511:0]  keystream   // ??X?? 512-bit ?K?_?y
);
    integer i, j;                    // ?£[? for ?j?????????

    // ???A???w?q (?e???X?R?? 3-bit ?H?e??s?W?????A)
    localparam IDLE = 3'd0;          // ???m???A?A???? start ?T??
    localparam CALC_COL = 3'd1;      // ?B???A 1?G???? Column Quarter Round
    localparam CALC_DIAG = 3'd2;     // ?B???A 2?G???? Diagonal Quarter Round
    localparam ADD = 3'd3;           // ?????A?G?N??l?x?}?P?B???G??[
    localparam DONE = 3'd4;          // ???????A?G??X ready ?T??

    // ChaCha20 ?W?w????l?`?? "expand 32-byte k"
    localparam CONSTANT1 = 32'h61707865;
    localparam CONSTANT2 = 32'h3320646e;
    localparam CONSTANT3 = 32'h79622d32;
    localparam CONSTANT4 = 32'h6b206574;

    reg [2:0] state, next_state;     // ?D???A????s??
    reg [3:0] round_cnt;             // ?j??p??? (0 ?? 9?A?@?p 10 ?? 20 rounds)
    reg [31:0] init_buf[0:15];       // ?s???l???A???x?}?A?£[??? ADD ?B?J
    reg [31:0] keystream_buf[0:15];  // ?s??B???P?????G???x?}
    
    reg [31:0] col_reg[0:15];        // Pipeline ??s???G?£Z???? Column ?B???G?A???_ Critical Path

    wire [31:0] col_out[0:15];       // Column Quarter Round ????X??X???u??
    wire [31:0] diagonal_out[0:15];  // Diagonal Quarter Round ????X??X???u??

    // ?N 16 ?? 32-bit word ?????? 512-bit ???????X
    assign keystream = {keystream_buf[15], keystream_buf[14], keystream_buf[13], keystream_buf[12],
                        keystream_buf[11], keystream_buf[10], keystream_buf[9],  keystream_buf[8],
                        keystream_buf[7],  keystream_buf[6],  keystream_buf[5],  keystream_buf[4],
                        keystream_buf[3],  keystream_buf[2],  keystream_buf[1],  keystream_buf[0]};


    // ??@??@?h?GColumn Quarter Round (????B??)
    Quarter_round Col1(.a(keystream_buf[0]), .b(keystream_buf[4]), .c(keystream_buf[8]),
                       .d(keystream_buf[12]), .out_a(col_out[0]), .out_b(col_out[4]),
                       .out_c(col_out[8]), .out_d(col_out[12]));
    Quarter_round Col2(.a(keystream_buf[1]), .b(keystream_buf[5]), .c(keystream_buf[9]),
                       .d(keystream_buf[13]), .out_a(col_out[1]), .out_b(col_out[5]),
                       .out_c(col_out[9]), .out_d(col_out[13]));
    Quarter_round Col3(.a(keystream_buf[2]), .b(keystream_buf[6]), .c(keystream_buf[10]),
                       .d(keystream_buf[14]), .out_a(col_out[2]), .out_b(col_out[6]),
                       .out_c(col_out[10]), .out_d(col_out[14]));
    Quarter_round Col4(.a(keystream_buf[3]), .b(keystream_buf[7]), .c(keystream_buf[11]),
                       .d(keystream_buf[15]), .out_a(col_out[3]), .out_b(col_out[7]),
                       .out_c(col_out[11]), .out_d(col_out[15]));

    // ??@??G?h?GDiagonal Quarter Round (???B??A??J???Y Pipeline ??s?? col_reg)
    Quarter_round Diag1(.a(col_reg[0]), .b(col_reg[5]), .c(col_reg[10]),
                       .d(col_reg[15]), .out_a(diagonal_out[0]), .out_b(diagonal_out[5]),
                       .out_c(diagonal_out[10]), .out_d(diagonal_out[15]));
    Quarter_round Diag2(.a(col_reg[1]), .b(col_reg[6]), .c(col_reg[11]),
                       .d(col_reg[12]), .out_a(diagonal_out[1]), .out_b(diagonal_out[6]),
                       .out_c(diagonal_out[11]), .out_d(diagonal_out[12]));
    Quarter_round Diag3(.a(col_reg[2]), .b(col_reg[7]), .c(col_reg[8]),
                       .d(col_reg[13]), .out_a(diagonal_out[2]), .out_b(diagonal_out[7]),
                       .out_c(diagonal_out[8]), .out_d(diagonal_out[13]));
    Quarter_round Diag4(.a(col_reg[3]), .b(col_reg[4]), .c(col_reg[9]),
                       .d(col_reg[14]), .out_a(diagonal_out[3]), .out_b(diagonal_out[4]),
                       .out_c(diagonal_out[9]), .out_d(diagonal_out[14]));

    // ???A????s???
    always @(posedge clk or posedge rst) begin
        if(rst) state <= IDLE;       // ?J?? rst ???m?^ IDLE ???A
        else state <= next_state;    // ???i??U?@????A
    end

    // ?U?@????A?P?_???
    always @(*) begin
        if(rst) next_state = IDLE;
        else begin
            case (state)
                IDLE: next_state = (start) ? CALC_COL : IDLE;                     // ???? start ?i?J Col ?B??
                CALC_COL: next_state = CALC_DIAG;                                 // Col ????L????i?J Diag
                CALC_DIAG: next_state = (round_cnt == 4'd9) ? ADD : CALC_COL;     // ?]?? 10 ??i?J ADD?A?_?h?~??U?@??
                ADD: next_state = DONE;                                           // ?x?}??[?????i?J DONE
                DONE: next_state = IDLE;                                          // ?????U?@???B??
                default: next_state = IDLE;                                       // ??~???p???@
            endcase
        end
    end

    // ?j??p??????????
    always @(posedge clk or posedge rst) begin
        if(rst) round_cnt <= 4'd0;                                                // ???m?p???
        else if (state == CALC_DIAG) round_cnt <= round_cnt + 4'd1;               // ?C?@?? (Col+Diag) ??????[ 1
        else if (state == IDLE || state == DONE) round_cnt <= 4'd0;               // ???m?£Y??????k?s
    end

    // ????s???|?P??s???g?J
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            for (i = 0; i < 16; i = i + 1) begin
                init_buf[i]      <= 32'd0;
                keystream_buf[i] <= 32'd0;
                col_reg[i]       <= 32'd0;
            end
        end else begin
            case (state)
                IDLE: begin
                    if (start) begin
                        init_buf[0] <= CONSTANT1;
                        init_buf[1] <= CONSTANT2;
                        init_buf[2] <= CONSTANT3;
                        init_buf[3] <= CONSTANT4;

                        keystream_buf[0] <= CONSTANT1;
                        keystream_buf[1] <= CONSTANT2;
                        keystream_buf[2] <= CONSTANT3;
                        keystream_buf[3] <= CONSTANT4;

                        for (i = 0; i < 8; i = i + 1) begin
                            init_buf[4+i] <= key[i*32 +: 32];
                            keystream_buf[4+i] <= key[i*32 +: 32];
                        end

                        init_buf[12] <= counter;
                        keystream_buf[12] <= counter;

                        for (j = 0; j < 3; j = j + 1) begin
                            init_buf[13+j] <= nonce[j*32 +: 32];
                            keystream_buf[13+j] <= nonce[j*32 +: 32];
                        end
                    end
                end

                CALC_COL: begin
                    for (i = 0; i < 16; i = i + 1) begin
                        col_reg[i] <= col_out[i];
                    end
                end

                CALC_DIAG: begin
                    for (i = 0; i < 16; i = i + 1) begin
                        keystream_buf[i] <= diagonal_out[i];
                    end
                end

                ADD: begin
                    for (i = 0; i < 16; i = i + 1) begin
                        keystream_buf[i] <= keystream_buf[i] + init_buf[i];
                    end
                end

                default: begin
                    // ?O????s??
                end
            endcase
        end
    end
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ready <= 1'b0;
        end else begin
            if (start) begin
                ready <= 1'b0;
            end else if (state == ADD) begin
                ready <= 1'b1;
            end else if (state == IDLE) begin
                ready <= 1'b0;
            end
        end
    end
endmodule