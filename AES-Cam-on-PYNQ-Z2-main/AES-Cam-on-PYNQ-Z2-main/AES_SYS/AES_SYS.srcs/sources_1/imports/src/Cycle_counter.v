`timescale 1ns / 1ps

module Cycle_counter (
    input  wire        clk,
    input  wire        rst,
    input  wire        start, // ��靘 GPIO ��� start 閮��
    input  wire        done,  // ��靘 RFC8439 ��� done 閮��
    output reg  [31:0] count  // 頛詨蝯血銝��� GPIO 霈����
);

    reg is_running;
    reg start_d;
    wire start_pulse;

    // ��楠閫貊�皜� (��� RFC8439 �����摩摰��郊)
    assign start_pulse = start & ~start_d;

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start_d <= 1'b0;
        end else begin
            start_d <= start;
        end
    end

    always @(posedge clk or posedge rst) begin
        if (rst) begin
            count      <= 32'd0;
            is_running <= 1'b0;
        end else begin
            // �� start ����飛�銝阡�����
            if (start_pulse) begin
                count      <= 32'd0;
                is_running <= 1'b1;
            end 
            // �� RFC8439 ��� done 閮���迫閮��
            else if (done) begin
                is_running <= 1'b0;
            end 
            // 甇�����葉嚗��� clock cycle ��� 1
            else if (is_running) begin
                count <= count + 32'd1;
            end
        end
    end

endmodule