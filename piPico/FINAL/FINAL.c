#include <stdio.h>
#include "pico/stdlib.h"
#include "hardware/adc.h"
#include "hardware/spi.h"

#define SPI_PORT spi0
#define SCK_PIN  18
#define MOSI_PIN 19
#define CS_PIN   17
#define JOY_X_ADC_PIN 26   
#define JOY_X_ADC_CH  0
#define FAST_DROP_PB_PIN 12
#define ROTATE_PB_PIN 13  
#define JOY_SW_PIN 15   
#define REST_X 2900 
#define DEADBAND 400

// FPGA control encoding
// 0 = idle, 1 = right, 2 =left, 3 = rotate, 4 =fast drop, 5 =hold
static uint8_t controlByte = 0;

enum movement {START, IDLE};
enum movement stateMove = START;
enum SPIState {SPISTART, TRANSMIT};
enum SPIState state_spi = SPISTART;

static inline bool pressed(uint pin) {
    return gpio_get(pin) == 0;
}

void move(enum movement *state) {
    switch (*state) {
        case START:
            *state = IDLE;
            break;

        case IDLE: {
            adc_select_input(JOY_X_ADC_CH);
            int x = adc_read();

            bool joy_right = (x > REST_X + DEADBAND);
            bool joy_left = (x < REST_X - DEADBAND);

            bool fast_drop_pb = pressed(FAST_DROP_PB_PIN);
            bool rotate_pb = pressed(ROTATE_PB_PIN);
            bool joy_sw = pressed(JOY_SW_PIN);
        

            if (fast_drop_pb) {
                controlByte = 4; // fast drop
            } else if (joy_sw) {
                controlByte = 5; // hold
            } else if (rotate_pb) {
                controlByte = 3; // rotate
            } else if (joy_right && !joy_left) {
                controlByte = 1; // right
            } else if (joy_left && !joy_right) {
                controlByte = 2; // left
            } else {
                controlByte = 0; 
            }

           //debugging
            // printf("x=%d control=%u FD=%d ROT=%d JSW=%d\n", x, controlByte, fast_drop_pb, rotate_pb, joy_sw);
            break;
        }
    }
}

void SPITick(enum SPIState *state) {`
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

    if (*state == TRANSMIT) {
        gpio_put(CS_PIN, 0);
        spi_write_blocking(SPI_PORT, &controlByte, 1);
        gpio_put(CS_PIN, 1);
    }
}

bool Tick(struct repeating_timer *t) {
    move(&stateMove); 
    SPITick(&state_spi);
    return true;
}

int main() {
    stdio_init_all();

    spi_init(SPI_PORT, 1000000);
    gpio_set_function(SCK_PIN, GPIO_FUNC_SPI);
    gpio_set_function(MOSI_PIN, GPIO_FUNC_SPI);

    gpio_init(CS_PIN);
    gpio_set_dir(CS_PIN, GPIO_OUT);
    gpio_put(CS_PIN, 1);

    gpio_init(FAST_DROP_PB_PIN);
    gpio_set_dir(FAST_DROP_PB_PIN, GPIO_IN);
    gpio_pull_up(FAST_DROP_PB_PIN);

    gpio_init(ROTATE_PB_PIN);
    gpio_set_dir(ROTATE_PB_PIN, GPIO_IN);
    gpio_pull_up(ROTATE_PB_PIN);

    gpio_init(JOY_SW_PIN);
    gpio_set_dir(JOY_SW_PIN, GPIO_IN);
    gpio_pull_up(JOY_SW_PIN);

    adc_init();
    adc_gpio_init(JOY_X_ADC_PIN);

    struct repeating_timer timer;
    add_repeating_timer_ms(-20, Tick, NULL, &timer);  
    while (true) {
        tight_loop_contents();
    }
}
