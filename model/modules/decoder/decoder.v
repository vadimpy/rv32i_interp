// decoder.v

`include "decode_defs.v"
`include "alu_codes.v"
`include "exec_insn_types.v"

module decoder(
    input wire         clk,
    input wire  [31:0] insn,
    input wire  [31:0] pc,
    input wire         ex_stall,
    output reg  [4:0]  rs1,
    output reg  [4:0]  rs2,
    output reg  [4:0]  rd,
    output reg  [3:0]  alu_code, // ensure width
    output reg  [31:0] pc_de,
    output reg  [31:0] imm,
    output reg         ex_use_imm,
    output reg  [4:0]  rs1_reg,
    output reg  [4:0]  rs2_reg,
    output reg  [3:0]  insn_type,
    output reg  [3:0]  insn_sub_type,
    output wire        ex_stall_to_fetch
);

reg ecall_ebreak_encountered;

initial ecall_ebreak_encountered = 0;

wire [6:0] opcode;
wire [2:0] funct3;
wire [6:0] funct7;
wire [31:0] u_imm;
wire [31:0] i_imm;
wire [31:0] j_imm;
wire [31:0] b_imm;
wire [31:0] s_imm;
wire [31:0] shamt;
wire [4:0] rs1_wire;
wire [4:0] rs2_wire;

assign rs1_wire = insn[19:15];
assign rs2_wire = insn[24:20];

assign ex_stall_to_fetch = ex_stall;// | (opcode === `LOAD_OPCODE);

wire [4:0] w_rd;

assign opcode = insn[6:0];
assign funct3 = insn[14:12];
assign funct7 = insn[31:25];
assign w_rd = insn[11:7];

wire [24:0] ecall_ebreak_field; 
assign ecall_ebreak_field = insn[31:7];

