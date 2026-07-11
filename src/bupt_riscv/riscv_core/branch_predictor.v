`timescale 1ns / 1ps

// 简单分支预测器/BTB。
// 取指阶段使用当前 PC 查询预测目标，执行阶段用真实结果更新或失效对应条目。
module branch_predictor(
    input wire clk,
    input wire rst,
    input wire[31:0] pcF,
    output wire pred_takenF,
    output wire[31:0] pred_targetF,
    input wire updateE,
    input wire invalidateE,
    input wire[31:0] pcE,
    input wire takenE,
    input wire[31:0] targetE
    );

    reg valid[0:127];
    reg[22:0] tag[0:127];
    reg[31:0] target[0:127];
    reg[1:0] counter[0:127];
    integer i;

    wire[6:0] idxF = pcF[8:2];
    wire[6:0] idxE = pcE[8:2];
    wire tag_matchF = valid[idxF] && (tag[idxF] == pcF[31:9]);
    wire tag_matchE = valid[idxE] && (tag[idxE] == pcE[31:9]);

    assign pred_takenF = tag_matchF && counter[idxF][1];
    assign pred_targetF = target[idxF];

    // 预测表只在时钟沿更新；非分支指令命中错误 BTB 时清除对应条目。
    always @(posedge clk) begin
        if (rst) begin
            for (i = 0; i < 128; i = i + 1) begin
                valid[i] <= 1'b0;
                tag[i] <= 23'b0;
                target[i] <= 32'b0;
                counter[i] <= 2'b01;
            end
        end else if (invalidateE) begin
            // A non-branch instruction was fetched at a PC whose BTB entry
            // falsely predicted taken. Drop the matching entry.
            if (tag_matchE) valid[idxE] <= 1'b0;
        end else if (updateE) begin
            valid[idxE] <= 1'b1;
            tag[idxE] <= pcE[31:9];
            target[idxE] <= targetE;
            if (takenE) begin
                if (counter[idxE] != 2'b11) counter[idxE] <= counter[idxE] + 2'b01;
            end else begin
                if (counter[idxE] != 2'b00) counter[idxE] <= counter[idxE] - 2'b01;
            end
        end
    end
endmodule
