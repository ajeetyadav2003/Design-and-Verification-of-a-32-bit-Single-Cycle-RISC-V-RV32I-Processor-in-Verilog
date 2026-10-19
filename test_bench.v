`timescale 1ns/1ps

module tb_riscv;

    reg clk;
    reg reset;

    wire [31:0] PC;
    wire [31:0] Instr;
    wire MemWrite;
    wire [31:0] Mem_WrAddr;
    wire [31:0] Mem_WrData;
    wire [31:0] ReadData;
    wire [31:0] Result;

    reg [31:0] rom [0:31];
    integer i;
    integer errors;

    riscv_cpu cpu (
        .clk(clk),
        .reset(reset),
        .PC(PC),
        .Instr(Instr),
        .MemWrite(MemWrite),
        .Mem_WrAddr(Mem_WrAddr),
        .Mem_WrData(Mem_WrData),
        .ReadData(ReadData),
        .Result(Result)
    );

    // PC is a byte address; each instruction occupies 4 bytes.
    assign Instr = rom[PC[6:2]];

    // Port names must match the data_mem module in design.sv.
    data_mem dmem (
        .clk(clk),
        .WE(MemWrite),
        .wr_addr(Mem_WrAddr),
        .wr_data(Mem_WrData),
        .rd_data(ReadData)
    );

    always #5 clk = ~clk;

    task check_reg;
        input integer reg_num;
        input [31:0] expected;
        begin
            if (cpu.DATA_PATH.RegFile.reg_file[reg_num] !== expected) begin
                $display("FAIL: x%0d expected=0x%08h actual=0x%08h",
                         reg_num, expected,
                         cpu.DATA_PATH.RegFile.reg_file[reg_num]);
                errors = errors + 1;
            end
            else begin
                $display("PASS: x%0d = 0x%08h", reg_num, expected);
            end
        end
    endtask

    task check_mem;
        input integer word_index;
        input [31:0] expected;
        begin
            if (dmem.data_ram[word_index] !== expected) begin
                $display("FAIL: memory word %0d expected=0x%08h actual=0x%08h",
                         word_index, expected, dmem.data_ram[word_index]);
                errors = errors + 1;
            end
            else begin
                $display("PASS: memory word %0d = 0x%08h",
                         word_index, expected);
            end
        end
    endtask

    initial begin
        clk = 1'b0;
        reset = 1'b1;
        errors = 0;

        for (i = 0; i < 32; i = i + 1)
            rom[i] = 32'h00000013; // NOP

        // Arithmetic and logical instructions
        rom[0]  = 32'h00500093; // ADDI x1, x0, 5
        rom[1]  = 32'h00A00113; // ADDI x2, x0, 10
        rom[2]  = 32'h002081B3; // ADD  x3, x1, x2 = 15
        rom[3]  = 32'h40110233; // SUB  x4, x2, x1 = 5
        rom[4]  = 32'h0020F2B3; // AND  x5, x1, x2 = 0
        rom[5]  = 32'h0020E333; // OR   x6, x1, x2 = 15
        rom[6]  = 32'h0020C3B3; // XOR  x7, x1, x2 = 15
        rom[7]  = 32'h0020A433; // SLT  x8, x1, x2 = 1

        // Store and load
        rom[8]  = 32'h00302023; // SW x3, 0(x0)
        rom[9]  = 32'h00002483; // LW x9, 0(x0) = 15

        // Branch test: skip rom[12]
        rom[10] = 32'h00100513; // ADDI x10, x0, 1
        rom[11] = 32'h00A50463; // BEQ x10, x10, +8
        rom[12] = 32'h06300593; // ADDI x11, x0, 99 (must skip)
        rom[13] = 32'h00700593; // ADDI x11, x0, 7

        // JAL test: link = PC + 4 = 60; skip rom[15]
        rom[14] = 32'h0080066F; // JAL x12, +8
        rom[15] = 32'h05800693; // ADDI x13, x0, 88 (must skip)
        rom[16] = 32'h00900693; // ADDI x13, x0, 9

        $dumpfile("riscv_test.vcd");
        $dumpvars(0, tb_riscv);

        repeat (2) @(negedge clk);
        reset = 1'b0;

        $display("");
        $display("========================================");
        $display("Starting RISC-V Processor Tests");
        $display("========================================");

        repeat (21) begin
            @(posedge clk);
            #1;
            $display("PC=%08h Instr=%08h Result=%08h MemWrite=%b",
                     PC, Instr, Result, MemWrite);
        end

        #1;
        $display("");
        $display("========== REGISTER TESTS ==========");

        check_reg(0,  32'd0);
        check_reg(1,  32'd5);
        check_reg(2,  32'd10);
        check_reg(3,  32'd15);
        check_reg(4,  32'd5);
        check_reg(5,  32'd0);
        check_reg(6,  32'd15);
        check_reg(7,  32'd15);
        check_reg(8,  32'd1);
        check_reg(9,  32'd15);
        check_reg(10, 32'd1);
        check_reg(11, 32'd7);
        check_reg(12, 32'd60);
        check_reg(13, 32'd9);

        $display("");
        $display("========== MEMORY TESTS ==========");
        check_mem(0, 32'd15);

        $display("");
        $display("========================================");
        if (errors == 0)
            $display("ALL TESTS PASSED");
        else
            $display("TESTS FAILED: %0d error(s)", errors);
        $display("========================================");

        $finish;
    end

endmodule
