`timescale 1ns / 1ps

module riscv(
    input wire clk,
    input wire rst,
    input wire [7:0] irq,
    output wire[31:0] pcF,
    input wire[31:0] instrF,
    input wire i_readyF,
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
    output wire perf_stall_loaduse,
    output wire perf_stall_muldiv,
    output wire perf_stall_dcache,
    output wire perf_stall_ifetch,
    output wire perf_flush_branch,
    output wire perf_flush_trap,
    output wire[31:0] demo_pcF,
    output wire[31:0] demo_pcD,
    output wire[31:0] demo_pcE,
    output wire[31:0] demo_pcM,
    output wire[31:0] demo_pcW,
    output wire[31:0] demo_instrF,
    output wire[31:0] demo_instrD,
    output wire[31:0] demo_instrE,
    output wire[31:0] demo_instrM,
    output wire[31:0] demo_instrW,
    output wire demo_validF,
    output wire demo_validD,
    output wire demo_validE,
    output wire demo_validM,
    output wire demo_validW,
    output wire demo_stallF,
    output wire demo_stallD,
    output reg[31:0] debug_branch_pc,
    output reg[31:0] debug_branch_srca,
    output reg[31:0] debug_branch_srcb,
    output reg[31:0] debug_branch_info
    );

    localparam WB_ALU = 2'b00;
    localparam WB_MEM = 2'b01;
    localparam WB_PC4 = 2'b10;
    localparam WB_CSR = 2'b11;

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
    wire validE;

    wire[31:0] pcplus4F = pcF + 32'd4;
    wire pred_takenF;
    wire[31:0] pred_targetF;
    wire redirectE;
    wire[31:0] redirect_targetE;
    wire bp_invalidateE;
    wire ifetch_stall = ~i_readyF;
    reg redirect_pendingR;
    reg[31:0] redirect_targetR;
    reg fetch_redirectR;
    reg[31:0] fetch_redirect_targetR;
    wire fetch_redirectF = fetch_redirectR & ~stallD;

    // ---- Machine-mode CSR / trap state (declared early, used by pcnextF) ----
    reg [31:0] mtvec;
    reg [31:0] mepc;
    reg [31:0] mcause;
    reg [31:0] mstatus;   // only MIE[3] and MPIE[7] used
    reg [31:0] mie;       // only MEIE[11] used
    wire mstatus_mie  = mstatus[3];
    wire mstatus_mpie = mstatus[7];
    wire meie = mie[11];
    wire irq_pending = (|irq) & meie;
    // trap/mret are taken only when EX holds a real instruction. On trap the
    // EX instruction is squashed before MEM, so mepc=pcE replays it precisely.
    wire trap_can_take = validE & ~memstallM & ~divstallE & ~rst;
    wire trap_take  = mstatus_mie & irq_pending & trap_can_take;
    wire mret_take;        // assigned in EX section
    wire trap_redirect = trap_take;
    wire mret_redirect = mret_take;
    wire trap_flush = (trap_take | mret_take);
    wire pc_redirectF = redirectE | trap_flush | fetch_redirectF;
    wire pc_fetch_holdF = ifetch_stall & ~pc_redirectF;
    wire[31:0] pcseqF = pc_fetch_holdF ? pcF : pcplus4F;

    wire[31:0] pcnextF = trap_redirect ? mtvec :
                         mret_redirect ? mepc :
                         redirectE ? redirect_targetR :
                         fetch_redirectF ? fetch_redirect_targetR : pcseqF;

    wire pc_en = ((~stallD) | pc_redirectF) & ~memstallM;
    pc #(32) pcreg(clk, rst, pc_en, pcnextF, pcF);

    // IF/ID
    wire[31:0] instrD;
    wire[31:0] pcD;
    wire[31:0] pcplus4D;
    wire pred_takenD;
    wire[31:0] pred_targetD;
    wire validD;

    wire ifid_en = ~stallD & ~memstallM;
    wire fetch_validF = i_readyF;
    wire ifid_acceptF = ifid_en & fetch_validF;
    flopenrc #(32) ifid_instr(clk, rst, ifid_en, flushD, fetch_validF ? instrF : 32'b0, instrD);
    flopenrc #(32) ifid_pc(clk, rst, ifid_en, flushD, fetch_validF ? pcF : 32'b0, pcD);
    flopenrc #(32) ifid_pc4(clk, rst, ifid_en, flushD, fetch_validF ? pcplus4F : 32'b0, pcplus4D);
    flopenrc #(1)  ifid_pred_taken(clk, rst, ifid_en, flushD, fetch_validF ? pred_takenF : 1'b0, pred_takenD);
    flopenrc #(32) ifid_pred_target(clk, rst, ifid_en, flushD, fetch_validF ? pred_targetF : 32'b0, pred_targetD);
    flopenrc #(1)  ifid_valid(clk, rst, ifid_en, flushD, fetch_validF, validD);

    always @(posedge clk) begin
        if (rst) begin
            fetch_redirectR <= 1'b0;
            fetch_redirect_targetR <= 32'b0;
        end else if (trap_flush | redirectE) begin
            fetch_redirectR <= 1'b0;
            fetch_redirect_targetR <= 32'b0;
        end else if (~memstallM) begin
            if (fetch_redirectF) begin
                fetch_redirectR <= 1'b0;
                fetch_redirect_targetR <= 32'b0;
            end else if (ifid_acceptF) begin
                fetch_redirectR <= pred_takenF;
                fetch_redirect_targetR <= pred_targetF;
            end
        end
    end

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
    reg csr_weD;
    reg[2:0] csr_opD;   // funct3 of CSR op (001 w, 010 s, 011 c, 1xx imm)
    reg csr_immD;       // 1 if immediate form (csrrwi/si/ci)
    reg mretD;

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
        csr_weD = 1'b0;
        csr_opD = 3'b000;
        csr_immD = 1'b0;
        mretD = 1'b0;

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
            7'b1110011: begin // SYSTEM: CSR instructions / mret
                if (funct3D == 3'b000) begin
                    if (instrD == 32'h30200073) begin
                        mretD = 1'b1;          // mret
                    end else begin
                        illegalD = 1'b1;       // ecall/ebreak not supported yet
                    end
                end else begin
                    regwriteD = 1'b1;
                    wbselD = WB_CSR;
                    csr_weD = 1'b1;
                    csr_opD = funct3D;
                    csr_immD = funct3D[2];
                    uses_rs1D = ~funct3D[2];
                end
            end
            default: begin
                illegalD = (instrD != 32'b0);
            end
        endcase
    end

    // ID/EX
    wire[31:0] pcE, pcplus4E, rd1E, rd2E, immE;
    wire[31:0] instrE;
    wire[4:0] rs1E, rs2E, rdE;
    wire[2:0] funct3E, load_funct3E, store_funct3E;
    wire regwriteE, memreadE, memwriteE, alusrcE, branchE, jumpE, jalrE;
    wire[1:0] wbselE, srca_selE;
    wire[4:0] alucontrolE;
    wire pred_takenE;
    wire[31:0] pred_targetE;
    wire csr_weE, csr_immE, mretE;
    wire[2:0] csr_opE;
    wire[11:0] csr_addrE;
    wire[4:0] zimmE;

    wire regwriteM;
    wire memreadM;
    wire[1:0] wbselM;
    wire[4:0] rdM;
    wire[31:0] pcM;
    wire[31:0] pcplus4M;
    wire[31:0] aluResultM;
    wire[31:0] resultM;

    wire[31:0] pcW;
    wire[31:0] aluoutW;
    wire[31:0] pcplus4W;
    wire[1:0] wbselW;
    wire[31:0] loadDataW;

    wire[1:0] forwardaD =
        (rs1D != 5'b0) ?
            ((rs1D == rdE) && regwriteE && validE && (wbselE != WB_MEM)) ? 2'b10 :
            ((rs1D == rdM) && regwriteM)                                ? 2'b01 : 2'b00
        : 2'b00;
    wire[1:0] forwardbD =
        (rs2D != 5'b0) ?
            ((rs2D == rdE) && regwriteE && validE && (wbselE != WB_MEM)) ? 2'b10 :
            ((rs2D == rdM) && regwriteM)                                ? 2'b01 : 2'b00
        : 2'b00;
    wire[1:0] forwardaE;
    wire[1:0] forwardbE;

    assign idex_en = ~memstallM & ~divstallE;

    flopenrc #(32) idex_pc(clk, rst, idex_en, flushE, pcD, pcE);
    flopenrc #(32) idex_pc4(clk, rst, idex_en, flushE, pcplus4D, pcplus4E);
    flopenrc #(32) idex_instr(clk, rst, idex_en, flushE, instrD, instrE);
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
    flopenrc #(1)  idex_csr_we(clk, rst, idex_en, flushE, csr_weD & ~illegalD & validD, csr_weE);
    flopenrc #(3)  idex_csr_op(clk, rst, idex_en, flushE, csr_opD, csr_opE);
    flopenrc #(1)  idex_csr_imm(clk, rst, idex_en, flushE, csr_immD, csr_immE);
    flopenrc #(1)  idex_mret(clk, rst, idex_en, flushE, mretD & ~illegalD & validD, mretE);
    flopenrc #(12) idex_csr_addr(clk, rst, idex_en, flushE, instrD[31:20], csr_addrE);
    flopenrc #(5)  idex_zimm(clk, rst, idex_en, flushE, instrD[19:15], zimmE);
    flopenrc #(2)  idex_forwarda(clk, rst, idex_en, flushE, forwardaD, forwardaE);
    flopenrc #(2)  idex_forwardb(clk, rst, idex_en, flushE, forwardbD, forwardbE);

    wire[31:0] srca_forwardE = (forwardaE == 2'b10) ? resultM :
                                (forwardaE == 2'b01) ? resultW : rd1E;
    wire[31:0] srcb_forwardE = (forwardbE == 2'b10) ? resultM :
                                (forwardbE == 2'b01) ? resultW : rd2E;
    wire[31:0] aluSrcAE = (srca_selE == 2'b01) ? pcE :
                           (srca_selE == 2'b10) ? 32'b0 : srca_forwardE;
    wire[31:0] aluSrcBE = alusrcE ? immE : srcb_forwardE;

    wire[31:0] aluResultE;
    alu alu(aluSrcAE, aluSrcBE, alucontrolE, aluResultE);

    wire mul_opE = validE & ((alucontrolE == ALU_MUL) ||
                             (alucontrolE == ALU_MULH) ||
                             (alucontrolE == ALU_MULHSU) ||
                             (alucontrolE == ALU_MULHU));
    wire mul_signed_aE = (alucontrolE == ALU_MUL) ||
                         (alucontrolE == ALU_MULH) ||
                         (alucontrolE == ALU_MULHSU);
    wire mul_signed_bE = (alucontrolE == ALU_MUL) ||
                         (alucontrolE == ALU_MULH);
    wire mul_highE = (alucontrolE != ALU_MUL);
    wire mul_busy;
    wire mul_ready;
    wire[31:0] mul_resultE;
    wire mul_startE = mul_opE & ~mul_busy & ~mul_ready & ~memstallM;

    iter_mul mul_unit(
        .clk(clk),
        .rst(rst),
        .start(mul_startE),
        .signed_a(mul_signed_aE),
        .signed_b(mul_signed_bE),
        .high_word(mul_highE),
        .a_i(srca_forwardE),
        .b_i(srcb_forwardE),
        .busy(mul_busy),
        .ready(mul_ready),
        .result(mul_resultE)
        );

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
    assign divstallE = (div_opE & ~div_ready) | (mul_opE & ~mul_ready);

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

    wire[31:0] executeResultE = div_opE ? div_resultE :
                                mul_opE ? mul_resultE : aluResultE;

    wire branch_takenE =
        (funct3E == 3'b000) ? (srca_forwardE == srcb_forwardE) :
        (funct3E == 3'b001) ? (srca_forwardE != srcb_forwardE) :
        (funct3E == 3'b100) ? ($signed(srca_forwardE) <  $signed(srcb_forwardE)) :
        (funct3E == 3'b101) ? ($signed(srca_forwardE) >= $signed(srcb_forwardE)) :
        (funct3E == 3'b110) ? (srca_forwardE <  srcb_forwardE) :
        (funct3E == 3'b111) ? (srca_forwardE >= srcb_forwardE) : 1'b0;

    wire[31:0] branch_targetE = pcE + immE;
    wire[31:0] jalr_targetE = (srca_forwardE + immE) & 32'hffff_fffe;
    wire actual_takenE = validE & (jumpE | (branchE & branch_takenE));
    wire[31:0] actual_targetE = jalrE ? jalr_targetE : branch_targetE;
    // Branches keep the fast predictor check. Jumps are redirected
    // unconditionally from EX so the critical request path does not compare a
    // forwarded JALR target against the predicted target in the same cycle.
    wire branch_mispredictE = validE & branchE &
        ((pred_takenE != branch_takenE) ||
         (branch_takenE && (pred_targetE != branch_targetE)));
    wire jump_redirect_reqE = validE & jumpE;
    // A non-branch instruction must never be redirected by the BTB. If the
    // predictor falsely asserted pred_taken for a non-branch (BTB aliasing),
    // treat it as a mispredict and redirect to pc+4 so the correct sequential
    // path is restored instead of silently diverging to a stale BTB target.
    wire nonbranch_pred_takenE = validE & ~(branchE | jumpE) & pred_takenE;
    wire pred_wrongE = branch_mispredictE | jump_redirect_reqE | nonbranch_pred_takenE;
    wire branch_redirect_reqE = pred_wrongE & ~trap_flush & ~redirect_pendingR;
    assign redirectE = redirect_pendingR;
    assign bp_invalidateE = nonbranch_pred_takenE & ~memstallM & ~trap_flush & ~redirectE;
    assign redirect_targetE = actual_takenE ? actual_targetE : pcplus4E;

    always @(posedge clk) begin
        if (rst) begin
            redirect_pendingR <= 1'b0;
            redirect_targetR <= 32'b0;
        end else if (trap_flush & ~memstallM) begin
            redirect_pendingR <= 1'b0;
            redirect_targetR <= 32'b0;
        end else if (~memstallM) begin
            redirect_targetR <= redirect_targetE;
            if (redirect_pendingR) begin
                redirect_pendingR <= 1'b0;
            end else if (branch_redirect_reqE) begin
                redirect_pendingR <= 1'b1;
            end
        end
    end

    // ---- mret commit ----
    assign mret_take = mretE & trap_can_take;

    // ---- CSR read (combinational, EX stage) ----
    wire meip = (|irq) & meie;
    reg [31:0] csr_rdataE;
    always @(*) begin
        case (csr_addrE)
            12'h300: csr_rdataE = mstatus;
            12'h304: csr_rdataE = mie;
            12'h305: csr_rdataE = mtvec;
            12'h341: csr_rdataE = mepc;
            12'h342: csr_rdataE = mcause;
            12'h344: csr_rdataE = {20'b0, meip, 11'b0}; // mip: MEIP[11]
            default: csr_rdataE = 32'b0;
        endcase
    end

    // ---- CSR write data / new value (combinational, EX stage) ----
    wire [31:0] csr_wdataE = csr_immE ? {27'b0, zimmE} : srca_forwardE;
    wire [1:0]  csr_op_kind = csr_opE[1:0]; // 01=w, 10=s, 11=c
    wire [31:0] csr_newE = (csr_op_kind == 2'b01) ? csr_wdataE :
                          (csr_op_kind == 2'b10) ? (csr_rdataE | csr_wdataE) :
                          (csr_op_kind == 2'b11) ? (csr_rdataE & ~csr_wdataE) :
                          csr_rdataE;
    wire csr_we_eff = csr_weE & validE & ~memstallM;

    // ---- CSR register file writes (trap/mret have priority over CSR instr) ----
    always @(posedge clk) begin
        if (rst) begin
            mstatus <= 32'h00000000;
            mie     <= 32'h00000000;
            mtvec   <= 32'b0;
            mepc    <= 32'b0;
            mcause  <= 32'b0;
        end else if (trap_take) begin
            mepc       <= pcE;
            mcause     <= 32'h8000000b;      // machine external interrupt
            mstatus[7] <= mstatus[3];        // MPIE <= MIE
            mstatus[3] <= 1'b0;             // MIE  <= 0
        end else if (mret_take) begin
            mstatus[3] <= mstatus[7];        // MIE  <= MPIE
            mstatus[7] <= 1'b1;             // MPIE <= 1
        end else if (csr_we_eff) begin
            case (csr_addrE)
                12'h300: mstatus <= csr_newE & 32'h00000088; // MIE/MPIE only
                12'h304: mie     <= csr_newE & 32'h00000800; // MEIE only
                12'h305: mtvec   <= csr_newE;
                12'h341: mepc    <= csr_newE;
                12'h342: mcause  <= csr_newE;
                // mip (0x344) is read-only
                default: ;
            endcase
        end
    end

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
    wire[31:0] instrM;
    wire[2:0] load_funct3M;
    wire[2:0] store_funct3M;
    wire[31:0] csr_rdataM;
    wire[31:0] csr_rdataW;
    wire validM;
    wire exmem_bubbleE = divstallE | trap_take | redirectE;
    wire[31:0] forwardResultE = (wbselE == WB_PC4) ? pcplus4E :
                                (wbselE == WB_CSR) ? csr_rdataE : executeResultE;

    flopenr #(32) exmem_alu(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : executeResultE, aluResultM);
    flopenr #(32) exmem_forward(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : forwardResultE, resultM);
    flopenr #(32) exmem_pc(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : pcE, pcM);
    flopenr #(32) exmem_instr(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : instrE, instrM);
    flopenr #(32) exmem_store(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : srcb_forwardE, storeDataM);
    flopenr #(32) exmem_pc4(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : pcplus4E, pcplus4M);
    flopenr #(5)  exmem_rd(clk, rst, ~memstallM, exmem_bubbleE ? 5'b0 : rdE, rdM);
    flopenr #(3)  exmem_loadfunct(clk, rst, ~memstallM, exmem_bubbleE ? 3'b0 : load_funct3E, load_funct3M);
    flopenr #(3)  exmem_storefunct(clk, rst, ~memstallM, exmem_bubbleE ? 3'b0 : store_funct3E, store_funct3M);
    flopenr #(1)  exmem_regwrite(clk, rst, ~memstallM, exmem_bubbleE ? 1'b0 : (regwriteE & validE), regwriteM);
    flopenr #(1)  exmem_memread(clk, rst, ~memstallM, exmem_bubbleE ? 1'b0 : (memreadE & validE), memreadM);
    flopenr #(1)  exmem_memwrite(clk, rst, ~memstallM, exmem_bubbleE ? 1'b0 : (memwriteE & validE), memwriteM);
    flopenr #(1)  exmem_valid(clk, rst, ~memstallM, exmem_bubbleE ? 1'b0 : validE, validM);
    flopenr #(2)  exmem_wbsel(clk, rst, ~memstallM, exmem_bubbleE ? WB_ALU : wbselE, wbselM);
    flopenr #(32) exmem_csr(clk, rst, ~memstallM, exmem_bubbleE ? 32'b0 : csr_rdataE, csr_rdataM);

    assign d_validM = memreadM | memwriteM;
    assign memstallM = d_validM & ~d_readyM;
    assign aluoutM = aluResultM;

    store_align store_align(storeDataM, aluResultM[1:0], store_funct3M, writedataM, wstrbM);
    wire[31:0] loadDataM;
    load_ext load_extM(readdataM, aluResultM[1:0], load_funct3M, loadDataM);

    // MEM/WB
    wire validW;
    wire retire_validW;
    wire[31:0] instrW;
    flopenr #(32) memwb_pc(clk, rst, ~memstallM, pcM, pcW);
    flopenr #(32) memwb_instr(clk, rst, ~memstallM, instrM, instrW);
    flopenr #(32) memwb_alu(clk, rst, ~memstallM, aluResultM, aluoutW);
    flopenr #(32) memwb_load(clk, rst, ~memstallM, loadDataM, loadDataW);
    flopenr #(32) memwb_pc4(clk, rst, ~memstallM, pcplus4M, pcplus4W);
    flopenr #(5)  memwb_rd(clk, rst, ~memstallM, rdM, rdW);
    flopenr #(2)  memwb_wbsel(clk, rst, ~memstallM, wbselM, wbselW);
    flopenr #(1)  memwb_regwrite(clk, rst, ~memstallM, regwriteM, regwriteW);
    flopenr #(1)  memwb_valid(clk, rst, ~memstallM, validM, validW);
    flopenr #(1)  memwb_retire_valid(clk, rst, ~memstallM, (regwriteM | memreadM | memwriteM), retire_validW);
    flopenr #(32) memwb_csr(clk, rst, ~memstallM, csr_rdataM, csr_rdataW);

    assign resultW = (wbselW == WB_MEM) ? loadDataW :
                     (wbselW == WB_PC4) ? pcplus4W :
                     (wbselW == WB_CSR) ? csr_rdataW : aluoutW;

    wire lwstallD = memreadE &&
        (((rs1D == rdE) && uses_rs1D && (rs1D != 5'b0)) ||
         ((rs2D == rdE) && uses_rs2D && (rs2D != 5'b0)));
    assign stallD = lwstallD | divstallE;
    assign stallF = lwstallD | divstallE | ifetch_stall;
    assign flushD = (redirectE | trap_flush | fetch_redirectF) & ~memstallM;
    assign flushE = (lwstallD | redirectE | trap_flush) & ~memstallM;

    reg bp_updateR;
    reg bp_invalidateR;
    reg bp_takenR;
    reg[31:0] bp_pcR;
    reg[31:0] bp_targetR;

    always @(posedge clk) begin
        if (rst) begin
            bp_updateR <= 1'b0;
            bp_invalidateR <= 1'b0;
            bp_takenR <= 1'b0;
            bp_pcR <= 32'b0;
            bp_targetR <= 32'b0;
        end else begin
            bp_updateR <= 1'b0;
            bp_invalidateR <= 1'b0;
            if (~memstallM) begin
                bp_updateR <= validE & branchE & ~redirectE & ~trap_flush;
                bp_invalidateR <= bp_invalidateE;
                bp_takenR <= branch_takenE;
                bp_pcR <= pcE;
                bp_targetR <= branch_targetE;
            end
        end
    end

    branch_predictor bp(
        .clk(clk),
        .rst(rst),
        .pcF(pcF),
        .pred_takenF(pred_takenF),
        .pred_targetF(pred_targetF),
        .updateE(bp_updateR),
        .invalidateE(bp_invalidateR),
        .pcE(bp_pcR),
        .takenE(bp_takenR),
        .targetE(bp_targetR)
        );

    assign demo_pcF = pcF;
    assign demo_pcD = pcD;
    assign demo_pcE = pcE;
    assign demo_pcM = pcM;
    assign demo_pcW = pcW;
    assign demo_instrF = fetch_validF ? instrF : 32'b0;
    assign demo_instrD = instrD;
    assign demo_instrE = instrE;
    assign demo_instrM = instrM;
    assign demo_instrW = instrW;
    assign demo_validF = fetch_validF;
    assign demo_validD = validD;
    assign demo_validE = validE;
    assign demo_validM = validM;
    assign demo_validW = validW;
    assign demo_stallF = stallF;
    assign demo_stallD = stallD;

    assign perf_retireW = retire_validW & ~memstallM;
    assign perf_branchE = validE & branchE & ~memstallM;
    assign perf_mispredictE = branch_redirect_reqE & ~memstallM;
    assign perf_stall = stallD | memstallM;
    assign perf_stall_loaduse = lwstallD;
    assign perf_stall_muldiv = divstallE;
    assign perf_stall_dcache = memstallM;
    assign perf_stall_ifetch = ifetch_stall;
    assign perf_flush_branch = redirectE & ~memstallM;
    assign perf_flush_trap = trap_flush & ~memstallM;
endmodule
