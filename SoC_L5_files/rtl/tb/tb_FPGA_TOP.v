`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 2025/06/16 11:46:44
// Design Name: 
// Module Name: tb_FPGA_TOP
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module tb_FPGA_TOP();
    parameter PER = 20;
    parameter HPER = 10;
    parameter CLOCK_FREQ = 50_000_000;
    
    reg clk;
    reg rst;
    wire FPGA_SERIAL_RX;
    wire FPGA_SERIAL_TX;
    reg TEST_BIOS;
    
    wire [31:0] EXT_DIN;
    wire [3:0] EXT_WEA;
    wire EXT_EN;
    wire [15:0] EXT_ADDR;
    wire [15:0] EXT_ADDR_FF;
    wire [31:0] EXT_DOUT;
    
    parameter BAUD_RATE = 10_000_000; //115200 for actual scenario simulation, 10_000_000 for quick simulation
    
    RVCORE_TOP #(
        .CPU_CLOCK_FREQ(50_000_000),
        .RESET_PC(32'h4000_0000),
        .BAUD_RATE(BAUD_RATE),
        .AWIDTH(16)
    ) cpu (
        .clk(clk),
        .rst(rst),
        .FPGA_SERIAL_RX(FPGA_SERIAL_RX),
        .FPGA_SERIAL_TX(FPGA_SERIAL_TX),
        .TEST_BIOS(TEST_BIOS),
        
        .EXT_DIN(EXT_DIN),
        .EXT_WEA(EXT_WEA),
        .EXT_EN(EXT_EN),
        .EXT_ADDR(EXT_ADDR),
        .EXT_DOUT(EXT_DOUT)
    );


	///////////////Host PC simulation part

	reg [7:0] host2rv_byte;
	reg host2rv_byte_valid;
	wire host2rv_byte_ready;

	wire [7:0] rv2host_byte;
	wire rv2host_byte_vaild;
	reg	rv2host_byte_ready;


    uart #(
        .CLOCK_FREQ(50_000_000),
        .BAUD_RATE(BAUD_RATE)
    ) host_pc_uart (
        .clk(clk),
        .reset(rst),

        .data_in(host2rv_byte),
        .data_in_valid(host2rv_byte_valid),
        .data_in_ready(host2rv_byte_ready),
        .serial_in(FPGA_SERIAL_TX),

        .data_out_ready(rv2host_byte_ready),
        .data_out(rv2host_byte),
        .data_out_valid(rv2host_byte_vaild),
        .serial_out(FPGA_SERIAL_RX)
    );


    reg [7:0] host_uart_record;

    initial begin
		clk	=	1'b0;
		rst	=	1'b0;
        TEST_BIOS = 1'b1;
        host2rv_byte = 8'b0;
		host2rv_byte_valid = 1'b0;
		rv2host_byte_ready = 1'b0;
		host_uart_record = 8'b0;

		#(10*PER)
		rst	=	1'b1;
	
		#(10*PER)
		rst	=	1'b0;

		#(10*PER)

		#(10000*PER)
	
		$stop;
	end

    initial begin
		clk = 1'b0;
		forever #(HPER) clk= ~clk;
	end
	
	PipeReg #(16) FF_EXT_ADDR (.CLK(clk), .RST(rst), .EN(1'b1), .D(EXT_ADDR), .Q(EXT_ADDR_FF));
	
    assign EXT_DOUT =   (EXT_ADDR_FF == 16'd0)          ? 32'd0 :
                        (EXT_ADDR_FF == 16'd1)          ? 32'd1 :
                        (EXT_ADDR_FF == 16'd2)          ? 32'd2 :
                        32'd0;
    
    
    always @(negedge rv2host_byte_vaild or posedge rv2host_byte_vaild) begin
        host_uart_record <= FPGA_SERIAL_TX ? 8'h23 : rv2host_byte;
    end
    
endmodule
