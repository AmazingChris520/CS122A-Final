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
    input  wire [15:0] control,     // (unused in this version, for now)
    input  wire        spi_valid,    // (unused in this version, for now)
    output logic [23:0] pixel       // {R[7:0], G[7:0], B[7:0]}
);

    // -------------------------------------------------------------------------
    // 10 x 20 playfield layout
    // -------------------------------------------------------------------------
    //   Cells are NON-square in raw pixels (16 wide x 20 tall) to compensate
    //   for the monitor stretching 640x480 to its native widescreen ratio --
    //   each cell ends up looking roughly square on screen.
    //   With CELL_W_PX=16, CELL_H_PX=20: playfield = 160 x 400 px, centered
    //   on the 640x480 screen at top-left pixel (240, 40).
    // -------------------------------------------------------------------------
    localparam int FIELD_COLS = 10;                          // 10 columns
    localparam int FIELD_ROWS = 20;                          // 20 rows
    localparam int CELL_W_PX  = 16;                          // cell width px
    localparam int CELL_H_PX  = 20;                          // cell height px
    localparam int FIELD_W    = FIELD_COLS * CELL_W_PX;      // 160 px wide
    localparam int FIELD_H    = FIELD_ROWS * CELL_H_PX;      // 400 px tall
    localparam int FIELD_X0   = (640 - FIELD_W) / 2;         // 240 (centered)
    localparam int FIELD_Y0   = (480 - FIELD_H) / 2;         //  40 (centered)
    localparam int FIELD_X1   = FIELD_X0 + FIELD_W;          // 400
    localparam int FIELD_Y1   = FIELD_Y0 + FIELD_H;          // 440

    // -------------------------------------------------------------------------
    // Playfield border (BORDER_PX-thick ring drawn JUST OUTSIDE the field)
    // -------------------------------------------------------------------------
    localparam int BORDER_PX  = 4;

    // -------------------------------------------------------------------------
    // Drop timing counter
    //   25 MHz / 6_250_000 = 4 Hz, so one drop every 0.25 s.
    //   Raise TICK_MAX to slow it down (25_000_000 = 1 s per cell).
    // -------------------------------------------------------------------------
    localparam int TICK_MAX   = 50_000_000;                   // 2 s per drop

    // -------------------------------------------------------------------------
    // Falling red block state
    //   block_col : 0..9   column in the 10-wide field
    //   block_row : 0..19  row in the 20-tall field (0 = top)
    //   tick_cnt  : counts up to TICK_MAX, then triggers a one-cell drop
    // -------------------------------------------------------------------------
    logic [3:0]  block_col;
    logic [4:0]  block_row;
    logic [23:0] tick_cnt;

    always_ff @(posedge clk) begin
        if (rst) begin
            tick_cnt  <= '0;
            block_col <= 4'd4;                       // spawn near middle column
            block_row <= 5'd0;                       // spawn at top of field
        end else if (tick_cnt == TICK_MAX[23:0]) begin
            tick_cnt <= '0;
            if (block_row == FIELD_ROWS - 1)
                block_row <= 5'd0;                   // wrap back to top
            else
                block_row <= block_row + 5'd1;       // drop one cell
                if (control == 4'd1)
                    block_col <= block_col + 4'd1;   // move right if control=1
                else if (control == -4'd1)
                    block_col <= block_col - 4'd1;   // move left if control=2
        end else begin
            tick_cnt <= tick_cnt + 24'd1;
        end
    end

    // -------------------------------------------------------------------------
    // Map screen pixel -> playfield cell (combinational)
    // -------------------------------------------------------------------------
    wire in_field = (vga_x >= FIELD_X0) && (vga_x < FIELD_X1)
                 && (vga_y >= FIELD_Y0) && (vga_y < FIELD_Y1);

    wire [9:0] rel_x = vga_x - 10'(FIELD_X0);
    wire [9:0] rel_y = vga_y - 10'(FIELD_Y0);

    wire [3:0] cell_col = rel_x / CELL_W_PX;        // 0..9
    wire [4:0] cell_row = rel_y / CELL_H_PX;        // 0..19

    // -------------------------------------------------------------------------
    // Region tests
    // -------------------------------------------------------------------------
    // Border: inside (field + border) rectangle but outside the field itself.
    wire in_border = (vga_x >= FIELD_X0 - BORDER_PX) && (vga_x < FIELD_X1 + BORDER_PX)
                  && (vga_y >= FIELD_Y0 - BORDER_PX) && (vga_y < FIELD_Y1 + BORDER_PX)
                  && !in_field;
 
    // Grid line: 1-px line along the top or left edge of each cell.
    wire on_grid_line = in_field && (((rel_x % CELL_W_PX) == 0)
                                  || ((rel_y % CELL_H_PX) == 0));
 
    // The pixel is inside the cell currently occupied by the block.
    wire in_block = in_field && (cell_col == block_col)
                             && (cell_row == block_row);
 
    wire in_active = (vga_x < 10'd640) && (vga_y < 10'd480);
 
    // -------------------------------------------------------------------------
    // Final pixel color.
    //
    // PRECEDENCE: on_grid_line MUST come before in_block. The dark-green
    // interior of every cell is the area 1 pixel in from the cell's left and
    // top edges (because the grid line lives on those edges). With grid-line
    // precedence the red block fills that same interior region exactly, so
    // it visually aligns with the surrounding empty cells. Putting in_block
    // first would let the block extend over its own left and top grid lines,
    // pushing it one pixel further left/up than where any other cell ends,
    // which reads as a shift.
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
