module convolution_acc (
    input wire          clk,
    input wire          rst,
    input wire [5:0]    addr,   // 6-bit address (총 64개 레지스터 공간 확보)
    input wire          en,     // enable 신호
    input wire          we,     // 1이면 쓰기 0이면 읽기
    input wire [31:0]   din,    // CPU가 가속기에 쓰는 데이터
    output reg [31:0]   dout    // CPU가 가속기에서 읽어갈 데이터
);

    // =================================================================
    // 1. 레지스터 정의 (Register Map)
    // =================================================================
    // 0x00: Control (Bit 0: Start)
    // 0x01: Status  (Bit 0: Busy, Bit 1: Done)
    // 0x02: Result  (Convolution 결과)
    // 0x10 ~ 0x18: Kernel Values (9개)
    // 0x20 ~ 0x28: Window Data Values (9개)

    reg [31:0] kernel [0:8];    // 커널 가중치 저장소 (K0 ~ K8)
    reg [31:0] window [0:8];    // 이미지 픽셀 데이터 저장소 (D0 ~ D8)
    reg [31:0] result;          // 결과 값
    
    reg start_reg;              // Start 신호
    reg done_reg;               // Done 신호
    reg busy_reg;               // Busy 신호

    integer i;

    // =================================================================
    // 2. Convolution 연산 로직 (Combinational Logic)
    // =================================================================
    // 9개의 곱셈과 덧셈을 병렬로 처리
    wire signed [31:0] mult_res [0:8];
    wire signed [31:0] sum_res;

    genvar j;
    generate
        for (j = 0; j < 9; j = j + 1) begin : MAC_UNIT
            assign mult_res[j] = $signed(window[j]) * $signed(kernel[j]);
        end
    endgenerate

    // 모든 곱셈 결과를 더함
    assign sum_res = mult_res[0] + mult_res[1] + mult_res[2] +
                     mult_res[3] + mult_res[4] + mult_res[5] +
                     mult_res[6] + mult_res[7] + mult_res[8];

    // =================================================================
    // 3. 레지스터 쓰기 동작 (CPU -> Accelerator)
    // =================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            start_reg <= 1'b0;
            for (i=0; i<9; i=i+1) begin
                kernel[i] <= 32'd0;
                window[i] <= 32'd0;
            end
        end
        else if (en && we) begin
            case (addr)
                6'h00: start_reg <= din[0];
                
                // Kernel 값 쓰기 (0x10 ~ 0x18)
                6'h10: kernel[0] <= din;
                6'h11: kernel[1] <= din;
                6'h12: kernel[2] <= din;
                6'h13: kernel[3] <= din;
                6'h14: kernel[4] <= din;
                6'h15: kernel[5] <= din;
                6'h16: kernel[6] <= din;
                6'h17: kernel[7] <= din;
                6'h18: kernel[8] <= din;

                // Window Data 값 쓰기 (0x20 ~ 0x28)
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
        else begin
            start_reg <= 1'b0; // Self-clearing
        end
    end

    // =================================================================
    // 4. 상태 머신 및 연산 제어 (FSM)
    // =================================================================
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_reg <= 1'b0;
            done_reg <= 1'b0;
            result   <= 32'd0;
        end
        else begin
            if (start_reg) begin
                busy_reg <= 1'b1;
                done_reg <= 1'b0;
            end
            else if (busy_reg) begin
                result   <= sum_res;  // 결과 저장
                busy_reg <= 1'b0;
                done_reg <= 1'b1;     // 완료 플래그
            end
        end
    end

    // =================================================================
    // [수정됨] 5. 레지스터 읽기 동작 (Accelerator -> CPU)
    // =================================================================
    // CPU가 주소를 보낸 다음 클럭에 데이터를 가져가므로, 
    // always @(posedge clk)를 사용하여 데이터를 1클럭 유지시켜 줍니다.
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            dout <= 32'd0;
        end
        else begin
            dout <= 32'd0; // 기본값 (선택되지 않을 때 0)
            
            if (en && !we) begin
                case (addr)
                    // Control & Status
                    6'h00: dout <= {31'd0, start_reg};
                    6'h01: dout <= {30'd0, done_reg, busy_reg}; 
                    6'h02: dout <= result;
                    
                    // Kernel Readback
                    6'h10: dout <= kernel[0];
                    6'h11: dout <= kernel[1];
                    6'h12: dout <= kernel[2];
                    6'h13: dout <= kernel[3];
                    6'h14: dout <= kernel[4];
                    6'h15: dout <= kernel[5];
                    6'h16: dout <= kernel[6];
                    6'h17: dout <= kernel[7];
                    6'h18: dout <= kernel[8];

                    // Window Readback
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
