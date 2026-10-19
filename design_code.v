`timescale 1ns/1ps

// ============================================================
// 32-bit ALU
// ============================================================
module alu (
    input  wire [31:0] A,
    input  wire [31:0] B,
    input  wire [3:0]  ALUControl,
    output reg  [31:0] ALUResult,
    output wire        Zero
);

    localparam ALU_ADD  = 4'b0000;
    localparam ALU_SUB  = 4'b0001;
    localparam ALU_AND  = 4'b0010;
    localparam ALU_OR   = 4'b0011;
    localparam ALU_SLL  = 4'b0100;
    localparam ALU_SLT  = 4'b0101;
    localparam ALU_SLTU = 4'b0110;
    localparam ALU_XOR  = 4'b0111;
    localparam ALU_SRL  = 4'b1000;
    localparam ALU_SRA  = 4'b1001;

    always @(*) begin
        case (ALUControl)
            ALU_ADD:  ALUResult = A + B;
            ALU_SUB:  ALUResult = A - B;
            ALU_AND:  ALUResult = A & B;
            ALU_OR:   ALUResult = A | B;
            ALU_SLL:  ALUResult = A << B[4:0];
            ALU_SLT:  ALUResult = ($signed(A) < $signed(B)) ? 32'd1 : 32'd0;
            ALU_SLTU: ALUResult = (A < B) ? 32'd1 : 32'd0;
            ALU_XOR:  ALUResult = A ^ B;
            ALU_SRL:  ALUResult = A >> B[4:0];
            ALU_SRA:  ALUResult = $signed(A) >>> B[4:0];
            default:  ALUResult = 32'd0;
        endcase
    end

    assign Zero = (ALUResult == 32'd0);

endmodule


// ============================================================
// Register File: 32 registers x 32 bits
// x0 is always zero
// ============================================================
module register_file (
    input  wire        clk,
    input  wire        reset,
    input  wire        WE3,
    input  wire [4:0]  A1,
    input  wire [4:0]  A2,
    input  wire [4:0]  A3,
    input  wire [31:0] WD3,
    output wire [31:0] RD1,
    output wire [31:0] RD2
);

    reg [31:0] reg_file [0:31];
    integer i;

    initial begin
        for (i = 0; i < 32; i = i + 1)
            reg_file[i] = 32'd0;
    end

    always @(posedge clk or posedge reset) begin
        if (reset) begin
            for (i = 0; i < 32; i = i + 1)
                reg_file[i] <= 32'd0;
        end
        else if (WE3 && (A3 != 5'd0)) begin
            reg_file[A3] <= WD3;
        end
    end

    assign RD1 = (A1 == 5'd0) ? 32'd0 : reg_file[A1];
    assign RD2 = (A2 == 5'd0) ? 32'd0 : reg_file[A2];

endmodule


// ============================================================
// Immediate Generator
// Supports I, S, B, U and J immediate formats
// ============================================================
module extend_unit (
    input  wire [31:0] Instr,
    output reg  [31:0] ImmExt
);

    always @(*) begin
        case (Instr[6:0])

            // I-type: ADDI, loads, JALR, immediate ALU operations
            7'b0010011,
            7'b0000011,
            7'b1100111:
                ImmExt = {{20{Instr[31]}}, Instr[31:20]};

            // S-type: stores
            7'b0100011:
                ImmExt = {{20{Instr[31]}},
                          Instr[31:25], Instr[11:7]};

            // B-type: conditional branches
            7'b1100011:
                ImmExt = {{19{Instr[31]}},
                          Instr[31], Instr[7],
                          Instr[30:25], Instr[11:8], 1'b0};

            // U-type: LUI and AUIPC
            7'b0110111,
            7'b0010111:
                ImmExt = {Instr[31:12], 12'b0};

            // J-type: JAL
            7'b1101111:
                ImmExt = {{11{Instr[31]}},
                          Instr[31], Instr[19:12],
                          Instr[20], Instr[30:21], 1'b0};

            default:
                ImmExt = 32'd0;

        endcase
    end

endmodule


// ============================================================
// Datapath and Instruction Control
// ============================================================
module datapath (
    input  wire        clk,
    input  wire        reset,

    input  wire [31:0] Instr,
    input  wire [31:0] ReadData,

    output reg  [31:0] PC,
    output wire        MemWrite,
    output wire [31:0] Mem_WrAddr,
    output wire [31:0] Mem_WrData,
    output wire [31:0] Result
);

    // Instruction fields
    wire [6:0] opcode = Instr[6:0];
    wire [4:0] rd     = Instr[11:7];
    wire [2:0] funct3 = Instr[14:12];
    wire [4:0] rs1    = Instr[19:15];
    wire [4:0] rs2    = Instr[24:20];
    wire [6:0] funct7 = Instr[31:25];

    // Opcodes
    localparam OP_LOAD   = 7'b0000011;
    localparam OP_IMM    = 7'b0010011;
    localparam OP_AUIPC  = 7'b0010111;
    localparam OP_STORE  = 7'b0100011;
    localparam OP_REG    = 7'b0110011;
    localparam OP_LUI    = 7'b0110111;
    localparam OP_BRANCH = 7'b1100011;
    localparam OP_JALR   = 7'b1100111;
    localparam OP_JAL    = 7'b1101111;

    // Register file signals
    wire [31:0] RD1;
    wire [31:0] RD2;
    reg  [31:0] WriteData;
    reg         RegWrite;

    register_file RegFile (
        .clk(clk),
        .reset(reset),
        .WE3(RegWrite),
        .A1(rs1),
        .A2(rs2),
        .A3(rd),
        .WD3(WriteData),
        .RD1(RD1),
        .RD2(RD2)
    );

    // Immediate generator
    wire [31:0] ImmExt;

    extend_unit EXT (
        .Instr(Instr),
        .ImmExt(ImmExt)
    );

    // ALU
    reg  [31:0] SrcB;
    reg  [3:0]  ALUControl;
    wire [31:0] ALUResult;
    wire        Zero;

    alu ALU (
        .A(RD1),
        .B(SrcB),
        .ALUControl(ALUControl),
        .ALUResult(ALUResult),
        .Zero(Zero)
    );

    // Branch decision
    reg BranchTaken;

    always @(*) begin
        BranchTaken = 1'b0;

        if (opcode == OP_BRANCH) begin
            case (funct3)
                3'b000: BranchTaken = (RD1 == RD2);                    // BEQ
                3'b001: BranchTaken = (RD1 != RD2);                    // BNE
                3'b100: BranchTaken = ($signed(RD1) < $signed(RD2));   // BLT
                3'b101: BranchTaken = ($signed(RD1) >= $signed(RD2));  // BGE
                3'b110: BranchTaken = (RD1 < RD2);                     // BLTU
                3'b111: BranchTaken = (RD1 >= RD2);                    // BGEU
                default: BranchTaken = 1'b0;
            endcase
        end
    end

    // ALU source selection
    always @(*) begin
        SrcB = RD2;

        case (opcode)
            OP_LOAD,
            OP_STORE,
            OP_IMM,
            OP_JALR:
                SrcB = ImmExt;

            default:
                SrcB = RD2;
        endcase
    end

    // ALU operation selection
    always @(*) begin
        ALUControl = 4'b0000;

        case (opcode)

            OP_REG,
            OP_IMM: begin
                case (funct3)

                    3'b000: begin
                        if ((opcode == OP_REG) &&
                            (funct7 == 7'b0100000))
                            ALUControl = 4'b0001; // SUB
                        else
                            ALUControl = 4'b0000; // ADD/ADDI
                    end

                    3'b001: ALUControl = 4'b0100; // SLL
                    3'b010: ALUControl = 4'b0101; // SLT
                    3'b011: ALUControl = 4'b0110; // SLTU
                    3'b100: ALUControl = 4'b0111; // XOR

                    3'b101: begin
                        if (funct7 == 7'b0100000)
                            ALUControl = 4'b1001; // SRA
                        else
                            ALUControl = 4'b1000; // SRL
                    end

                    3'b110: ALUControl = 4'b0011; // OR
                    3'b111: ALUControl = 4'b0010; // AND

                    default: ALUControl = 4'b0000;
                endcase
            end

            OP_BRANCH:
                ALUControl = 4'b0001; // SUB

            default:
                ALUControl = 4'b0000; // ADD
        endcase
    end

    // Memory interface
    assign MemWrite   = (opcode == OP_STORE);
    assign Mem_WrAddr = ALUResult;
    assign Mem_WrData = RD2;

    // Write-back selection
    always @(*) begin
        RegWrite  = 1'b0;
        WriteData = 32'd0;

        case (opcode)

            OP_REG,
            OP_IMM: begin
                RegWrite  = 1'b1;
                WriteData = ALUResult;
            end

            OP_LOAD: begin
                RegWrite  = 1'b1;
                WriteData = ReadData;
            end

            OP_LUI: begin
                RegWrite  = 1'b1;
                WriteData = ImmExt;
            end

            OP_AUIPC: begin
                RegWrite  = 1'b1;
                WriteData = PC + ImmExt;
            end

            OP_JAL,
            OP_JALR: begin
                RegWrite  = 1'b1;
                WriteData = PC + 32'd4;
            end

            default: begin
                RegWrite  = 1'b0;
                WriteData = 32'd0;
            end

        endcase
    end

    // Next-PC selection
    reg [31:0] PCNext;

    always @(*) begin
        PCNext = PC + 32'd4;

        if ((opcode == OP_BRANCH) && BranchTaken)
            PCNext = PC + ImmExt;

        if (opcode == OP_JAL)
            PCNext = PC + ImmExt;

        if (opcode == OP_JALR)
            PCNext = (ALUResult + 32'd0) & 32'hFFFFFFFE;
    end

    // Program counter
    always @(posedge clk or posedge reset) begin
        if (reset)
            PC <= 32'd0;
        else
            PC <= PCNext;
    end

    // Debug/write-back result
    assign Result = WriteData;

endmodule


// ============================================================
// Top-Level RISC-V CPU
// Instruction input is supplied by ROM/testbench.
// ============================================================
module riscv_cpu (
    input  wire        clk,
    input  wire        reset,

    output wire [31:0] PC,
    input  wire [31:0] Instr,

    output wire        MemWrite,
    output wire [31:0] Mem_WrAddr,
    output wire [31:0] Mem_WrData,

    input  wire [31:0] ReadData,
    output wire [31:0] Result
);

    datapath DATA_PATH (
        .clk(clk),
        .reset(reset),
        .Instr(Instr),
        .ReadData(ReadData),
        .PC(PC),
        .MemWrite(MemWrite),
        .Mem_WrAddr(Mem_WrAddr),
        .Mem_WrData(Mem_WrData),
        .Result(Result)
    );

endmodule


// ============================================================
// 64-word data memory
// Supports word-aligned LW and SW.
// ============================================================
module data_mem (
    input  wire        clk,
    input  wire        WE,
    input  wire [31:0] wr_addr,
    input  wire [31:0] wr_data,
    output wire [31:0] rd_data
);

    reg [31:0] data_ram [0:63];
    integer i;

    initial begin
        for (i = 0; i < 64; i = i + 1)
            data_ram[i] = 32'd0;
    end

    always @(posedge clk) begin
        if (WE && (wr_addr[1:0] == 2'b00))
            data_ram[wr_addr[7:2]] <= wr_data;
    end

    assign rd_data = data_ram[wr_addr[7:2]];

endmodule