assign u_imm = { insn[31:12], 12'b0 };
assign i_imm = { {21{insn[31]}}, insn[30:20] };
assign s_imm = { {21{insn[31]}}, insn[30:25], insn[11:8], insn[7]};
assign b_imm = { {20{insn[31]}}, insn[7], insn[30:25], insn[11:8], 1'b0 };
assign j_imm = { {12{insn[31]}}, insn[19:12], insn[20], insn[30:25], insn[24:21], 1'b0 };
assign shamt = { 27'b0, insn[24:20] };

always @(posedge clk) begin
    if (ecall_ebreak_encountered) begin
        ex_use_imm <= 0;
        insn_type <= `AR_TYPE;
        insn_sub_type <= `AR_GENERAL;
        rs1_reg <= 0;
        rs2_reg <= 0;
        rd <= 0;
    end
    if (~ex_stall) begin
        pc_de <= pc;
        rs1_reg <= rs1_wire;
        rs2_reg <= rs2_wire;
        rs1 <= rs1_wire;
        rs2 <= rs2_wire;
    end
end

always @(posedge clk) begin
    if (~ecall_ebreak_encountered)
    if (~ex_stall) begin
        case (opcode)

            `LUI_OPCODE: begin
                $display("%h lui %d %h", pc, w_rd, u_imm);
                imm <= u_imm;
                ex_use_imm <= 1;
                insn_type <= `AR_TYPE;
                insn_sub_type <= `AR_LUI;
                rd <= w_rd;
            end

            // -------------------- //

            `AUIPC_OPCODE: begin
                $display("%h auipc %d %h + %h", pc, w_rd, u_imm, pc);
                imm <= u_imm;
                ex_use_imm <= 1;
                insn_type <= `AR_TYPE;
                insn_sub_type <= `AR_AUIPC;
                alu_code <= `ADD;
                rd <= w_rd;
            end

            // -------------------- //

            `JAL_OPCODE: begin
                $display("%h jal %d, %h", pc, w_rd, j_imm);
                imm <= j_imm;
                ex_use_imm <= 0;
                insn_type <= `DB_TYPE;
                insn_sub_type <= `DB_JAL;
                alu_code <= `NONE;
                rd <= w_rd;
            end

            // -------------------- //

            `JALR_OPCODE: begin
                imm <= i_imm;
                ex_use_imm <= 0;
                insn_type <= `IB_TYPE;
                insn_sub_type <= `IB_JALR;
                alu_code <= `ADD;
                $display("%h jalr %d %h(%d)", pc, w_rd, i_imm, rs1_wire);
                rd <= w_rd;
            end

            // -------------------- //

            `DIR_BRANCH_OPCODE: begin
                insn_type <= `DB_TYPE;
                rd <= 0;
                imm <= b_imm;
                ex_use_imm <= 0;
                case (funct3)
                    `BEQ_FUNCT3: begin
                        insn_sub_type <= `DB_BEQ;
                        alu_code <= `CMP;
                        $display("%h beq %d %d %d (0x%h)", pc, rs1_wire, rs2_wire, $signed(b_imm), b_imm);
                    end
                    `BNE_FUNCT3: begin
                        insn_sub_type <= `DB_BNE;
                        alu_code <= `CMP;
                        $display("%h bne %d %d %d (0x%h)", pc, rs1_wire, rs2_wire, $signed(b_imm), b_imm);
                    end
                    `BLT_FUNCT3: begin
                        insn_sub_type <= `DB_BLT;
                        alu_code <= `CMP;
                        $display("%h blt %d %d %d (0x%h)", pc, rs1_wire, rs2_wire, $signed(b_imm), b_imm);
                    end
                    `BGE_FUNCT3: begin
                        alu_code <= `CMP;
                        insn_sub_type <= `DB_BGE;
                        $display("%h bge %d %d %d (0x%h)", pc, rs1_wire, rs2_wire, $signed(b_imm), b_imm);
                    end
                    `BLTU_FUNCT3: begin
                        alu_code <= `CMPU;
                        insn_sub_type <= `DB_BLT;
                        $display("%h bltu %d %d %d (0x%h)", pc, rs1_wire, rs2_wire, $signed(b_imm), b_imm);
                    end
                    `BGEU_FUNCT3: begin
                        alu_code <= `CMPU;
                        insn_sub_type <= `DB_BGE;
                        $display("%h bgeu %d %d %d (0x%h)", pc, rs1_wire, rs2_wire, $signed(b_imm), b_imm);
                    end
                    default: begin
                        $display("Unreachable!");
                        $finish(1);
                    end
                endcase
            end

            // -------------------- //

            `LOAD_OPCODE: begin
                insn_type <= `L_TYPE;
                rd <= w_rd;
                alu_code <= `ADD;
                imm <= i_imm;
                ex_use_imm <= 1;
                case (funct3)
                    `LB_FUNCT3: begin
                        $display("%h lb %d %d(%d)", pc, w_rd, $signed(i_imm), rs1_wire);
                        insn_sub_type <= `L_B;
                    end
                    `LH_FUNCT3: begin
                        $display("%h lh %d %d(%d)", pc, w_rd, $signed(i_imm), rs1_wire);
                        insn_sub_type <= `L_H;
                    end
                    `LW_FUNCT3: begin
                        $display("%h lw %d %d(%d)", pc, w_rd, $signed(i_imm), rs1_wire);
                        insn_sub_type <= `L_W;
                    end
                    `LBU_FUNCT3: begin
                        $display("%h lbu %d %d(%d)", pc, w_rd, $signed(i_imm), rs1_wire);
                        insn_sub_type <= `L_BU;
                    end
                    `LHU_FUNCT3: begin
                        $display("%h lhu %d %d(%d)", pc, w_rd, $signed(i_imm), rs1_wire);
                        insn_sub_type <= `L_HU;
                    end
                    default: begin
                        $display("Unreachable!");
                        $finish(1);
                    end
                endcase
            end

            // -------------------- //

            `STORE_OPCODE: begin
                insn_type <= `S_TYPE;
                rd <= 0;
                imm <= s_imm;
                ex_use_imm <= 1;
                alu_code <= `ADD;
                case (funct3)
                    `SB_FUNCT3: begin
                        $display("%h sb %d %d(%d)", pc, rs2_wire, $signed(s_imm), rs1_wire);
                        insn_sub_type <= `S_B;
                    end
                    `SH_FUNCT3: begin
                        $display("%h sh %d %d(%d)", pc, rs2_wire, $signed(s_imm), rs1_wire);
                        insn_sub_type <= `S_H;
                    end
                    `SW_FUNCT3: begin
                        $display("%h sw %d %d(%d)", pc, rs2_wire, $signed(s_imm), rs1_wire);
                        insn_sub_type <= `S_W;
                    end
                    default: begin
                        $display("Unreachable!");
                        $finish(1);
                    end
                endcase
            end

            // -------------------- //

            `IMM_ARITHM: begin
                ex_use_imm <= 1;
                insn_type <= `AR_TYPE;
                rd <= w_rd;
                case (funct3)
                    `ADDI_FUNCT3: begin
                        $display("%h addi %d %d %h", pc, w_rd, rs1_wire, i_imm);
                        alu_code <= `ADD;
                        imm <= i_imm;
                        insn_sub_type <= `AR_GENERAL;
                    end
                    `SLTI_FUNCT3: begin
                        $display("%h slti %d %d %h", pc, w_rd, rs1_wire, i_imm);
                        alu_code <= `CMP;
                        imm <= i_imm;
                        insn_sub_type <= `AR_SLT;
                    end
                    `SLTIU_FUNCT3: begin
                        $display("%h sltiu %d %d %h", pc, w_rd, rs1_wire, i_imm);
                        alu_code <= `CMPU;
                        imm <= i_imm;
                        insn_sub_type <= `AR_SLT;
                    end
                    `XORI_FUNCT3: begin
                        $display("%h xori %d %d %h", pc, w_rd, rs1_wire, i_imm);
                        alu_code <= `XOR;
                        imm <= i_imm;
                        insn_sub_type <= `AR_GENERAL;
                    end
                    `ORI_FUNCT3: begin
                        $display("%h ori %d %d %h", pc, w_rd, rs1_wire, i_imm);
                        alu_code <= `OR;
                        imm <= i_imm;
                        insn_sub_type <= `AR_GENERAL;
                    end
                    `ANDI_FUNCT3: begin
                        $display("%h andi %d %d %h", pc, w_rd, rs1_wire, i_imm);
                        alu_code <= `AND;
                        insn_sub_type <= `AR_GENERAL;
                        imm <= i_imm;
                    end
                    `SLLI_FUNCT3: begin
                        if (funct7 == `SLLI_FUNCT7) begin
                            $display("%h slli %d %d %h", pc, w_rd, rs1_wire, i_imm);
                            alu_code <= `LS;
                            insn_sub_type <= `AR_GENERAL;
                            imm <= shamt;
                        end
                    end
                    `SRI_FUNCT3: begin
                        imm <= shamt;
                        case (funct7)
                            `SRLI_FUNCT7: begin
                                $display("%h srli", pc, w_rd, rs1_wire, shamt);
                                alu_code <= `RSL;
                                insn_sub_type <= `AR_GENERAL;
                            end
                            `SRAI_FUNCT7: begin
                                $display("%h srai", pc, w_rd, rs1_wire, shamt);
                                alu_code <= `RSA;
                                insn_sub_type <= `AR_GENERAL;
                            end
                            default: begin
                                $display("Unreachable!");
                                $finish(1);
                            end
                        endcase
                    end
                    default: begin
                        $display("Unreachable!");
                        $finish(1);
                    end
                endcase
            end

            // -------------------- //

            `REG_ARITHM_OPCODE: begin
                ex_use_imm <= 0;
                insn_type <= `AR_TYPE;
                rd <= w_rd;
                case (funct3)
                    `ADD_SUB_FUNCT3: begin
                        insn_sub_type <= `AR_GENERAL;
                        case (funct7)
                            `ADD_FUNCT7: begin
                                $display("%h add %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                                alu_code <= `ADD;
                            end
                            `SUB_FUNCT7: begin
                                $display("%h sub %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                                alu_code <= `SUB;
                            end
                            default: begin
                                $display("Unreachable!");
                                $finish(1);
                            end
                        endcase
                    end
                    `SLL_FUNCT3: begin
                        if (funct7 == `SLL_FUNCT7) begin
                            $display("%h sll %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                            alu_code <= `LS;
                            insn_sub_type <= `AR_GENERAL;
                        end
                    end
                    `SLT_FUNCT3: begin
                        if (funct7 == `SLT_FUNCT7) begin
                            $display("%h slt %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                            alu_code <= `CMP;
                            insn_sub_type <= `AR_SLT;
                        end
                    end
                    `SLTU_FUNCT3: begin
                        if (funct7 == `SLTU_FUNCT7) begin
                            $display("%h sltu %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                            alu_code <= `CMPU;
                            insn_sub_type <= `AR_SLT;
                        end
                    end
                    `XOR_FUNCT3: begin
                        if (funct7 == `XOR_FUNCT7) begin
                            $display("%h xor %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                            alu_code <= `XOR;
                            insn_sub_type <= `AR_GENERAL;
                        end
                    end
                    `SRR_FUNCT3: begin
                        case (funct7)
                            `SRL_FUNCT7: begin
                                $display("%h srl %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                                alu_code <= `RSL;
                                insn_sub_type <= `AR_GENERAL;
                            end
                            `SRA_FUNCT7: begin
                                $display("%h sra %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                                alu_code <= `RSA;
                                insn_sub_type <= `AR_GENERAL;
                            end
                            default: begin
                                $display("Unreachable!");
                                $finish(1);
                            end
                        endcase
                    end
                    `OR_FUNCT3: begin
                        if (funct7 == `OR_FUNCT7) begin
                            $display("%h or %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                            alu_code <= `OR;
                            insn_sub_type <= `AR_GENERAL;
                        end
                    end
                    `AND_FUNCT3: begin
                        if (funct7 == `AND_FUNCT7) begin
                            $display("%h and %d %d %d", pc, w_rd, rs1_wire, rs2_wire);
                            alu_code <= `AND;
                            insn_sub_type <= `AR_GENERAL;
                        end
                    end
                    default: begin
                        $display("Unreachable!");
                        $finish(1);
                    end
                endcase
            end

            // -------------------- //

            `FENCE_OPCODE: begin
                case (funct3)
                    `FENCE_FUNCT3: begin
                        $display("%h fence", pc);
                    end
                    `FENCE_I_FUNCT3: begin
                        $display("%h fence.i", pc);
                    end
                    default: begin
                        $display("Unreachable!");
                        $finish(1);
                    end
                endcase
            end

            // -------------------- //

            `SYSTEM_OPCODE: begin
                case (ecall_ebreak_field)
                    `ECALL: begin
                        ecall_ebreak_encountered <= 1;
                        $display("%h ecall", pc);
                        ex_use_imm <= 0;
                        insn_type <= `AR_TYPE;
                        insn_sub_type <= `AR_GENERAL;
                        rs1_reg <= 0;
                        rs2_reg <= 0;
                        rd <= 0;
                    end
                    `EBREAK: begin
                        ecall_ebreak_encountered <= 1;
                        $display("%h ebreak", pc);
                        ex_use_imm <= 0;
                        insn_type <= `AR_TYPE;
                        insn_sub_type <= `AR_GENERAL;
                        rs1_reg <= 0;
                        rs2_reg <= 0;
                        rd <= 0;
                    end
                    default: begin
                        case (funct3)
                            `CSRRW_FUNCT3: begin
                                $display("%h csrrw", pc);
                            end
                            `CSRRS_FUNCT3: begin
                                $display("%h csrrs", pc);
                            end
                            `CSRRC_FUNCT3: begin
                                $display("%h csrrc", pc);
                            end
                            `CSRRWI_FUNCT3: begin
                                $display("%h csrrwi", pc);
                            end
                            `CSRRSI_FUNCT3: begin
                                $display("%h csrrsi", pc);
                            end
                            `CSRRCI_FUNCT3: begin
                                $display("%h csrrci", pc);
                            end
                            default: begin
                                $display("Unreachable!");
                                $finish(1);
                            end
                        endcase
                    end
                endcase
            end
            default: begin
                $display("Incorrect insn");
            end
        endcase
    end
end

endmodule
