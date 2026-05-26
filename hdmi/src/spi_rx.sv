module spi_rx (
    input  wire SCK,
    input  wire MOSI,
    input  wire CSN,
    output reg [7:0] data,
    output reg spi_valid
);

    reg [3:0] bit_index;
    reg [15:0] shift_reg;
    reg [15:0] next_shift;
    
    

    initial data = 8'b00000000; // All LEDs on at start
    always @(posedge SCK or posedge CSN) begin
    if (CSN) begin
        bit_index <= 0;
        shift_reg <= 0;
        spi_valid <= 0;
    end else begin
            next_shift = {shift_reg[14:0], MOSI};
            shift_reg <= next_shift;
            if (bit_index == 4'd15) begin
                data <= 8'd2;
                //data <= next_shift; // Capture the full 16 bits of data 
                spi_valid <= 1;
                //led_data = 8'hFF;
                bit_index <= 0;
            end else begin
                spi_valid <= 0;
                data <= 8'd2;
                bit_index <= bit_index + 1;
            end
        end
    end

endmodule