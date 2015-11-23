/* register file */

`timescale 1ps/1ps
module regs(input clk,
            input ren0, input [3:0]raddr0, output [15:0]rdata0,
            input ren1, input [3:0]raddr1, output [15:0]rdata1,
            input wen, input [3:0]waddr, input [15:0]wdata);
    reg [15:0]data[15:0];

    reg ren0_reg;
    reg [3:0]raddr0_reg;
    reg ren1_reg;
    reg [3:0]raddr1_reg;
    reg wen_reg;
    reg [3:0]waddr_reg;
    reg [15:0]wdata_reg;

    reg [15:0]out0 = 16'hxxxx;
    assign rdata0 = out0;
    reg [15:0]out1 = 16'hxxxx;
    assign rdata1 = out1;

    always @(posedge clk) begin
        ren0_reg <= ren0;
        raddr0_reg <= raddr0;
        ren1_reg <= ren1;
        raddr1_reg <= raddr1;
        wen_reg <= wen;
        waddr_reg <= waddr;
        wdata_reg <= wdata;

        if (ren0_reg) begin
            out0 <= data[raddr0_reg];
        end
        if (ren1_reg) begin
            out1 <= data[raddr1_reg];
        end
        if (wen_reg) begin
            $display("#reg[%d] <= 0x%x",waddr_reg,wdata_reg);
            data[waddr_reg] <= wdata_reg;
        end
    end

endmodule
