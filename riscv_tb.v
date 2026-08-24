module riscv_tb;

    reg clk;
    reg rst_n;
    
    // RF Signals
    reg         rf_we;
    reg  [4:0]  rs1, rs2, rd;
    reg  [31:0] rf_wdata;
    wire [31:0] rf_rdata1, rf_rdata2;

    // LSU Signals
    reg         mem_req, mem_we, l_unsigned;
    reg  [1:0]  size;
    reg  [31:0] addr, lsu_wdata;
    wire [31:0] lsu_rdata;
    wire        addr_fault, stall;

    // Simulated Main Memory Signals
    wire [31:0] mem_addr, mem_wdata_out;
    wire [3:0]  mem_byte_en;
    reg  [31:0] mem_rdata;
    reg         mem_ready;
    
    integer p, f;

    // Instantiate Register File
    riscv_regfile u_rf (
        .clk(clk),
        .rst_n(rst_n),
        .we(rf_we),
        .rs1(rs1),
        .rs2(rs2),
        .rd(rd),
        .wdata(rf_wdata),
        .rdata1(rf_rdata1),
        .rdata2(rf_rdata2)
    );

    // Instantiate LSU
    riscv_lsu u_lsu (
        .clk(clk),
        .rst_n(rst_n),
        .mem_req(mem_req),
        .mem_we(mem_we),
        .size(size),
        .l_unsigned(l_unsigned),
        .addr(addr),
        .wdata(lsu_wdata),
        .rdata(lsu_rdata),
        .addr_fault(addr_fault),
        .stall(stall),
        .mem_addr(mem_addr),
        .mem_wdata(mem_wdata_out),
        .mem_byte_en(mem_byte_en),
        .mem_rdata(mem_rdata),
        .mem_ready(mem_ready)
    );

    initial clk = 0;
    always #5 clk = ~clk;

    initial begin
        p = 0; f = 0;
        rst_n = 0;
        
        // Init RF
        rf_we = 0; rs1 = 0; rs2 = 0; rd = 0; rf_wdata = 0;
        
        // Init LSU
        mem_req = 0; mem_we = 0; size = 0; l_unsigned = 0; addr = 0; lsu_wdata = 0;
        mem_ready = 1; mem_rdata = 32'hDEADBEEF;

        #15 rst_n = 1;
        
        // =========================================================
        // TC1: Register File - Hardwired Zero Test
        // =========================================================
        @(negedge clk);
        rf_we = 1; rd = 5'd0; rf_wdata = 32'hFFFFFFFF; // Try writing to x0
        @(negedge clk);
        rf_we = 0; rs1 = 5'd0;
        #1;
        if (rf_rdata1 == 32'd0) begin p=p+1; $display("PASS: RF x0 is hardwired to 0"); end
        else begin f=f+1; $display("FAIL: RF x0 was overwritten!"); end

        // =========================================================
        // TC2: LSU - Unaligned Word Fault
        // =========================================================
        @(negedge clk);
        mem_req = 1; mem_we = 0; size = 2'b10; addr = 32'h0000_1001; // Not divisible by 4
        #1;
        if (addr_fault) begin p=p+1; $display("PASS: LSU caught unaligned word access"); end
        else begin f=f+1; $display("FAIL: LSU missed unaligned word access"); end

        // =========================================================
        // TC3: LSU - Sign-Extended Byte Load
        // =========================================================
        @(negedge clk);
        mem_req = 1; mem_we = 0; size = 2'b00; addr = 32'h0000_1002; l_unsigned = 0;
        mem_rdata = 32'h00A50000; // Byte at offset 2 is 0xA5 (negative in 8-bit)
        #1;
        if (lsu_rdata == 32'hFFFFFFA5) begin p=p+1; $display("PASS: LSU sign-extended byte correctly"); end
        else begin f=f+1; $display("FAIL: LSU sign-extension failed (Got %h)", lsu_rdata); end

        // =========================================================
        // TC4: LSU - Halfword Store Alignment
        // =========================================================
        @(negedge clk);
        mem_req = 1; mem_we = 1; size = 2'b01; addr = 32'h0000_1002; lsu_wdata = 32'h0000_BEEF;
        #1;
        if (mem_byte_en == 4'b1100 && mem_wdata_out == 32'hBEEF_0000) begin 
            p=p+1; $display("PASS: LSU aligned halfword store correctly"); 
        end else begin 
            f=f+1; $display("FAIL: LSU halfword store failed"); 
        end
        mem_req = 0;

        $display("=== %0d passed %0d failed ===", p, f);
        #20 $finish;
    end

    // Waveforms
    initial begin
        $dumpfile("riscv_waves.vcd");
        $dumpvars(0, riscv_tb);
    end

endmodule