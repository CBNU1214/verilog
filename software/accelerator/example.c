#include "types.h"
#include "memory_map.h"
#include "ascii.h"
#include "uart.h"

// =================================================================
// 1. 하드웨어 가속기 주소 정의
// =================================================================
// FPGA_TOP에서 0x100(Word Address)을 할당했으므로,
// C언어 Byte Address = 0x80010000(Base) + 0x400(Offset)
#define ACC_BASE_ADDR       0x80010400

// 레지스터 오프셋 (Byte 단위)
#define ACC_REG_CTRL        0x00  // Verilog addr 0x00
#define ACC_REG_STATUS      0x04  // Verilog addr 0x01
#define ACC_REG_RESULT      0x08  // Verilog addr 0x02
#define ACC_REG_KERNEL_BASE 0x40  // Verilog addr 0x10 (16 * 4bytes = 64 = 0x40)
#define ACC_REG_WINDOW_BASE 0x80  // Verilog addr 0x20 (32 * 4bytes = 128 = 0x80)

// 버퍼 길이 정의
#define BUF_LEN 128

// =================================================================
// 2. 메인 함수
// =================================================================
int main(void)
{
    // 결과 출력을 위한 버퍼
    int8_t buffer[BUF_LEN];

    // 가속기 테스트 시작 메시지
    uwrite_int8s("\r\n================================\r\n");
    uwrite_int8s("   Convolution Accelerator Test   \r\n");
    uwrite_int8s("================================\r\n");

    // ---------------------------------------------------------
    // Step 1: 테스트 데이터 준비 (Sobel Filter 예시)
    // ---------------------------------------------------------
    // 커널 (Vertical Edge Detection)
    int32_t kernel[9] = {
        1,  0, -1,
        2,  0, -2,
        1,  0, -1
    };
    
    // 윈도우 데이터 (테스트용 임의 픽셀 값)
    int32_t window[9] = {
        10, 20, 30,
        40, 50, 60,
        70, 80, 90
    };

    // ---------------------------------------------------------
    // Step 2: 하드웨어 가속기에 데이터 입력
    // ---------------------------------------------------------
    uwrite_int8s("[HW] Writing Data to Accelerator...\r\n");

    // Kernel 값 쓰기 (0x40 ~ 0x60)
    for(int i = 0; i < 9; i++) {
        // 주소 계산: Base + Kernel_Base + (Index * 4)
        *(volatile uint32_t *)(ACC_BASE_ADDR + ACC_REG_KERNEL_BASE + (i * 4)) = kernel[i];
    }

    // Window 값 쓰기 (0x80 ~ 0xA0)
    for(int i = 0; i < 9; i++) {
        *(volatile uint32_t *)(ACC_BASE_ADDR + ACC_REG_WINDOW_BASE + (i * 4)) = window[i];
    }

    // ---------------------------------------------------------
    // Step 3: 연산 시작 및 대기
    // ---------------------------------------------------------
    uwrite_int8s("[HW] Starting Computation...\r\n");

    // Control 레지스터(0x00)에 1을 써서 Start 신호 발생
    *(volatile uint32_t *)(ACC_BASE_ADDR + ACC_REG_CTRL) = 1;

    // Polling: Status 레지스터(0x04)의 Done 비트(Bit 1)가 1이 될 때까지 대기
    while(1) {
        uint32_t status = *(volatile uint32_t *)(ACC_BASE_ADDR + ACC_REG_STATUS);
        if (status & 0x02) { // Done bit check
            break;
        }
    }

    // ---------------------------------------------------------
    // Step 4: 결과 읽기 및 CPU 검증
    // ---------------------------------------------------------
    // 하드웨어 결과 읽기 (0x08)
    int32_t hw_result = *(volatile uint32_t *)(ACC_BASE_ADDR + ACC_REG_RESULT);

    // 소프트웨어로 동일한 연산 수행 (검증용)
    int32_t sw_result = 0;
    for(int i = 0; i < 9; i++) {
        sw_result += (kernel[i] * window[i]);
    }

    // ---------------------------------------------------------
    // Step 5: 결과 비교 및 출력
    // ---------------------------------------------------------
    uwrite_int8s("[Result]\r\n");
    
    // HW 결과 출력
    uwrite_int8s("HW Result: ");
    uint32_to_ascii_hex((uint32_t)hw_result, buffer, BUF_LEN);
    uwrite_int8s(buffer);
    uwrite_int8s("\r\n");

    // SW 결과 출력
    uwrite_int8s("SW Result: ");
    uint32_to_ascii_hex((uint32_t)sw_result, buffer, BUF_LEN);
    uwrite_int8s(buffer);
    uwrite_int8s("\r\n");

    // 최종 판정
    if (hw_result == sw_result) {
        uwrite_int8s(">> Verification: SUCCESS\r\n");
    } else {
        uwrite_int8s(">> Verification: FAIL\r\n");
    }

    // 무한 루프로 종료 방지
    while(1);
    
    return 0;
}
