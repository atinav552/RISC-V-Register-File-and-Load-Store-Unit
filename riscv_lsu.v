// ---------------------------------------------------------------------
// Module RISC-V Load-Store Unit (LSU)
// ---------------------------------------------------------------------
module riscv_lsu (
    input  wire        clk,
    input  wire        rst_n,
    
    // CPU Core Interface
    input  wire        mem_req,    // Request active
    input  wire        mem_we,     // 0 = Load, 1 = Store
    input  wire [1:0]  size,       // 00=Byte, 01=Halfword, 10=Word
    input  wire        l_unsigned, // 1 = Zero extend, 0 = Sign extend (for loads)
    input  wire [31:0] addr,       // Target memory address
    input  wire [31:0] wdata,      // Data to store
    
    output reg  [31:0] rdata,      // Data loaded to CPU
    output reg         addr_fault, // Unaligned address exception
    output wire        stall,      // Pipeline stall signal
    
    // Main Memory Interface (32-bit aligned)
    output wire        mem_valid,  // Valid transaction request to memory
    output wire        mem_we_out, // Write enable to memory
    output wire [31:0] mem_addr,
    output reg  [31:0] mem_wdata,
    output reg  [3:0]  mem_byte_en,
    input  wire [31:0] mem_rdata,
    input  wire        mem_ready
);

    // FSM States for tracking multi-cycle memory accesses & exceptions
    localparam IDLE     = 2'b00,
               WAIT_MEM = 2'b01,
               FAULT    = 2'b10;

    reg [1:0]  state, next_state;
    reg [7:0]  selected_byte;
    reg [15:0] selected_half;

    // Word-aligned memory address
    assign mem_addr   = {addr[31:2], 2'b00};
    
    // Issue a request to memory only if there is no alignment fault
    assign mem_valid  = mem_req && !addr_fault && (state != FAULT);
    assign mem_we_out = mem_valid && mem_we;

    // Stall the pipeline if a valid memory request is waiting on mem_ready
    assign stall      = mem_valid && !mem_ready;

    // Sequential State Register
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= IDLE;
        else
            state <= next_state;
    end

    // Next-State Logic
    always @(*) begin
        next_state = state;
        case (state)
            IDLE: begin
                if (mem_req) begin
                    if (addr_fault)
                        next_state = FAULT;
                    else if (!mem_ready)
                        next_state = WAIT_MEM;
                end
            end
            WAIT_MEM: begin
                if (mem_ready)
                    next_state = IDLE;
            end
            FAULT: begin
                next_state = IDLE; // Clear fault state on next cycle as trap handler takes over
            end
            default: next_state = IDLE;
        endcase
    end

    // Shared Byte & Halfword Extraction Muxes for Loads (Reduces LUT/Mux Area)
    always @(*) begin
        case (addr[1:0])
            2'b00: selected_byte = mem_rdata[7:0];
            2'b01: selected_byte = mem_rdata[15:8];
            2'b10: selected_byte = mem_rdata[23:16];
            2'b11: selected_byte = mem_rdata[31:24];
        endcase

        selected_half = addr[1] ? mem_rdata[31:16] : mem_rdata[15:0];
    end

    // Fault Detection, Byte-Enable Steering & Sign/Zero Extension Logic
    always @(*) begin
        addr_fault  = 1'b0;
        mem_byte_en = 4'b0000;
        mem_wdata   = 32'd0;
        rdata       = 32'd0;

        if (mem_req) begin
            case (size)
                2'b00: begin // BYTE (8-bit)
                    if (mem_we) begin
                        mem_byte_en = 4'b0001 << addr[1:0];
                        mem_wdata   = {24'd0, wdata[7:0]} << {addr[1:0], 3'b000};
                    end else begin
                        rdata = {{24{~l_unsigned & selected_byte[7]}}, selected_byte};
                    end
                end

                2'b01: begin // HALFWORD (16-bit)
                    if (addr[0] != 1'b0) begin
                        addr_fault = 1'b1; // Unaligned halfword fault
                    end else if (mem_we) begin
                        mem_byte_en = addr[1] ? 4'b1100 : 4'b0011;
                        mem_wdata   = addr[1] ? {wdata[15:0], 16'd0} : {16'd0, wdata[15:0]};
                    end else begin
                        rdata = {{16{~l_unsigned & selected_half[15]}}, selected_half};
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
                
                default: addr_fault = 1'b1; // Invalid size encoding (2'b11) triggers fault
            endcase
        end
    end
endmodule
