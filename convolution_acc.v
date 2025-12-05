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

    reg [31:0] kernel [0:8];    // 커널 가중치 저장소 (K0 ~ K8) 3x3 필터
    reg [31:0] window [0:8];    // 이미지 픽셀 데이터 저장소 (D0 ~ D8) 3x3 이미지 픽셀
    reg [31:0] result;          // 결과 값 (컨볼루션)
    
    reg start_reg;              // Start 신호(연산을 시작해라)
    reg done_reg;               // Done 신호 (연산이 끝남)
    reg busy_reg;               // Busy 신호 (연산 중임)

    integer i;

    // =================================================================
    // 2. Convolution 연산 로직 (Combinational Logic)
    // =================================================================
    // 9개의 곱셈과 덧셈을 병렬로 처리 (하드웨어의 장점)
    // signed 연산을 위해 $signed() 시스템 함수 사용
    wire signed [31:0] mult_res [0:8]; // mult_res[0] ~ mult_res[8]: (window[j] * kernel[j]) 곱셈결과
    wire signed [31:0] sum_res; // sum_res: mult_res 9개를 모두 더한합

    genvar j;
    generate
        for (j = 0; j < 9; j = j + 1) begin : MAC_UNIT
            assign mult_res[j] = $signed(window[j]) * $signed(kernel[j]);
        end
    endgenerate // 조합논리 곱셈기 9개를 병렬로 생성

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
        else if (en && we) begin // 리셋이 아닐 때, 버스에서 이 모듈이 선택(en)되고, 쓰기 사이클 (we=1)인 경우
            case (addr)
                6'h00: start_reg <= din[0]; // Control Register에 Start 비트 쓰기
                                            // CPU가 이 주소에 1을 쓰면 start_reg= 1이 되어 연산 시작 트리거
                                            // addr == 6'h00이면 din[0](LSB)를 start_reg에 저장
                
                // Kernel 값 쓰기 (주소 0x10 ~ 0x18)
                // 각각의 addr에 대응해서 kernel[0]~kernel[8]에 din을 저장
                // CPU가 addr=0x10, din=0x00000003 쓰면 kernel[0] = 3
                6'h10: kernel[0] <= din;
                6'h11: kernel[1] <= din;
                6'h12: kernel[2] <= din;
                6'h13: kernel[3] <= din;
                6'h14: kernel[4] <= din;
                6'h15: kernel[5] <= din;
                6'h16: kernel[6] <= din;
                6'h17: kernel[7] <= din;
                6'h18: kernel[8] <= din;

                // Window Data 값 쓰기 (주소 0x20 ~ 0x28)
                // 결국 cpu는 9번 write해서 3x3윈도우를 채운 뒤, start를 눌러 연산 시작하는 구조
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
            start_reg <= 1'b0; // Start 신호는 1클럭만 유지 (Self-clearing)
        end
    end

    // =================================================================
    // 4. 상태 머신 및 연산 제어 (FSM)
    // =================================================================
    // 간단한 2상태 FSM: IDLE -> RUN -> DONE
    always @(posedge clk or posedge rst) begin
        if (rst) begin
            busy_reg <= 1'b0;
            done_reg <= 1'b0;
            result   <= 32'd0;
        end
        else begin
            if (start_reg) begin
                busy_reg <= 1'b1;     // 연산 시작
                done_reg <= 1'b0;
            end
            else if (busy_reg) begin
                result   <= sum_res;  // 계산된 결과를 레지스터에 저장
                busy_reg <= 1'b0;     // 연산 종료
                done_reg <= 1'b1;     // 완료 플래그 세트
            end
           
        end
    end

    // =================================================================
    // 5. 레지스터 읽기 동작 (Accelerator -> CPU) 확인 용도
    // =================================================================
    always @(*) begin
        dout = 32'd0; // 기본값
        if (en && !we) begin
            case (addr)
                6'h00: dout = {31'd0, start_reg};
                6'h01: dout = {30'd0, done_reg, busy_reg}; 
                6'h02: dout = result;
                
                6'h10: dout = kernel[0];
                6'h20: dout = window[0];
                default: dout = 32'd0;
            endcase
        end
    end

endmodule