module Poly1305 (
    input  wire          clk,
    input  wire          rst,
    input  wire          valid_in,
    output reg           ready_out,
    input  wire [255:0]  mac_key,
    input  wire [127:0]  data_in,
    input  wire          pad_bit,
    input  wire          finalize,
    output reg  [127:0]  mac_tag,
    output reg           tag_valid
);
    localparam [5:0] ST_IDLE = 6'd0;

    localparam [5:0] ST_ADD0 = 6'd1;
    localparam [5:0] ST_ADD1 = 6'd2;
    localparam [5:0] ST_ADD2 = 6'd3;
    localparam [5:0] ST_ADD3 = 6'd4;
    localparam [5:0] ST_ADD4 = 6'd5;
    localparam [5:0] ST_ADD5 = 6'd6;

    localparam [5:0] ST_MUL0_LOAD = 6'd7;
    localparam [5:0] ST_MUL0_MULT = 6'd29;
    localparam [5:0] ST_MUL0_TREE = 6'd34; // 新增：加法樹第一級
    localparam [5:0] ST_MUL0_SAVE = 6'd8;  // 加法樹第二級並存入 d

    localparam [5:0] ST_MUL1_LOAD = 6'd9;
    localparam [5:0] ST_MUL1_MULT = 6'd30;
    localparam [5:0] ST_MUL1_TREE = 6'd35; // 新增
    localparam [5:0] ST_MUL1_SAVE = 6'd10;

    localparam [5:0] ST_MUL2_LOAD = 6'd11;
    localparam [5:0] ST_MUL2_MULT = 6'd31;
    localparam [5:0] ST_MUL2_TREE = 6'd36; // 新增
    localparam [5:0] ST_MUL2_SAVE = 6'd12;

    localparam [5:0] ST_MUL3_LOAD = 6'd13;
    localparam [5:0] ST_MUL3_MULT = 6'd32;
    localparam [5:0] ST_MUL3_TREE = 6'd37; // 新增
    localparam [5:0] ST_MUL3_SAVE = 6'd14;

    localparam [5:0] ST_MUL4_LOAD = 6'd15;
    localparam [5:0] ST_MUL4_MULT = 6'd33;
    localparam [5:0] ST_MUL4_TREE = 6'd38; // 新增
    localparam [5:0] ST_MUL4_SAVE = 6'd16;

    localparam [5:0] ST_RED0 = 6'd17;
    localparam [5:0] ST_RED1 = 6'd18;
    localparam [5:0] ST_RED2 = 6'd19;
    localparam [5:0] ST_RED3 = 6'd20;
    localparam [5:0] ST_RED4 = 6'd21;
    localparam [5:0] ST_RED5 = 6'd22;
    localparam [5:0] ST_RED6 = 6'd23;
    localparam [5:0] ST_RED7 = 6'd24;

    localparam [5:0] ST_FIN_PACK = 6'd25;
    localparam [5:0] ST_FIN_RED  = 6'd26;
    localparam [5:0] ST_FIN_ADD  = 6'd27;
    localparam [5:0] ST_FIN_DONE = 6'd28;

    localparam [31:0] LIMB_MASK32 = 32'h03ff_ffff;
    localparam [130:0] P130 = 131'h3fffffffffffffffffffffffffffffffb;

    reg [5:0] state;
    reg [5:0] next_state;

    reg [31:0] h0, h1, h2, h3, h4;
    reg [26:0] r0, r1, r2, r3, r4;
    
    // --- 優化：預計算暫存器 (29-bit) ---
    reg [28:0] u1, u2, u3, u4; 
    
    reg [127:0] s_reg;

    reg is_first;
    reg is_final;

    reg [63:0] d0, d1, d2, d3, d4;

    reg [130:0] h_full_reg;
    reg [130:0] h_red_reg;
    reg [127:0] tag_sum_reg;

    // --- 優化：擴展位寬與加法樹 Pipeline 暫存器 ---
    reg [26:0] ma0, ma1, ma2, ma3, ma4;
    reg [28:0] mb0, mb1, mb2, mb3, mb4;
    
    // 使用 keep 屬性防止合成工具過度優化 (Vivado/Quartus 適用)
    (* keep = "true" *) reg [55:0] p0_reg, p1_reg, p2_reg, p3_reg, p4_reg; 

    reg [63:0] s01_reg; // 儲存 p0 + p1
    reg [63:0] s23_reg; // 儲存 p2 + p3
    reg [63:0] s4_reg;  // 儲存 p4
    // ---------------------------------------------

    wire [127:0] r_clamped_w;
    assign r_clamped_w = mac_key[127:0] & 128'h0ffffffc0ffffffc0ffffffc0fffffff;

    wire [26:0] n0_w = data_in[25:0];
    wire [26:0] n1_w = data_in[51:26];
    wire [26:0] n2_w = data_in[77:52];
    wire [26:0] n3_w = data_in[103:78];
    wire [26:0] n4_w = {3'd0, data_in[127:104]} + (pad_bit ? 27'h1000000 : 27'd0);

    wire [26:0] h0_w = h0[26:0];
    wire [26:0] h1_w = h1[26:0];
    wire [26:0] h2_w = h2[26:0];
    wire [26:0] h3_w = h3[26:0];
    wire [26:0] h4_w = h4[26:0];

    wire [31:0] red5_h0_m = h0 & LIMB_MASK32;
    wire [31:0] red5_h1_a = h1 + (h0 >> 26);
    wire [31:0] red5_h1_m = red5_h1_a & LIMB_MASK32;
    wire [31:0] red5_h2_a = h2 + (red5_h1_a >> 26);

    wire [31:0] red6_h2_m = h2 & LIMB_MASK32;
    wire [31:0] red6_h3_a = h3 + (h2 >> 26);
    wire [31:0] red6_h3_m = red6_h3_a & LIMB_MASK32;
    wire [31:0] red6_h4_a = h4 + (red6_h3_a >> 26);

    wire [31:0] red7_h4_m = h4 & LIMB_MASK32;
    wire [31:0] red7_h0_a = h0 + ((h4 >> 26) + ((h4 >> 26) << 2));
    wire [31:0] red7_h0_m = red7_h0_a & LIMB_MASK32;
    wire [31:0] red7_h1_a = h1 + (red7_h0_a >> 26);

    wire [130:0] h_full_w =
        {104'd0, h0[26:0]} +
        {78'd0,  h1[26:0], 26'd0} +
        {52'd0,  h2[26:0], 52'd0} +
        {26'd0,  h3[26:0], 78'd0} +
        {        h4[26:0], 104'd0};

    wire [130:0] h_red_w =
        (h_full_reg >= P130) ? (h_full_reg - P130) : h_full_reg;

    wire [128:0] tag_sum_w =
        {1'b0, h_red_reg[127:0]} + {1'b0, s_reg};

    always @(*) begin
        next_state = state;

        case (state)
            ST_IDLE: if (valid_in) next_state = ST_ADD0;

            ST_ADD0: next_state = ST_ADD1;
            ST_ADD1: next_state = ST_ADD2;
            ST_ADD2: next_state = ST_ADD3;
            ST_ADD3: next_state = ST_ADD4;
            ST_ADD4: next_state = ST_ADD5;
            ST_ADD5: next_state = ST_MUL0_LOAD;

            // --- 修改：加入 TREE 狀態 ---
            ST_MUL0_LOAD: next_state = ST_MUL0_MULT;
            ST_MUL0_MULT: next_state = ST_MUL0_TREE;
            ST_MUL0_TREE: next_state = ST_MUL0_SAVE;
            ST_MUL0_SAVE: next_state = ST_MUL1_LOAD;

            ST_MUL1_LOAD: next_state = ST_MUL1_MULT;
            ST_MUL1_MULT: next_state = ST_MUL1_TREE;
            ST_MUL1_TREE: next_state = ST_MUL1_SAVE;
            ST_MUL1_SAVE: next_state = ST_MUL2_LOAD;

            ST_MUL2_LOAD: next_state = ST_MUL2_MULT;
            ST_MUL2_MULT: next_state = ST_MUL2_TREE;
            ST_MUL2_TREE: next_state = ST_MUL2_SAVE;
            ST_MUL2_SAVE: next_state = ST_MUL3_LOAD;

            ST_MUL3_LOAD: next_state = ST_MUL3_MULT;
            ST_MUL3_MULT: next_state = ST_MUL3_TREE;
            ST_MUL3_TREE: next_state = ST_MUL3_SAVE;
            ST_MUL3_SAVE: next_state = ST_MUL4_LOAD;

            ST_MUL4_LOAD: next_state = ST_MUL4_MULT;
            ST_MUL4_MULT: next_state = ST_MUL4_TREE;
            ST_MUL4_TREE: next_state = ST_MUL4_SAVE;
            ST_MUL4_SAVE: next_state = ST_RED0;
            // ----------------------------

            ST_RED0: next_state = ST_RED1;
            ST_RED1: next_state = ST_RED2;
            ST_RED2: next_state = ST_RED3;
            ST_RED3: next_state = ST_RED4;
            ST_RED4: next_state = ST_RED5;
            ST_RED5: next_state = ST_RED6;
            ST_RED6: next_state = ST_RED7;

            ST_RED7: begin
                if (is_final) next_state = ST_FIN_PACK;
                else          next_state = ST_IDLE;
            end

            ST_FIN_PACK: next_state = ST_FIN_RED;
            ST_FIN_RED:  next_state = ST_FIN_ADD;
            ST_FIN_ADD:  next_state = ST_FIN_DONE;
            ST_FIN_DONE: next_state = ST_IDLE;

            default: next_state = ST_IDLE;
        endcase
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;

            h0 <= 32'd0; h1 <= 32'd0; h2 <= 32'd0; h3 <= 32'd0; h4 <= 32'd0;
            r0 <= 27'd0; r1 <= 27'd0; r2 <= 27'd0; r3 <= 27'd0; r4 <= 27'd0;
            
            u1 <= 29'd0; u2 <= 29'd0; u3 <= 29'd0; u4 <= 29'd0;

            s_reg <= 128'd0;

            d0 <= 64'd0; d1 <= 64'd0; d2 <= 64'd0; d3 <= 64'd0; d4 <= 64'd0;

            ma0 <= 27'd0; ma1 <= 27'd0; ma2 <= 27'd0; ma3 <= 27'd0; ma4 <= 27'd0;
            mb0 <= 29'd0; mb1 <= 29'd0; mb2 <= 29'd0; mb3 <= 29'd0; mb4 <= 29'd0;

            p0_reg <= 56'd0; p1_reg <= 56'd0; p2_reg <= 56'd0; p3_reg <= 56'd0; p4_reg <= 56'd0;

            // --- 新增：初始化管線化暫存器 ---
            s01_reg <= 64'd0;
            s23_reg <= 64'd0;
            s4_reg  <= 64'd0;
            // --------------------------------

            h_full_reg <= 131'd0;
            h_red_reg  <= 131'd0;
            tag_sum_reg <= 128'd0;

            is_first <= 1'b1;
            is_final <= 1'b0;
        end else begin
            state <= next_state;

            case (state)
                ST_IDLE: begin
                    if (valid_in) begin
                        is_final <= finalize;

                        d0 <= 64'd0; d1 <= 64'd0; d2 <= 64'd0; d3 <= 64'd0; d4 <= 64'd0;

                        if (is_first) begin
                            r0 <= r_clamped_w[25:0];
                            r1 <= r_clamped_w[51:26];
                            r2 <= r_clamped_w[77:52];
                            r3 <= r_clamped_w[103:78];
                            r4 <= {3'd0, r_clamped_w[127:104]};
                            
                            // 預計算 r * 5
                            u1 <= {3'd0, r_clamped_w[51:26]}  + ({3'd0, r_clamped_w[51:26]}  << 2);
                            u2 <= {3'd0, r_clamped_w[77:52]}  + ({3'd0, r_clamped_w[77:52]}  << 2);
                            u3 <= {3'd0, r_clamped_w[103:78]} + ({3'd0, r_clamped_w[103:78]} << 2);
                            u4 <= {5'd0, r_clamped_w[127:104]}+ ({5'd0, r_clamped_w[127:104]}<< 2);

                            s_reg <= mac_key[255:128];

                            h0 <= {5'd0, n0_w};
                            h1 <= {5'd0, n1_w};
                            h2 <= {5'd0, n2_w};
                            h3 <= {5'd0, n3_w};
                            h4 <= {5'd0, n4_w};

                            is_first <= 1'b0;
                        end else begin
                            h0 <= h0 + {5'd0, n0_w};
                            h1 <= h1 + {5'd0, n1_w};
                            h2 <= h2 + {5'd0, n2_w};
                            h3 <= h3 + {5'd0, n3_w};
                            h4 <= h4 + {5'd0, n4_w};
                        end
                    end
                end

                ST_ADD0: begin
                    h1 <= h1 + (h0 >> 26);
                    h0 <= h0 & LIMB_MASK32;
                end
                ST_ADD1: begin
                    h2 <= h2 + (h1 >> 26);
                    h1 <= h1 & LIMB_MASK32;
                end
                ST_ADD2: begin
                    h3 <= h3 + (h2 >> 26);
                    h2 <= h2 & LIMB_MASK32;
                end
                ST_ADD3: begin
                    h4 <= h4 + (h3 >> 26);
                    h3 <= h3 & LIMB_MASK32;
                end
                ST_ADD4: begin
                    h0 <= h0 + ((h4 >> 26) + ((h4 >> 26) << 2));
                    h4 <= h4 & LIMB_MASK32;
                end
                ST_ADD5: begin
                    h1 <= h1 + (h0 >> 26);
                    h0 <= h0 & LIMB_MASK32;
                end

                ST_MUL0_LOAD: begin
                    ma0 <= h0_w; mb0 <= {3'd0, r0}; 
                    ma1 <= h1_w; mb1 <= u4;
                    ma2 <= h2_w; mb2 <= u3;
                    ma3 <= h3_w; mb3 <= u2;
                    ma4 <= h4_w; mb4 <= u1;
                end
                ST_MUL1_LOAD: begin
                    ma0 <= h0_w; mb0 <= {3'd0, r1};
                    ma1 <= h1_w; mb1 <= {3'd0, r0};
                    ma2 <= h2_w; mb2 <= u4;
                    ma3 <= h3_w; mb3 <= u3;
                    ma4 <= h4_w; mb4 <= u2;
                end
                ST_MUL2_LOAD: begin
                    ma0 <= h0_w; mb0 <= {3'd0, r2};
                    ma1 <= h1_w; mb1 <= {3'd0, r1};
                    ma2 <= h2_w; mb2 <= {3'd0, r0};
                    ma3 <= h3_w; mb3 <= u4;
                    ma4 <= h4_w; mb4 <= u3;
                end
                ST_MUL3_LOAD: begin
                    ma0 <= h0_w; mb0 <= {3'd0, r3};
                    ma1 <= h1_w; mb1 <= {3'd0, r2};
                    ma2 <= h2_w; mb2 <= {3'd0, r1};
                    ma3 <= h3_w; mb3 <= {3'd0, r0};
                    ma4 <= h4_w; mb4 <= u4;
                end
                ST_MUL4_LOAD: begin
                    ma0 <= h0_w; mb0 <= {3'd0, r4};
                    ma1 <= h1_w; mb1 <= {3'd0, r3};
                    ma2 <= h2_w; mb2 <= {3'd0, r2};
                    ma3 <= h3_w; mb3 <= {3'd0, r1};
                    ma4 <= h4_w; mb4 <= {3'd0, r0};
                end

                ST_MUL0_MULT, ST_MUL1_MULT, ST_MUL2_MULT, ST_MUL3_MULT, ST_MUL4_MULT: begin
                    p0_reg <= ma0 * mb0;
                    p1_reg <= ma1 * mb1;
                    p2_reg <= ma2 * mb2;
                    p3_reg <= ma3 * mb3;
                    p4_reg <= ma4 * mb4;
                end

                // --- 新增：管線化加法樹第一級 ---
                ST_MUL0_TREE, ST_MUL1_TREE, ST_MUL2_TREE, ST_MUL3_TREE, ST_MUL4_TREE: begin
                    s01_reg <= {8'd0, p0_reg} + {8'd0, p1_reg};
                    s23_reg <= {8'd0, p2_reg} + {8'd0, p3_reg};
                    s4_reg  <= {8'd0, p4_reg};
                end
                // --------------------------------

                // --- 修改：管線化加法樹第二級，直接寫入 d ---
                ST_MUL0_SAVE: d0 <= s01_reg + s23_reg + s4_reg;
                ST_MUL1_SAVE: d1 <= s01_reg + s23_reg + s4_reg;
                ST_MUL2_SAVE: d2 <= s01_reg + s23_reg + s4_reg;
                ST_MUL3_SAVE: d3 <= s01_reg + s23_reg + s4_reg;
                ST_MUL4_SAVE: d4 <= s01_reg + s23_reg + s4_reg;
                // ------------------------------------------

                ST_RED0: begin
                    h0 <= {6'd0, d0[25:0]};
                    d1 <= d1 + (d0 >> 26);
                end
                ST_RED1: begin
                    h1 <= {6'd0, d1[25:0]};
                    d2 <= d2 + (d1 >> 26);
                end
                ST_RED2: begin
                    h2 <= {6'd0, d2[25:0]};
                    d3 <= d3 + (d2 >> 26);
                end
                ST_RED3: begin
                    h3 <= {6'd0, d3[25:0]};
                    d4 <= d4 + (d3 >> 26);
                end
                ST_RED4: begin
                    h4 <= {6'd0, d4[25:0]};
                    h0 <= h0 + ((d4 >> 26) + ((d4 >> 26) << 2));
                end
                ST_RED5: begin
                    h0 <= red5_h0_m;
                    h1 <= red5_h1_m;
                    h2 <= red5_h2_a;
                end
                ST_RED6: begin
                    h2 <= red6_h2_m;
                    h3 <= red6_h3_m;
                    h4 <= red6_h4_a;
                end
                ST_RED7: begin
                    h4 <= red7_h4_m;
                    h0 <= red7_h0_m;
                    h1 <= red7_h1_a;
                end

                ST_FIN_PACK: begin
                    h_full_reg <= h_full_w;
                end
                ST_FIN_RED: begin
                    h_red_reg <= h_red_w;
                end
                ST_FIN_ADD: begin
                    tag_sum_reg <= tag_sum_w[127:0];
                end
                ST_FIN_DONE: begin
                    h0 <= 32'd0;
                    h1 <= 32'd0;
                    h2 <= 32'd0;
                    h3 <= 32'd0;
                    h4 <= 32'd0;

                    h_full_reg <= 131'd0;
                    h_red_reg  <= 131'd0;

                    is_first <= 1'b1;
                    is_final <= 1'b0;
                end

                default: ;
            endcase
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            ready_out <= 1'b1;
            tag_valid <= 1'b0;
            mac_tag   <= 128'd0;
        end else begin
            if (state == ST_IDLE && valid_in) begin
                ready_out <= 1'b0;
                tag_valid <= 1'b0;
            end else if (next_state == ST_IDLE) begin
                ready_out <= 1'b1;
            end else begin
                ready_out <= 1'b0;
            end

            if (state == ST_FIN_DONE) begin
                mac_tag   <= tag_sum_reg;
                tag_valid <= 1'b1;
            end else if (state == ST_IDLE && valid_in) begin
                tag_valid <= 1'b0;
            end
        end
    end

endmodule