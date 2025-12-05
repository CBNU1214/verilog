#include "types.h"
#include "memory_map.h"
#include "ascii.h"
#include "uart.h"

#define BUF_LEN 128

typedef void (*entry_t)(void);


int __attribute__ ((noinline)) timer_count(uint32_t num)
{
    uint32_t counter;

    counter = CYCLE_COUNTER;//CSR read by macro

    COUNTER_RST = 1; //CSR write by macro

    uint32_t temp;
    for(int i = 0 ; i < num ; i ++){
        temp = CYCLE_COUNTER;//CSR read by macro
    }
    counter -= temp;

    return counter;
}

int main(void)
{
    int a, b, c;

    a = 1;
    b = 2;
    c = a + b;
    
    uwrite_int8s("1234567890\r\n"); // print custom string by uart
    int8_t buffer[BUF_LEN];

    int d = timer_count(10); // run custom function
    uwrite_int8s("custom function results:"); // print custom string by uart
    uwrite_int8s(uint32_to_ascii_hex(c,buffer,BUF_LEN)); // print cariable's value by uart
    uwrite_int8s("\r\n");

    // infinite loop for simulation, comment out for on-chip demo
//    while(1); 

    // returning to bios
    uint32_t bios = ascii_hex_to_uint32("40000000");
    entry_t start = (entry_t) (bios);
    start();
    return 0;
}





