#include <stdio.h>
#include "pico/stdlib.h"
#include "hardware/adc.h"
#include "hardware/spi.h"

#define SPI_PORT spi0
#define SCK_PIN  18
#define MOSI_PIN 19
#define CS_PIN   17

int moveInt = 0;

enum movement {START, IDLE};
enum movement stateMove = START;
enum SPIState {SPISTART, TRANSMIT};
enum SPIState state_spi = SPISTART;

void move(enum movement *state) {
    switch (*state) {
        case START:
            *state = IDLE; // FIX 2: Dereference pointer properly
            break;

        case IDLE:
            adc_select_input(0); // Reads GPIO 26
            int value = adc_read();
            
            // FIX 4: Adjusted thresholds to match Pico's 12-bit ADC spectrum (0-4095)
            if (value > 2000) {
                moveInt = 1;
            } else if (value < 2000) {
                moveInt = 2;
            } else {
                moveInt = 0;
            }
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
            gpio_put(CS_PIN, 0); // Pull CS Low to select FPGA receiver
            
            // FIX 3: Cast to 16-bit variable and send exactly 2 bytes (16 bits)
            // uint16_t tx_payload = (uint16_t)moveInt; 
            uint8_t tx_payload = (uint8_t)2; 
            spi_write_blocking(SPI_PORT, (uint8_t*)&tx_payload, 1); 
            
            gpio_put(CS_PIN, 1); // Pull CS High to finish packet transmission
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
    
    // FIX 1: Initialize SPI hardware subsystem
    spi_init(SPI_PORT, 1000000); // 1 MHz communication speed
    gpio_set_function(SCK_PIN, GPIO_FUNC_SPI);
    gpio_set_function(MOSI_PIN, GPIO_FUNC_SPI);
    
    // Configure CS pin manually
    gpio_init(CS_PIN);
    gpio_set_dir(CS_PIN, GPIO_OUT);
    gpio_put(CS_PIN, 1); 

    // Setup input diagnostic pins
    gpio_init(6);
    gpio_set_dir(6, GPIO_IN);
    gpio_init(7);
    gpio_set_dir(7, GPIO_IN);
    
    // Initialize Analog to Digital Converter
    adc_init();
    adc_gpio_init(26); // ADC0
    adc_gpio_init(27); // ADC1

    // Add repeating timer execution loop tracking every 500ms
    //add_repeating_timer_ms(-500, Tick, NULL, &timer);
    while (true) {
    Tick(); // Call Tick once to initialize state
    }
}