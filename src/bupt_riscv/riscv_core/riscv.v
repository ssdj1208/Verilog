`timescale 1ns / 1ps

module riscv(
    input wire clk,
    input wire rst,
    output wire[31:0] pcF,
    input wire[31:0] instrF,
    output wire d_validM,
    input wire d_readyM,
    output wire memwriteM,
    output wire[3:0] wstrbM,
    output wire[31:0] aluoutM,
    output wire[31:0] writedataM,
    input wire[31:0] readdataM,
    output wire perf_retireW,
    output wire perf_branchE,
    output wire perf_mispredictE,
    output wire perf_stall,
    output reg[31:0] debug_branch_pc,
    output reg[31:0] debug_branch_srca,
    output reg[31:0] debug_branch_srcb,
    output reg[31:0] debug_branch_info
    );

    localparam WB_ALU = 2'b00;
    localparam WB_MEM = 2'b01;
    localparam WB_PC4 = 2'b10;

    localparam ALU_ADD  = 4'd0;
    localparam ALU_SUB  = 4'd1;
    localparam ALU_SLL  = 4'd2;
    localparam ALU_SLT  = 4'd3;
    localparam ALU_SLTU = 4'd4;
    localparam ALU_XOR  = 4'd5;
    localparam ALU_SRL  = 4'd6;
    localparam ALU_SRA  = 4'd7;
    localparam ALU_OR   = 4'd8;
    localparam ALU_AND  = 4'd9;
    localparam ALU_COPYB = 5'd10;
    localparam ALU_MUL   = 5'd11;
    localparam ALU_MULH  = 5'd12;
    localparam ALU_MULHSU = 5'd13;
    localparam ALU_MULHU = 5'd14;
    localparam ALU_DIV   = 5'd15;
    localparam ALU_DIVU  = 5'd16;
    localparam ALU_REM   = 5'd17;
    localparam ALU_REMU  = 5'd18;

    wire stallF;
    wire stallD;
    wire flushD;
    wire flushE;
    wire memstallM;
    wire divstallE;
    wire idex_en;

    wire[31:0] pcplus4F = pcF + 32'd4;
    wire pred_takenF;
    wire[31:0] pred_targetF;
    wire redirectE;
    wire[31:0] redirect_targetE;
    wire[31:0] pcnextF = redirectE ? redirect_targetE :
                          pred_takenF ? pred_targetF : pcplus4F;

    pc #(32) pcreg(clk, rst, ~stallF & ~memstallM, pcnextF, pcF);

    // IF/ID
    wire[31:0] instrD;
    wire[31:0] pcD;
    wire[31:0] pcplus4D;
    wire pred_takenD;
    wire[31:0] pred_targetD;
    wire validD;

    flopenrc #(32) ifid_instr(clk, rst, ~stallD & ~memstallM, flushD, instrF, instrD);
    flopenrc #(32) ifid_pc(clk, rst, ~stallD & ~memstallM, flushD, pcF, pcD);
    flopenrc #(32) ifid_pc4(clk, rst, ~stallD & ~memstallM, flushD, pcplus4F, pcplus4D);
    flopenrc #(1)  ifid_pred_taken(clk, rst, ~stallD & ~memstallM, flushD, pred_takenF, pred_takenD);
    flopenrc #(32) ifid_pred_target(clk, rst, ~stallD & ~memstallM, flushD, pred_targetF, pred_targetD);
    flopenrc #(1)  ifid_valid(clk, rst, ~stallD & ~memstallM, flushD, 1'b1, validD);

    wire[6:0] opcodeD = instrD[6:0];
    wire[2:0] funct3D = instrD[14:12];
    wire[6:0] funct7D = instrD[31:25];
    wire[4:0] rs1D = instrD[19:15];
    wire[4:0] rs2D = instrD[24:20];
    wire[4:0] rdD  = instrD[11:7];

    wire[31:0] rd1D;
    wire[31:0] rd2D;
    wire[31:0] resultW;
    wire[4:0] rdW;
    wire regwriteW;

    regfile rf(clk, regwriteW, rs1D, rs2D, rdW, resultW, rd1D, rd2D);

    wire[31:0] immD;
    immgen ig(instrD, immD);

    reg regwriteD;
    reg memreadD;
    reg memwriteD;
    reg[1:0] wbselD;
    reg alusrcD;
    reg[1:0] srca_selD; // 0 rs1, 1 pc, 2 zero
    reg[4:0] alucontrolD;
    reg branchD;
    reg jumpD;
    reg jalrD;
    reg illegalD;
    reg uses_rs1D;
    reg uses_rs2D;
    reg[2:0] load_funct3D;
    reg[2:0] store_funct3D;

    always @(*) begin
        regwriteD = 1'b0;
        memreadD = 1'b0;
        memwriteD = 1'b0;
        wbselD = WB_ALU;
        alusrcD = 1'b0;
        srca_selD = 2'b00;
        alucontrolD = ALU_ADD;
        branchD = 1'b0;
        jumpD = 1'b0;
        jalrD = 1'b0;
        illegalD = 1'b0;
        uses_rs1D = 1'b0;
        uses_rs2D = 1'b0;
        load_funct3D = funct3D;
        store_funct3D = funct3D;

        case (opcodeD)
            7'b0110111: begin // lui
                regwriteD = 1'b1;
                alusrcD = 1'b1;
                srca_selD = 2'b10;
                alucontrolD = ALU_COPYB;
            end
            7'b0010111: begin // auipc
                regwriteD = 1'b1;
                alusrcD = 1'b1;
                srca_selD = 2'b01;
                alucontrolD = ALU_ADD;
            end
            7'b1101111: begin // jal
                regwriteD = 1'b1;
                wbselD = WB_PC4;
                jumpD = 1'b1;
            end
            7'b1100111: begin // jalr
                regwriteD = 1'b1;
                wbselD = WB_PC4;
                jumpD = 1'b1;
                jalrD = 1'b1;
                uses_rs1D = 1'b1;
            end
            7'b1100011: begin // branch
                branchD = 1'b1;
                uses_rs1D = 1'b1;
                uses_rs2D = 1'b1;
            end
            7'b0000011: begin // load
                regwriteD = 1'b1;
                memreadD = 1'b1;
                wbselD = WB_MEM;
                alusrcD = 1'b1;
                uses_rs1D = 1'b1;
            end
            7'b0100011: begin // store
                memwriteD = 1'b1;
                alusrcD = 1'b1;
                uses_rs1D = 1'b1;
                uses_rs2D = 1'b1;
            end
            7'b0010011: begin // immediate ALU
                regwriteD = 1'b1;
                alusrcD = 1'b1;
                uses_rs1D = 1'b1;
                case (funct3D)
                    3'b000: alucontrolD = ALU_ADD;  // addi
                    3'b010: alucontrolD = ALU_SLT;  // slti
                    3'b011: alucontrolD = ALU_SLTU; // sltiu
                    3'b100: alucontrolD = ALU_XOR;
                    3'b110: alucontrolD = ALU_OR;
                    3'b111: alucontrolD = ALU_AND;
                    3'b001: alucontrolD = ALU_SLL;
                    3'b101: alucontrolD = funct7D[5] ? ALU_SRA : ALU_SRL;
                    default: illegalD = 1'b1;
                endcase
            end
            7'b0110011: begin // register ALU
                regwriteD = 1'b1;
                uses_rs1D = 1'b1;
                uses_rs2D = 1'b1;
                if (funct7D == 7'b0000001) begin
                    case (funct3D)
                        3'b000: alucontrolD = ALU_MUL;
                        3'b001: alucontrolD = ALU_MULH;
                        3'b010: alucontrolD = ALU_MULHSU;
                        3'b011: alucontrolD = ALU_MULHU;
                        3'b100: alucontrolD = ALU_DIV;
                        3'b101: alucontrolD = ALU_DIVU;
                        3'b110: alucontrolD = ALU_REM;
                        3'b111: alucontrolD = ALU_REMU;
                        default: illegalD = 1'b1;
                    endcase
                end else begin
                    case (funct3D)
                        3'b000: alucontrolD = funct7D[5] ? ALU_SUB : ALU_ADD;
                        3'b001: alucontrolD = ALU_SLL;
                        3'b010: alucontrolD = ALU_SLT;
                        3'b011: alucontrolD = ALU_SLTU;
                        3'b100: alucontrolD = ALU_XOR;
                        3'b101: alucontrolD = funct7D[5] ? ALU_SRA : ALU_SRL;
                        3'b110: alucontrolD = ALU_OR;
                        3'b111: alucontrolD = ALU_AND;
                        default: illegalD = 1'b1;
                    endcase
                end
            end
            default: begin
                illegalD = (instrD != 32'b0);
            end
        endcase
    end

    // ID/EX
    wire[31:0] pcE, pcplus4E, rd1E, rd2E, immE;
    wire[4:0] rs1E, rs2E, rdE;
    wire[2:0] funct3E, load_funct3E, store_funct3E;
    wire regwriteE, memreadE, memwriteE, alusrcE, branchE, jumpE, jalrE, validE;
    wire[1:0] wbselE, srca_selE;
    wire[4:0] alucontrolE;
    wire pred_takenE;
    wire[31:0] pred_targetE;

    assign idex_en = ~memstallM & ~divstallE;

    flopenrc #(32) idex_pc(clk, rst, idex_en, flushE, pcD, pcE);
    flopenrc #(32) idex_pc4(clk, rst, idex_en, flushE, pcplus4D, pcplus4E);
    flopenrc #(32) idex_rd1(clk, rst, idex_en, flushE, rd1D, rd1E);
    flopenrc #(32) idex_rd2(clk, rst, idex_en, flushE, rd2D, rd2E);
    flopenrc #(32) idex_imm(clk, rst, idex_en, flushE, immD, immE);
    flopenrc #(5)  idex_rs1(clk, rst, idex_en, flushE, rs1D, rs1E);
    flopenrc #(5)  idex_rs2(clk, rst, idex_en, flushE, rs2D, rs2E);
    flopenrc #(5)  idex_rd(clk, rst, idex_en, flushE, rdD, rdE);
    flopenrc #(3)  idex_funct3(clk, rst, idex_en, flushE, funct3D, funct3E);
    flopenrc #(3)  idex_loadfunct(clk, rst, idex_en, flushE, load_funct3D, load_funct3E);
    flopenrc #(3)  idex_storefunct(clk, rst, idex_en, flushE, store_funct3D, store_funct3E);
    flopenrc #(1)  idex_regwrite(clk, rst, idex_en, flushE, regwriteD & ~illegalD & validD, regwriteE);
    flopenrc #(1)  idex_memread(clk, rst, idex_en, flushE, memreadD & ~illegalD & validD, memreadE);
    flopenrc #(1)  idex_memwrite(clk, rst, idex_en, flushE, memwriteD & ~illegalD & validD, memwriteE);
    flopenrc #(2)  idex_wbsel(clk, rst, idex_en, flushE, wbselD, wbselE);
    flopenrc #(1)  idex_alusrc(clk, rst, idex_en, flushE, alusrcD, alusrcE);
    flopenrc #(2)  idex_srcasel(clk, rst, idex_en, flushE, srca_selD, srca_selE);
    flopenrc #(5)  idex_alucontrol(clk, rst, idex_en, flushE, alucontrolD, alucontrolE);
    flopenrc #(1)  idex_branch(clk, rst, idex_en, flushE, branchD & ~illegalD & validD, branchE);
    flopenrc #(1)  idex_jump(clk, rst, idex_en, flushE, jumpD & ~illegalD & validD, jumpE);
    flopenrc #(1)  idex_jalr(clk, rst, idex_en, flushE, jalrD & ~illegalD & validD, jalrE);
    flopenrc #(1)  idex_pred_taken(clk, rst, idex_en, flushE, pred_takenD, pred_takenE);
    flopenrc #(32) idex_pred_target(clk, rst, idex_en, flushE, pred_targetD, pred_targetE);
    flopenrc #(1)  idex_valid(clk, rst, idex_en, flushE, validD & ~illegalD, validE);

    wire regwriteM;
    wire memreadM;
    wire[1:0] wbselM;
    wire[4:0] rdM;
    wire[31:0] pcplus4M;
    wire[31:0] aluResultM;
    wire[31:0] resultM = (wbselM == WB_PC4) ? pcplus4M : aluResultM;
    wire memtoregM = (wbselM == WB_MEM);

    wire[31:0] aluoutW;
    wire[31:0] readdataW;
    wire[31:0] pcplus4W;
    wire[1:0] wbselW;
    wire[2:0] load_funct3W;
    wire[1:0] load_addrW;

    reg[1:0] forwardaE;
    reg[1:0] forwardbE;
    always @(*) begin
        forwardaE = 2'b00;
        forwardbE = 2'b00;
        if (rs1E != 5'b0) begin
            if ((rs1E == rdM) && regwriteM && ~memtoregM) forwardaE = 2'b10;
            else if ((rs1E == rdW) && regwriteW) forwardaE = 2'b01;
        end
        if (rs2E != 5'b0) begin
            if ((rs2E == rdM) && regwriteM && ~memtoregM) forwardbE = 2'b10;
            else if ((rs2E == rdW) && regwriteW) forwardbE = 2'b01;
        end
    end

    wire[31:0] srca_forwardE = (forwardaE == 2'b10) ? resultM :
                                (forwardaE == 2'b01) ? resultW : rd1E;
    wire[31:0] srcb_forwardE = (forwardbE == 2'b10) ? resultM :
                                (forwardbE == 2'b01) ? resultW : rd2E;
    wire[31:0] aluSrcAE = (srca_selE == 2'b01) ? pcE :
                           (srca_selE == 2'b10) ? 32'b0 : srca_forwardE;
    wire[31:0] aluSrcBE = alusrcE ? immE : srcb_forwardE;

    wire[31:0] aluResultE;
    alu alu(aluSrcAE, aluSrcBE, alucontrolE, aluResultE);

    wire div_opE = validE & ((alucontrolE == ALU_DIV) ||
                             (alucontrolE == ALU_DIVU) ||
                             (alucontrolE == ALU_REM) ||
                             (alucontrolE == ALU_REMU));
    wire div_signedE = (alucontrolE == ALU_DIV) || (alucontrolE == ALU_REM);
    wire div_remE = (alucontrolE == ALU_REM) || (alucontrolE == ALU_REMU);
    wire div_busy;
    wire div_ready;
    wire[31:0] div_resultE;
    wire div_startE = div_opE & ~div_busy & ~div_ready & ~memstallM;
    assign divstallE = div_opE & ~div_ready;

    iter_div div_unit(
        .clk(clk),
        .rst(rst),
        .start(div_startE),
        .signed_op(div_signedE),
        .rem_op(div_remE),
        .dividend_i(srca_forwardE),
        .divisor_i(srcb_forwardE),
        .busy(div_busy),
        .ready(div_ready),
        .result(div_resultE)
        );

    wire[31:0] executeResultE = div_opE ? div_resultE : aluResultE;

    reg branch_takenE;
    always @(*) begin
        case (funct3E)
            3'b000: branch_takenE = (srca_forwardE == srcb_forwardE);
            3'b001: branch_takenE = (srca_forwardE != srcb_forwardE);
            3'b100: branch_takenE = ($signed(srca_forwardE) < $signed(srcb_forwardE));
            3'b101: branch_takenE = ($signed(srca_forwardE) >= $signed(srcb_forwardE));
            3'b110: branch_takenE = (srca_forwardE < srcb_forwardE);
            3'b111: branch_takenE = (srca_forwardE >= srcb_forwardE);
            default: branch_takenE = 1'b0;
        endcase
    end

    wire[31:0] branch_targetE = pcE + immE;
    wire[31:0] jalr_targetE = (srca_forwardE + immE) & 32'hffff_fffe;
    wire actual_takenE = validE & (jumpE | (branchE & branch_takenE));
    wire[31:0] actual_targetE = jalrE ? jalr_targetE : branch_targetE;
    wire pred_wrongE = validE & (branchE | jumpE) &
        ((pred_takenE != actual_takenE) ||
         (actual_takenE && (pred_targetE != actual_targetE)));
    assign redirectE = pred_wrongE;
    assign redirect_targetE = actual_takenE ? actual_targetE : pcplus4E;

    always @(posedge clk) begin
        if (rst) begin
            debug_branch_pc <= 32'b0;
            debug_branch_srca <= 32'b0;
            debug_branch_srcb <= 32'b0;
            debug_branch_info <= 32'b0;
        end else if (validE & branchE & ~memstallM) begin
            debug_branch_pc <= pcE;
            debug_branch_srca <= srca_forwardE;
            debug_branch_srcb <= srcb_forwardE;
            debug_branch_info <= {23'b0, branchE, validE, funct3E,
                                  pred_wrongE, pred_takenE,
                                  actual_takenE, branch_takenE};
        end
    end

    // EX/MEM
    wire[31:0] storeDataM;
    wire[2:0] load_funct3M;
    wire[2:0] store_funct3M;
    wire exmem_bubbleE = divstallE;

    flopenr #(32) exmem_alu(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : executeResultE, aluResultM);
    flopenr #(32) exmem_store(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : srcb_forwardE, storeDataM);
    flopenr #(32) exmem_pc4(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : pcplus4E, pcplus4M);
    flopenr #(5)  exmem_rd(clk, rst, ~memstallM, exmem_bubbleE ? 5'b0 : rdE, rdM);
    flopenr #(3)  exmem_loadfunct(clk, rst, ~memstallM, exmem_bubbleE ? 3'b0 : load_funct3E, load_funct3M);
    flopenr #(3)  exmem_storefunct(clk, rst, ~memstallM, exmem_bubbleE ? 3'b0 : store_funct3E, store_funct3M);
    flopenr #(1)  exmem_regwrite(clk, rst, ~memstallM, exmem_bubbleE ? 1'b0 : (regwriteE & validE), regwriteM);
    flopenr #(1)  exmem_memread(clk, rst, ~memstallM, exmem_bubbleE ? 1'b0 : (memreadE & validE), memreadM);
    flopenr #(1)  exmem_memwrite(clk, rst, ~memstallM, exmem_bubbleE ? 1'b0 : (memwriteE & validE), memwriteM);
    flopenr #(2)  exmem_wbsel(clk, rst, ~memstallM, exmem_bubbleE ? WB_ALU : wbselE, wbselM);

    assign d_validM = memreadM | memwriteM;
    assign memstallM = d_validM & ~d_readyM;
    assign aluoutM = aluResultM;

    store_align store_align(storeDataM, aluResultM[1:0], store_funct3M, writedataM, wstrbM);

    // MEM/WB
    wire validW;
    flopenr #(32) memwb_alu(clk, rst, ~memstallM, aluResultM, aluoutW);
    flopenr #(32) memwb_read(clk, rst, ~memstallM, readdataM, readdataW);
    flopenr #(32) memwb_pc4(clk, rst, ~memstallM, pcplus4M, pcplus4W);
    flopenr #(5)  memwb_rd(clk, rst, ~memstallM, rdM, rdW);
    flopenr #(2)  memwb_wbsel(clk, rst, ~memstallM, wbselM, wbselW);
    flopenr #(3)  memwb_loadfunct(clk, rst, ~memstallM, load_funct3M, load_funct3W);
    flopenr #(2)  memwb_loadaddr(clk, rst, ~memstallM, aluResultM[1:0], load_addrW);
    flopenr #(1)  memwb_regwrite(clk, rst, ~memstallM, regwriteM, regwriteW);
    flopenr #(1)  memwb_valid(clk, rst, ~memstallM, (regwriteM | memreadM | memwriteM), validW);

    wire[31:0] loadDataW;
    load_ext load_ext(readdataW, load_addrW, load_funct3W, loadDataW);
    assign resultW = (wbselW == WB_MEM) ? loadDataW :
                     (wbselW == WB_PC4) ? pcplus4W : aluoutW;

    wire lwstallD = memreadE &&
        (((rs1D == rdE) && uses_rs1D && (rs1D != 5'b0)) ||
         ((rs2D == rdE) && uses_rs2D && (rs2D != 5'b0)));
    assign stallD = lwstallD | divstallE;
    assign stallF = lwstallD | divstallE;
    assign flushD = redirectE & ~memstallM;
    assign flushE = (lwstallD | redirectE) & ~memstallM;

    branch_predictor bp(
        .clk(clk),
        .rst(rst),
        .pcF(pcF),
        .pred_takenF(pred_takenF),
        .pred_targetF(pred_targetF),
        .updateE(validE & branchE & ~memstallM),
        .pcE(pcE),
        .takenE(branch_takenE),
        .targetE(branch_targetE)
        );

    assign perf_retireW = validW & ~memstallM;
    assign perf_branchE = validE & branchE & ~memstallM;
    assign perf_mispredictE = pred_wrongE & ~memstallM;
    assign perf_stall = stallD | memstallM;
endmodule
