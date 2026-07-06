`timescale 1ns / 1ps

module branch_predictor(
    input wire clk,
    input wire rst,
    input wire[31:0] pcF,
    output wire pred_takenF,
    output wire[31:0] pred_targetF,
    input wire updateE,
    input wire[31:0] pcE,
    input wire takenE,
    input wire[31:0] targetE
    );

    reg valid[0:63];
    reg[23:0] tag[0:63];
    reg[31:0] target[0:63];
    reg[1:0] counter[0:63];
    integer i;

    wire[5:0] idxF = pcF[7:2];
    wire[23:0] tagF = pcF[31:8];
    wire[5:0] idxE = pcE[7:2];
    wire[23:0] tagE = pcE[31:8];

    assign pred_takenF = valid[idxF] && (tag[idxF] == tagF) && counter[idxF][1];
    assign pred_targetF = target[idxF];

    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 64; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i] <= 24'b0;
                target[i] <= 32'b0;
                counter[i] <= 2'b01;
            end
        end else if (updateE) begin
            valid[idxE] <= 1'b1;
            tag[idxE] <= tagE;
            target[idxE] <= targetE;
            if (takenE) begin
                if (counter[idxE] != 2'b11) counter[idxE] <= counter[idxE] + 2'b01;
            end else begin
                if (counter[idxE] != 2'b00) counter[idxE] <= counter[idxE] - 2'b01;
            end
        end
    end
endmodule
