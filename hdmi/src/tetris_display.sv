`default_nettype none

// =============================================================================
// tetris_display
//   Minimal first-step display for a Tetris clone on a 640x480 HDMI output.
//   Renders a 10-column x 20-row playfield with a green border and dim
//   green grid lines, and drops a single red block one cell at a time from
//   the top to the bottom, then resets it to the top and repeats.
//
//   No grid storage: the only state is the block's (col, row) and a drop-
//   tick counter. Pixel color is recomputed combinationally every pixel
//   from those registers and (vga_x, vga_y).
// =============================================================================
module tetris_display(
    input  wire         clk,        // 25 MHz pixel clock
    input  wire         rst,
    input  wire  [9:0]  vga_x,      // 0..799, drawable when < 640
    input  wire  [9:0]  vga_y,      // 0..524, drawable when < 480
    output logic [23:0] pixel       // {R[7:0], G[7:0], B[7:0]}
);

    // -------------------------------------------------------------------------
    // 10 x 20 playfield layout
    // -------------------------------------------------------------------------
    //   CELL_PX     = pixel size of each square cell (cells are CELL_PX x CELL_PX)
    //   FIELD_COLS  = 10  (classic Tetris width)
    //   FIELD_ROWS  = 20  (classic Tetris height)
    //   FIELD_W/H   = full playfield in pixels (200 x 400 with CELL_PX = 20)
    //   FIELD_X0/Y0 = top-left pixel of the playfield, chosen so it's centered
    //                 on the 640x480 screen -> (220, 40)
    //   FIELD_X1/Y1 = one past the bottom-right pixel of the playfield
    // -------------------------------------------------------------------------
    localparam int CELL_W_PX  = 16;
    localparam int CELL_H_PX  = 20;

    localparam int FIELD_W = FIELD_COLS * CELL_W_PX;  // 10 * 16 = 160
    localparam int FIELD_H = FIELD_ROWS * CELL_H_PX;  // 20 * 20 = 400
    //localparam int CELL_PX    = 20;                          // 20 px per cell
    localparam int FIELD_COLS = 10;                          // 10 columns
    localparam int FIELD_ROWS = 20;                          // 20 rows
    //localparam int FIELD_W    = FIELD_COLS * CELL_PX;        // 200 px wide
    //ocalparam int FIELD_H    = FIELD_ROWS * CELL_PX;        // 400 px tall
    localparam int FIELD_X0   = (640 - FIELD_W) / 2;         // 240 (centered)
    localparam int FIELD_Y0   = (480 - FIELD_H) / 2;         //  40 (centered)
    localparam int FIELD_X1   = FIELD_X0 + FIELD_W;          // 400
    localparam int FIELD_Y1   = FIELD_Y0 + FIELD_H;          // 440

    // -------------------------------------------------------------------------
    // Playfield border
    // -------------------------------------------------------------------------
    //   A BORDER_PX-thick ring drawn JUST OUTSIDE the playfield rectangle.
    //   Makes the play area clearly visible against the background.
    // -------------------------------------------------------------------------
    localparam int BORDER_PX  = 4;                           // 4 px border ring

    // -------------------------------------------------------------------------
    // Drop timing counter
    // -------------------------------------------------------------------------
    //   The pixel clock is 25 MHz. To drop the block one cell every 0.25 s,
    //   we count TICK_MAX = 25_000_000 / 4 = 6_250_000 clocks between drops.
    //   - Faster fall: lower TICK_MAX
    //   - Slower fall: raise TICK_MAX (e.g. 25_000_000 for 1 s per cell)
    // -------------------------------------------------------------------------
    localparam int TICK_MAX = 6_250_000;                     // 0.25 s per drop

    // -------------------------------------------------------------------------
    // Falling red block state
    // -------------------------------------------------------------------------
    //   block_col : 0..9  -- column in the 10-wide field (fixed for now)
    //   block_row : 0..19 -- row in the 20-tall field    (increments each tick)
    //   tick_cnt  : counts up to TICK_MAX, then triggers a one-cell drop
    // -------------------------------------------------------------------------
    logic [3:0]  block_col;
    logic [4:0]  block_row;
    logic [22:0] tick_cnt;          // 23 bits is enough for 6_250_000

    always_ff @(posedge clk) begin
        if (rst) begin
            tick_cnt  <= '0;
            block_col <= 4'd4;                       // spawn near middle column
            block_row <= 5'd0;                       // spawn at top of field
        end else if (tick_cnt == TICK_MAX[22:0]) begin
            tick_cnt <= '0;
            // One-cell drop. When we hit the floor, reset to the top and repeat.
            if (block_row == FIELD_ROWS - 1)
                block_row <= 5'd0;
            else
                block_row <= block_row + 5'd1;
        end else begin
            tick_cnt <= tick_cnt + 23'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Map screen pixel -> playfield cell (combinational)
    // -------------------------------------------------------------------------
    wire in_field = (vga_x >= FIELD_X0) && (vga_x < FIELD_X1)
                 && (vga_y >= FIELD_Y0) && (vga_y < FIELD_Y1);

    // Pixel position relative to the field origin (valid only when in_field).
    wire [9:0] rel_x = vga_x - 10'(FIELD_X0);
    wire [9:0] rel_y = vga_y - 10'(FIELD_Y0);

    // Cell that this pixel belongs to.
    wire [3:0] cell_col = rel_x / CELL_W_PX;          // 0..9
    wire [4:0] cell_row = rel_y / CELL_H_PX;          // 0..19

    // -------------------------------------------------------------------------
    // Region tests
    // -------------------------------------------------------------------------
    // Border = inside the (field + border) rectangle but outside the field.
    wire in_border = (vga_x >= FIELD_X0 - BORDER_PX) && (vga_x < FIELD_X1 + BORDER_PX)
                  && (vga_y >= FIELD_Y0 - BORDER_PX) && (vga_y < FIELD_Y1 + BORDER_PX)
                  && !in_field;

    // Grid line = 1-pixel line along the top or left edge of each cell.
    wire on_grid_line = in_field && (((rel_x % CELL_W_PX) == 0)
                                  || ((rel_y % CELL_H_PX) == 0));
    wire [9:0] cell_px_x = rel_x % CELL_W_PX;
    wire [9:0] cell_px_y = rel_y % CELL_H_PX;
    // The pixel falls inside the cell currently occupied by the red block.
    wire in_block = in_field && (cell_col == block_col)
                             && (cell_row == block_row);
    /*wire in_block = in_block_cell
             && (cell_px_x != 0)
             && (cell_px_y != 0);
             */
    // Drawable region of the screen (outside this is HDMI blanking).
    wire in_active = (vga_x < 10'd640) && (vga_y < 10'd480);

    // -------------------------------------------------------------------------
    // Final pixel color. Order matters: block sits on top of grid/field, the
    // grid lines on top of the field interior, the border around it, all on
    // a black background.
    // -------------------------------------------------------------------------
    always_comb begin
        if      (!in_active)    pixel = 24'h000000;  // blanking
        else if (on_grid_line)  pixel = 24'h003300;  // dim green grid lines
        else if (in_block)      pixel = 24'hFF0000;  // red falling block
        else if (in_field)      pixel = 24'h001500;  // very dark green field
        else if (in_border)     pixel = 24'h00FF00;  // bright green border
        else                    pixel = 24'h000000;  // black surround
    end

endmodule