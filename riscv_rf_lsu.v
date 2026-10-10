// =====================================================================
// RISC-V Register File and Load-Store Unit (LSU)
// =====================================================================

// ---------------------------------------------------------------------
// Module 1: RISC-V 32-Register File
// ---------------------------------------------------------------------
module riscv_regfile (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        we,       // Write Enable
    input  wire [4:0]  rs1,      // Source Register 1 Address
    input  wire [4:0]  rs2,      // Source Register 2 Address
    input  wire [4:0]  rd,       // Destination Register Address
    input  wire [31:0] wdata,    // Write Data
    
    output wire [31:0] rdata1,   // Read Data 1
    output wire [31:0] rdata2    // Read Data 2
);

    reg [31:0] registers [0:31];
    integer i;

    // Asynchronous Read (RISC-V standard)
    // Register 0 (x0) is hardwired to 0.
    assign rdata1 = (rs1 == 5'b00000) ? 32'd0 : ((we && (rs1 == rd)) ? wdata : registers[rs1]);
    assign rdata2 = (rs2 == 5'b00000) ? 32'd0 : ((we && (rs2 == rd)) ? wdata : registers[rs2]);

    // Synchronous Write
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 32; i = i + 1) begin
                registers[i] <= 32'd0;
            end
        end else if (we && (rd != 5'b00000)) begin
            registers[rd] <= wdata;
        end
    end

endmodule

// ---------------------------------------------------------------------
// Module 2: RISC-V Load-Store Unit (LSU)
// ---------------------------------------------------------------------
module riscv_lsu (
    input  wire        clk,
    input  wire        rst_n,
    
    // CPU Core Interface
    input  wire        mem_req,     // Request active
    input  wire        mem_we,      // 0 = Load, 1 = Store
    input  wire [1:0]  size,        // 00=Byte, 01=Halfword, 10=Word
    input  wire        l_unsigned,  // 1 = Zero extend, 0 = Sign extend (for loads)
    input  wire [31:0] addr,        // Target memory address
    input  wire [31:0] wdata,       // Data to store
    
    output reg  [31:0] rdata,       // Data loaded to CPU
    output reg         addr_fault,  // Unaligned address exception
    output wire        stall,       // Pipeline stall signal
    
    // Main Memory Interface (Simulated 32-bit aligned memory)
    output wire [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    output reg  [3:0]  mem_byte_en,
    input  wire [31:0] mem_rdata,
    input  wire        mem_ready
);

    // Memory address is always word-aligned (drops bottom 2 bits)
    assign mem_addr = {addr[31:2], 2'b00};
    
    // Stall the pipeline if memory is requested but not ready
    assign stall = mem_req && !mem_ready;

    // Fault Detection & Byte Enable/Data Alignment Logic
    always @(*) begin
        addr_fault  = 1'b0;
        mem_byte_en = 4'b0000;
        mem_wdata   = 32'd0;
        rdata       = 32'd0;

        if (mem_req) begin
            case (size)
                2'b00: begin // BYTE (8-bit)
                    // No alignment faults for single bytes
                    if (mem_we) begin
                        case (addr[1:0])
                            2'b00: begin mem_byte_en = 4'b0001; mem_wdata = {24'd0, wdata[7:0]}; end
                            2'b01: begin mem_byte_en = 4'b0010; mem_wdata = {16'd0, wdata[7:0], 8'd0}; end
                            2'b10: begin mem_byte_en = 4'b0100; mem_wdata = {8'd0, wdata[7:0], 16'd0}; end
                            2'b11: begin mem_byte_en = 4'b1000; mem_wdata = {wdata[7:0], 24'd0}; end
                        endcase
                    end else begin
                        case (addr[1:0])
                            2'b00: rdata = l_unsigned ? {24'd0, mem_rdata[7:0]}   : {{24{mem_rdata[7]}}, mem_rdata[7:0]};
                            2'b01: rdata = l_unsigned ? {24'd0, mem_rdata[15:8]}  : {{24{mem_rdata[15]}}, mem_rdata[15:8]};
                            2'b10: rdata = l_unsigned ? {24'd0, mem_rdata[23:16]} : {{24{mem_rdata[23]}}, mem_rdata[23:16]};
                            2'b11: rdata = l_unsigned ? {24'd0, mem_rdata[31:24]} : {{24{mem_rdata[31]}}, mem_rdata[31:24]};
                        endcase
                    end
                end

                2'b01: begin // HALFWORD (16-bit)
                    if (addr[0] != 1'b0) begin
                        addr_fault = 1'b1; // Unaligned halfword fault
                    end else if (mem_we) begin
                        case (addr[1])
                            1'b0: begin mem_byte_en = 4'b0011; mem_wdata = {16'd0, wdata[15:0]}; end
                            1'b1: begin mem_byte_en = 4'b1100; mem_wdata = {wdata[15:0], 16'd0}; end
                        endcase
                    end else begin
                        case (addr[1])
                            1'b0: rdata = l_unsigned ? {16'd0, mem_rdata[15:0]}  : {{16{mem_rdata[15]}}, mem_rdata[15:0]};
                            1'b1: rdata = l_unsigned ? {16'd0, mem_rdata[31:16]} : {{16{mem_rdata[31]}}, mem_rdata[31:16]};
                        endcase
                    end
                end

                2'b10: begin // WORD (32-bit)
                    if (addr[1:0] != 2'b00) begin
                        addr_fault = 1'b1; // Unaligned word fault
                    end else if (mem_we) begin
                        mem_byte_en = 4'b1111;
                        mem_wdata   = wdata;
                    end else begin
                        rdata = mem_rdata;
                    end
                end
                
                default: addr_fault = 1'b0;
            endcase
        end
    end
endmodule
