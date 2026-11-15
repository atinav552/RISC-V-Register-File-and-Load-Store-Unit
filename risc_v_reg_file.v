
// ---------------------------------------------------------------------
// Module RISC-V 32-Register File
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

    // Allocate only x1 through x31 (x0 is hardwired constant 0, saving 32 FFs)
    reg [31:0] registers [1:31];
    integer i;

    // Asynchronous Read with Same-Cycle Write-Through Bypass
    // Checking (rsX == 5'd0) first prevents writes to x0 from bypassing non-zero wdata
    assign rdata1 = (rs1 == 5'd0) ? 32'd0 : ((we && (rs1 == rd)) ? wdata : registers[rs1]);
    assign rdata2 = (rs2 == 5'd0) ? 32'd0 : ((we && (rs2 == rd)) ? wdata : registers[rs2]);

    // Synchronous Write (Ignores writes targeting x0)
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            for (i = 1; i < 32; i = i + 1) begin
                registers[i] <= 32'd0;
            end
        end else if (we && (rd != 5'd0)) begin
            registers[rd] <= wdata;
        end
    end

endmodule
