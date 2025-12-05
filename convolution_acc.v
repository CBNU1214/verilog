module convolution_acc (
    input wire          clk,
    input wire          rst,
    input wire [5:0]    addr,   // Word Address (0x00, 0x01, 0x10...)
    input wire          en,     // enable 신호
    input wire          we,     // 1이면 쓰기 0이면 읽기
    input wire [31:0]   din,    // CPU -> Accelerator
    output reg [31:0]   dout    // Accelerator -> CPU
);

    // =================================================================
    // 1. 레지스터 정의
    // =================================================================
    reg [31:0] kernel [0:8];    // 커널 가중치
    reg [31:0] window [0:8];    // 윈도우 데이터
    reg [31:0] result;          // 결과 값
    
    reg start_reg;              // Start (Bit 0)
    reg done_reg;               // Done (Bit 1)
    reg busy_reg;               // Busy (Bit 0 of Status)

    integer i;

    // =================================================================
    // 2. Convolution 연산 로직
    // =================================================================
    wire signed [31:0] mult_res [0:8];
    wire signed [31:0] sum_res;

    genvar j;
    generate
        for (j = 0; j < 9; j = j + 1) begin : MAC_UNIT
            assign mult_res[j] = $signed(window[j]) * $signed(kernel[j]);
        end
    endgenerate

    assign sum_res = mult_res[0] + mult_res[1] + mult_res[2] +
                     mult_res[3] + mult_res[4] + mult_res[5] +
                     mult_res[6] + mult_res[7] + mult_res[8];

    // =================================================================
    // 3. 레지스터 쓰기 및 제어 (수정됨)
    // =================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start_reg <= 1'b0;
            busy_reg  <= 1'b0;
            done_reg  <= 1'b0;
            result    <= 32'd0;
            for (i=0; i<9; i=i+1) begin
                kernel[i] <= 32'd0;
                window[i] <= 32'd0;
            end
        end
        else begin
            // 1. Start 신호 Self-clearing (기본적으로 0으로 돌아감)
            start_reg <= 1'b0;

            // 2. CPU 쓰기 동작
            if (en && we) begin
                case (addr)
                    // Control Reg (Addr 0x00)
                    6'h00: begin
                        // CPU가 1을 쓰면 start_reg를 1로 설정 (다음 클럭에 다시 0이 됨)
                        if (din[0]) start_reg <= 1'b1;
                    end
                    
                    // Kernel Values (Addr 0x10 ~ 0x18)
                    6'h10: kernel[0] <= din;
                    6'h11: kernel[1] <= din;
                    6'h12: kernel[2] <= din;
                    6'h13: kernel[3] <= din;
                    6'h14: kernel[4] <= din;
                    6'h15: kernel[5] <= din;
                    6'h16: kernel[6] <= din;
                    6'h17: kernel[7] <= din;
                    6'h18: kernel[8] <= din;

                    // Window Values (Addr 0x20 ~ 0x28)
                    6'h20: window[0] <= din;
                    6'h21: window[1] <= din;
                    6'h22: window[2] <= din;
                    6'h23: window[3] <= din;
                    6'h24: window[4] <= din;
                    6'h25: window[5] <= din;
                    6'h26: window[6] <= din;
                    6'h27: window[7] <= din;
                    6'h28: window[8] <= din;
                endcase
            end

            // 3. 상태 머신 (연산 제어)
            if (start_reg) begin
                busy_reg <= 1'b1;
                done_reg <= 1'b0;
            end
            else if (busy_reg) begin
                result   <= sum_res; // 연산 결과 저장
                busy_reg <= 1'b0;    // Busy 해제
                done_reg <= 1'b1;    // Done 설정
            end
        end
    end

    // =================================================================
    // 4. 레지스터 읽기 동작
    // =================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dout <= 32'd0;
        end
        else begin
            dout <= 32'd0; // 기본값
            if (en && !we) begin
                case (addr)
                    6'h00: dout <= {31'd0, start_reg};
                    6'h01: dout <= {30'd0, done_reg, busy_reg}; // Status
                    6'h02: dout <= result;
                    
                    6'h10: dout <= kernel[0];
                    6'h11: dout <= kernel[1];
                    6'h12: dout <= kernel[2];
                    6'h13: dout <= kernel[3];
                    6'h14: dout <= kernel[4];
                    6'h15: dout <= kernel[5];
                    6'h16: dout <= kernel[6];
                    6'h17: dout <= kernel[7];
                    6'h18: dout <= kernel[8];

                    6'h20: dout <= window[0];
                    6'h21: dout <= window[1];
                    6'h22: dout <= window[2];
                    6'h23: dout <= window[3];
                    6'h24: dout <= window[4];
                    6'h25: dout <= window[5];
                    6'h26: dout <= window[6];
                    6'h27: dout <= window[7];
                    6'h28: dout <= window[8];
                    default: dout <= 32'd0;
                endcase
            end
        end
    end

endmodule
