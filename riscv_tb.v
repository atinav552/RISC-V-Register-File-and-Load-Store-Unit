`timescale 1ns/1ps

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
        // TC1: Register File - Hardwired Zero (x0) Test
        // =========================================================
        @(negedge clk);
        rf_we = 1; rd = 5'd0; rf_wdata = 32'hFFFF_FFFF;
        @(negedge clk);
        rf_we = 0; rs1 = 5'd0;
        #1;
        if (rf_rdata1 === 32'd0) begin p=p+1; $display("PASS [TC1]: RF x0 is hardwired to 0"); end
        else begin f=f+1; $display("FAIL [TC1]: RF x0 was overwritten!"); end

        // =========================================================
        // TC2: Register File - Standard Write & Dual-Port Read
        // =========================================================
        @(negedge clk);
        rf_we = 1; rd = 5'd5; rf_wdata = 32'hCAFE_BABE;
        @(negedge clk);
        rf_we = 1; rd = 5'd10; rf_wdata = 32'h1234_5678;
        @(negedge clk);
        rf_we = 0; rs1 = 5'd5; rs2 = 5'd10;
        #1;
        if (rf_rdata1 === 32'hCAFE_BABE && rf_rdata2 === 32'h1234_5678) begin
            p=p+1; $display("PASS [TC2]: RF dual-port read/write verified");
        end else begin
            f=f+1; $display("FAIL [TC2]: RF R/W mismatch (r1=%h, r2=%h)", rf_rdata1, rf_rdata2);
        end

        // =========================================================
        // TC3: Register File - Same-Cycle Write-Through Forwarding
        // =========================================================
        @(negedge clk);
        rf_we = 1; rd = 5'd15; rs1 = 5'd15; rf_wdata = 32'hA5A5_5A5A;
        #1; // Check combinational bypass BEFORE clock edge
        if (rf_rdata1 === 32'hA5A5_5A5A) begin
            p=p+1; $display("PASS [TC3]: RF internal write-through forwarding works");
        end else begin
            f=f+1; $display("FAIL [TC3]: RF forwarding failed (Got %h)", rf_rdata1);
        end
        @(negedge clk);
        rf_we = 0;

        // =========================================================
        // TC4: LSU - Unaligned Word & Halfword Store Fault Suppression
        // =========================================================
        @(negedge clk);
        mem_req = 1; mem_we = 1; size = 2'b10; addr = 32'h0000_1002; lsu_wdata = 32'hDEAD_BEEF;
        #1;
        if (addr_fault === 1'b1 && mem_byte_en === 4'b0000) begin
            p=p+1; $display("PASS [TC4a]: LSU caught unaligned word store & suppressed byte_en");
        end else begin
            f=f+1; $display("FAIL [TC4a]: Unaligned word fault/suppression failed");
        end

        @(negedge clk);
        mem_req = 1; mem_we = 1; size = 2'b01; addr = 32'h0000_1003; // Odd address halfword
        #1;
        if (addr_fault === 1'b1 && mem_byte_en === 4'b0000) begin
            p=p+1; $display("PASS [TC4b]: LSU caught unaligned halfword store & suppressed byte_en");
        end else begin
            f=f+1; $display("FAIL [TC4b]: Unaligned halfword fault/suppression failed");
        end

        // =========================================================
        // TC5: LSU - Sign-Extended (LB) vs Zero-Extended (LBU) Byte Load
        // =========================================================
        @(negedge clk);
        mem_req = 1; mem_we = 0; size = 2'b00; addr = 32'h0000_1002; l_unsigned = 0;
        mem_rdata = 32'h00A5_0000; // Byte at offset 2 is 0xA5 (MSB=1)
        #1;
        if (lsu_rdata === 32'hFFFF_FFA5) begin p=p+1; $display("PASS [TC5a]: LSU sign-extended byte (LB) correctly"); end
        else begin f=f+1; $display("FAIL [TC5a]: LB failed (Got %h)", lsu_rdata); end

        l_unsigned = 1; // Switch to LBU
        #1;
        if (lsu_rdata === 32'h0000_00A5) begin p=p+1; $display("PASS [TC5b]: LSU zero-extended byte (LBU) correctly"); end
        else begin f=f+1; $display("FAIL [TC5b]: LBU failed (Got %h)", lsu_rdata); end

        // =========================================================
        // TC6: LSU - Halfword Store Alignment
        // =========================================================
        @(negedge clk);
        mem_req = 1; mem_we = 1; size = 2'b01; addr = 32'h0000_1002; lsu_wdata = 32'h0000_BEEF;
        #1;
        if (mem_byte_en === 4'b1100 && mem_wdata_out === 32'hBEEF_0000 && !addr_fault) begin 
            p=p+1; $display("PASS [TC6]: LSU aligned halfword store correctly"); 
        end else begin 
            f=f+1; $display("FAIL [TC6]: LSU halfword store failed"); 
        end

        // =========================================================
        // TC7: LSU - Delayed Memory Access & Pipeline Stall Generation
        // =========================================================
        @(negedge clk);
        mem_req = 1; mem_we = 0; size = 2'b10; addr = 32'h0000_2000;
        mem_ready = 0; // Simulate slow memory (Wait State)
        #1;
        if (stall === 1'b1) begin
            p=p+1; $display("PASS [TC7a]: LSU asserted pipeline stall on mem_ready=0");
        end else begin
            f=f+1; $display("FAIL [TC7a]: LSU failed to stall when mem_ready=0");
        end

        @(negedge clk); // Hold wait state for 1 full clock cycle
        @(negedge clk);
        mem_ready = 1; mem_rdata = 32'h8765_4321; // Memory responds
        #1;
        if (stall === 1'b0 && lsu_rdata === 32'h8765_4321) begin
            p=p+1; $display("PASS [TC7b]: LSU released stall and captured data on mem_ready=1");
        end else begin
            f=f+1; $display("FAIL [TC7b]: LSU stall release failed");
        end

        // =========================================================
        // TC8: Integrated Load-to-Register File Writeback
        // =========================================================
        rf_we = 1; rd = 5'd20; rf_wdata = lsu_rdata; // Write loaded word into x20
        @(negedge clk);
        mem_req = 0; rf_we = 0; rs1 = 5'd20;
        #1;
        if (rf_rdata1 === 32'h8765_4321) begin
            p=p+1; $display("PASS [TC8]: Integrated LSU Load -> RF x20 writeback verified");
        end else begin
            f=f+1; $display("FAIL [TC8]: Integrated Load -> RF writeback failed");
        end

        $display("========================================");
        $display("=== SUMMARY: %0d PASSED | %0d FAILED ===", p, f);
        $display("========================================");
        #20 $finish;
    end

    // Waveforms
    initial begin
        $dumpfile("riscv_waves.vcd");
        $dumpvars(0, riscv_tb);
    end

endmodule
