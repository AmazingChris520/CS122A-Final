#include <stdio.h>
#include "pico/stdlib.h"
#include "hardware/adc.h"
#include "hardware/spi.h"

#define SPI_PORT spi0
#define SCK_PIN  18
#define MOSI_PIN 19
#define CS_PIN   17
#define REST_X       2900   // <-- replace with what you measured
#define DEADBAND     400

int moveInt = 0;

enum movement {START, IDLE};
enum movement stateMove = START;
enum SPIState {SPISTART, TRANSMIT};
enum SPIState state_spi = SPISTART;

void move(enum movement *state) {
    switch (*state) {
        case START:
            *state = IDLE;
            break;

        case IDLE:
            adc_select_input(0); // Reads GPIO 26
            int value = adc_read();
            printf("ADC0 rest=%d\n", value); 
            
            if      (value > REST_X + DEADBAND) moveInt = 1;   // right
            else if (value < REST_X - DEADBAND) moveInt = 2;   // left
            else moveInt = 0;   // idle
            break;
    }
}

void SPITick(enum SPIState *state) {
    switch (*state) {
        case SPISTART:
            *state = TRANSMIT;
            break;
        case TRANSMIT:
            break;
        default:
            *state = SPISTART;
            break;
    }

    switch (*state) {
        case SPISTART:
            break;

        case TRANSMIT:
            gpio_put(CS_PIN, 0);
            
            uint8_t tx_payload = (uint8_t)moveInt;
            spi_write_blocking(SPI_PORT, &tx_payload, 1);
            
            gpio_put(CS_PIN, 1);
            break;

        default:
            break;
    }
}

bool Tick() {
    SPITick(&state_spi);
    move(&stateMove);
    return true;
}

struct repeating_timer timer;

int main() {
    stdio_init_all();
    
    spi_init(SPI_PORT, 1000000);
    gpio_set_function(SCK_PIN, GPIO_FUNC_SPI);
    gpio_set_function(MOSI_PIN, GPIO_FUNC_SPI);
    
    gpio_init(CS_PIN);
    gpio_set_dir(CS_PIN, GPIO_OUT);
    gpio_put(CS_PIN, 1); 

    gpio_init(6);
    gpio_set_dir(6, GPIO_IN);
    gpio_init(7);
    gpio_set_dir(7, GPIO_IN);
    
    adc_init();
    adc_gpio_init(26); // ADC0
    adc_gpio_init(27); // ADC1

    while (true) {
    Tick();
    }
}