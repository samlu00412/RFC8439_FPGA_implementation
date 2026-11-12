module Quarter_round (
    input [31:0] a,
    input [31:0] b,
    input [31:0] c,
    input [31:0] d,
    output [31:0] out_a,
    output [31:0] out_b,
    output [31:0] out_c,
    output [31:0] out_d
);
    wire [31:0] a1, b1, c1, d1;
    wire [31:0] a2, b2, c2, d2;

    wire [31:0] d_xor1, b_xor1, d_xor2, b_xor2;

    assign a1 = a + b;
    assign d_xor1 = d ^ a1;
    assign d1 = {d_xor1[15:0], d_xor1[31:16]};

    assign c1 = c + d1;
    assign b_xor1 = b ^ c1;
    assign b1 = {b_xor1[19:0], b_xor1[31:20]};

    assign a2 = a1 + b1;
    assign d_xor2 = d1 ^ a2;
    assign d2 = {d_xor2[23:0], d_xor2[31:24]};

    assign c2 = c1 + d2;
    assign b_xor2 = b1 ^ c2;
    assign b2 = {b_xor2[24:0], b_xor2[31:25]};

    assign out_a = a2;
    assign out_b = b2;
    assign out_c = c2;
    assign out_d = d2;

endmodule