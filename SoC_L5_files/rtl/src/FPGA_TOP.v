`timescale 1ns/10ps

module FPGA_TOP #(
    parameter SYSTEM_CLOCK_FREQ = 100_000_000,
    parameter BAUD_RATE = 115200,
    parameter CPU_CLOCK_FREQ = 50_000_000,
    parameter integer B_SAMPLE_COUNT_MAX = 0.0005 * CPU_CLOCK_FREQ,
    parameter integer B_PULSE_COUNT_MAX = 0.100 / 0.0005,
    parameter RESET_PC = 32'h4000_0000
) (
    input wire CLK100MHZ,
    input wire [3:0] BUTTONS,
    input wire [3:0] SWITCHES,
    output wire [3:0] LEDS,
    input wire usb_uart_rxd,
    output wire usb_uart_txd
);

    wire FPGA_SERIAL_RX;
    wire FPGA_SERIAL_TX;
    assign FPGA_SERIAL_RX = usb_uart_rxd;
    assign usb_uart_txd = FPGA_SERIAL_TX;
    
    wire [31:0] EXT_DIN;
    wire [3:0] EXT_WEA;
    wire EXT_EN;
    wire [15:0] EXT_ADDR;
    wire [15:0] EXT_ADDR_FF;
    wire [31:0] EXT_DOUT;
    
    wire clk;
    assign clk = CLK100MHZ;

    wire cpu_clk, cpu_clk_g, cpu_clk_pll_lock;
    wire cpu_clk_pll_fb_out, cpu_clk_pll_fb_in;
    
    BUFG  cpu_clk_buf     (.I(cpu_clk),               .O(cpu_clk_g));
    BUFG  cpu_clk_f_buf   (.I(cpu_clk_pll_fb_out),    .O (cpu_clk_pll_fb_in));

    /* verilator lint_off PINMISSING */
    PLLE2_ADV #(
        .BANDWIDTH            ("OPTIMIZED"),
        .COMPENSATION         ("BUF_IN"),
        .STARTUP_WAIT         ("FALSE"),
        .DIVCLK_DIVIDE        (4),
        .CLKFBOUT_MULT        (34),
        .CLKFBOUT_PHASE       (0.000),
        .CLKOUT0_DIVIDE       (17),
        .CLKOUT0_PHASE        (0.000),
        .CLKOUT0_DUTY_CYCLE   (0.500),
        .CLKIN1_PERIOD        (10.000)
    ) plle2_cpu_inst (
        .CLKFBOUT            (cpu_clk_pll_fb_out),
        .CLKOUT0             (cpu_clk),
        .CLKFBIN             (cpu_clk_pll_fb_in),
        .CLKIN1              (clk),
        .CLKIN2              (1'b0),
        .CLKINSEL            (1'b1),
        .LOCKED              (cpu_clk_pll_lock),
        .PWRDWN              (1'b0),
        .RST                 (1'b0)
    );

    wire [3:0] button_parsed;
    wire reset_button, reset;
    assign reset = reset_button|| ~cpu_clk_pll_lock;

    button_parser #(
        .width(4),
        .sample_count_max(B_SAMPLE_COUNT_MAX),
        .pulse_count_max(B_PULSE_COUNT_MAX)
    ) b_parser (
        .clk(cpu_clk_g),
        .in(BUTTONS[0]),
        .out(button_parsed)
    );
    
    assign reset_button = button_parsed[0];
    
    wire cpu_tx, cpu_rx;

    RVCORE_TOP #(
        .CPU_CLOCK_FREQ(CPU_CLOCK_FREQ),
        .RESET_PC(RESET_PC),
        .BAUD_RATE(BAUD_RATE),
        .AWIDTH(16)
    ) cpu (
        .clk(cpu_clk_g),
        .rst(reset),
        .FPGA_SERIAL_RX(cpu_rx),
        .FPGA_SERIAL_TX(cpu_tx),
        .TEST_BIOS(1'b0),
        
        .EXT_DIN(EXT_DIN),
        .EXT_WEA(EXT_WEA),
        .EXT_EN(EXT_EN),
        .EXT_ADDR(EXT_ADDR),
        .EXT_DOUT(EXT_DOUT) 
    );
    
    reg [3:0] reg_led;
    
    always @(posedge cpu_clk_g or posedge reset_button) begin
        if(reset_button) begin
            reg_led <= 4'd0;
        end
        else if(EXT_EN & EXT_WEA[0] & (EXT_ADDR == 16'd0)) begin
            reg_led[0]   <= EXT_DIN[0];
            reg_led[1]   <= EXT_DIN[1];
            reg_led[2]   <= EXT_DIN[2]; 
            reg_led[3]   <= EXT_DIN[3];
        end
    end
    
    assign LEDS = reg_led;
    
    PipeReg #(16) FF_EXT_ADDR (.CLK(cpu_clk_g), .RST(reset), .EN(1'b1), .D(EXT_ADDR), .Q(EXT_ADDR_FF));
    
    // =========================================================================
    // [수정됨] Convolution Accelerator 연결 로직
    // =========================================================================
    
    // 1. 가속기 신호 선언
    wire [5:0]  conv_addr;
    wire        acc_en;
    wire        acc_we;
    wire [31:0] acc_dout;

    // 2. 주소 디코딩 및 변환 (수정됨!)
    // C 코드 #define ACC_BASE_ADDR 0x80010400 와 일치시킴.
    // Offset 0x400 (Byte) -> Decimal 1024
    // 1024 / 64 (페이지 크기) = 16 (10'd16)
    assign acc_en = EXT_EN && (EXT_ADDR[15:6] == 10'd16); 
    
    // Byte Addressing을 Word Addressing으로 변환
    // C에서 0x40 -> Verilog 0x10 (16)
    // 따라서 EXT_ADDR의 하위 비트 [7:2]를 사용해야 함 (나누기 4)
    assign conv_addr = EXT_ADDR[7:2]; 
    
    assign acc_we = EXT_WEA[0];

    // 3. 모듈 인스턴스화
    convolution_acc u_conv_acc (
        .clk    (cpu_clk_g),
        .rst    (reset),
        .addr   (conv_addr),
        .en     (acc_en),
        .we     (acc_we),
        .din    (EXT_DIN),
        .dout   (acc_dout)
    );

    // 4. Read Data MUX 수정 (수정됨!)
    // acc_en 조건과 동일하게 ADDR_FF의 상위 비트가 16일 때 가속기 데이터를 선택
    assign EXT_DOUT =   (EXT_ADDR_FF == 16'd0) ? LEDS :
                        (EXT_ADDR_FF == 16'd1) ? SWITCHES :
                        (EXT_ADDR_FF == 16'd2) ? BUTTONS :
                        (EXT_ADDR_FF[15:6] == 10'd16) ? acc_dout : // [수정] 10'd4 -> 10'd16 (0x400 대응)
                        32'd0;

    // =========================================================================
    
    (* IOB = "true" *) reg fpga_serial_tx_iob;
    (* IOB = "true" *) reg fpga_serial_rx_iob;
    assign FPGA_SERIAL_TX = fpga_serial_tx_iob;
    assign cpu_rx = fpga_serial_rx_iob;
    always @(posedge cpu_clk_g) begin
        fpga_serial_tx_iob <= cpu_tx;
        fpga_serial_rx_iob <= FPGA_SERIAL_RX;
    end
   
endmodule
