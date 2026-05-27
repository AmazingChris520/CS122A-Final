`default_nettype none

// =============================================================================
// tetris_display
//   10 x 20 Tetris-style playfield with a single falling red block, plus
//   left/right movement driven by an external 8-bit `control` byte.
//
//   control encoding (one drop-tick worth of action):
//     8'd1  -> move block one column to the right
//     8'd2  -> move block one column to the left
//     anything else -> no horizontal movement this tick
//
//   Horizontal movement is CLAMPED to the playfield, i.e. the block never
//   leaves columns 0..FIELD_COLS-1. Vertical movement still wraps to the
//   top of the field when it reaches the bottom.
// =============================================================================
module tetris_display(
    input  wire         clk,
    input  wire         rst,
    input  wire  [9:0]  vga_x,
    input  wire  [9:0]  vga_y,
    input  wire  [7:0]  control,
    input  wire         spi_valid,    // (unused for now)
    output logic [23:0] pixel
);

    // -------------------------------------------------------------------------
    // 10 x 20 playfield layout (16 px wide x 20 px tall cells, centered)
    // -------------------------------------------------------------------------
    localparam int FIELD_COLS = 10;
    localparam int FIELD_ROWS = 20;
    localparam int CELL_W_PX  = 16;
    localparam int CELL_H_PX  = 20;
    localparam int FIELD_W    = FIELD_COLS * CELL_W_PX;
    localparam int FIELD_H    = FIELD_ROWS * CELL_H_PX;
    localparam int FIELD_X0   = (640 - FIELD_W) / 2;
    localparam int FIELD_Y0   = (480 - FIELD_H) / 2;
    localparam int FIELD_X1   = FIELD_X0 + FIELD_W;
    localparam int FIELD_Y1   = FIELD_Y0 + FIELD_H;
    localparam int BORDER_PX  = 4;

    // 2 s per cell drop. Lower this for a faster fall.
    localparam int TICK_MAX   = 50_000_000;

    // -------------------------------------------------------------------------
    // Block + tick state
    // -------------------------------------------------------------------------
    logic [3:0]  block_col;     // 0..9
    logic [4:0]  block_row;     // 0..19
    logic [23:0] tick_cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            tick_cnt  <= '0;
            block_col <= 4'd4;
            block_row <= 5'd0;
        end else if (tick_cnt == TICK_MAX[23:0]) begin
            tick_cnt <= '0;

            // ----- Vertical drop (still wraps to top for visual loop) -----
            if (block_row == FIELD_ROWS - 1)
                block_row <= 5'd0;
            else
                block_row <= block_row + 5'd1;

            // ----- Horizontal move, CLAMPED to [0, FIELD_COLS-1] ---------
            // No subtraction/addition happens at the boundary, so the
            // 4-bit counter can never underflow to 4'd15 or overflow past
            // 4'd9. The block stays put at the edges.
            if (control == 8'd1) begin
                if (block_col < FIELD_COLS - 1)         // not yet at right edge
                    block_col <= block_col + 4'd1;
                // else: clamp -- block_col stays at 9
            end else if (control == 8'd2) begin
                if (block_col > 4'd0)                   // not yet at left edge
                    block_col <= block_col - 4'd1;
                // else: clamp -- block_col stays at 0
            end
        end else begin
            tick_cnt <= tick_cnt + 24'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Pixel-to-cell mapping (combinational)
    // -------------------------------------------------------------------------
    wire in_field = (vga_x >= FIELD_X0) && (vga_x < FIELD_X1)
                 && (vga_y >= FIELD_Y0) && (vga_y < FIELD_Y1);

    wire [9:0] rel_x = vga_x - 10'(FIELD_X0);
    wire [9:0] rel_y = vga_y - 10'(FIELD_Y0);

    wire [3:0] cell_col = rel_x / CELL_W_PX;
    wire [4:0] cell_row = rel_y / CELL_H_PX;

    wire in_border = (vga_x >= FIELD_X0 - BORDER_PX) && (vga_x < FIELD_X1 + BORDER_PX)
                  && (vga_y >= FIELD_Y0 - BORDER_PX) && (vga_y < FIELD_Y1 + BORDER_PX)
                  && !in_field;

    wire on_grid_line = in_field && (((rel_x % CELL_W_PX) == 0)
                                  || ((rel_y % CELL_H_PX) == 0));

    wire in_block = in_field && (cell_col == block_col)
                             && (cell_row == block_row);

    wire in_active = (vga_x < 10'd640) && (vga_y < 10'd480);

    always_comb begin
        if      (!in_active)    pixel = 24'h000000;
        else if (on_grid_line)  pixel = 24'h003300;
        else if (in_block)      pixel = 24'hFF0000;
        else if (in_field)      pixel = 24'h001500;
        else if (in_border)     pixel = 24'h00FF00;
        else                    pixel = 24'h000000;
    end

endmodule