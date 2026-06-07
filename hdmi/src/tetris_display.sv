`default_nettype none

// =============================================================================
// tetris_display
//   10 x 20 playfield with real 4-cell Tetris tetrominoes.
//     - VGA playfield layout
//     - locked-cell stack rendering
//     - left/right control from the 8-bit `control` byte
//     - gravity drop timing
//     - 0.5 s lock delay
//     - row clearing
//
//   control encoding:
//     8'd1 -> move right one column
//     8'd2 -> move left  one column
//     8'd3 -> rotate clockwise
//     8'd4 -> fast drop while held
//   Notes:
//     - The active piece is drawn red.
//     - Locked cells are drawn grey.
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

    // 10 x 20 playfield layout (16 px wide x 20 px tall cells, centered)
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

    // -------------------------------------------------------------------------
    // Timing (25 MHz clock)
    // -------------------------------------------------------------------------
    localparam int FALL_TICKS      = 25_000_000;   // 1.0 s per normal row drop
    localparam int MOVE_TICKS      =  3_750_000;   // 150 ms between L/R/rotate steps
    localparam int FAST_DROP_TICKS =  1_250_000;   // 50 ms between fast-drop rows
    localparam int LOCK_TICKS      = 12_500_000;   // 0.5 s lock delay

    // -------------------------------------------------------------------------
    // FSM state
    // -------------------------------------------------------------------------
    localparam logic [1:0] S_FALLING = 2'd0,
                           S_LOCKING = 2'd1,
                           S_SPAWN   = 2'd2,
                           S_CLEAR   = 2'd3;
    logic [1:0] state;

    // -------------------------------------------------------------------------
    // Tetromino encoding
    // -------------------------------------------------------------------------
    localparam logic [2:0] P_I = 3'd0,
                           P_O = 3'd1,
                           P_T = 3'd2,
                           P_S = 3'd3,
                           P_Z = 3'd4,
                           P_J = 3'd5,
                           P_L = 3'd6;

    // piece_row/piece_col are the top-left corner of a 4x4 piece box.
    logic [3:0]  piece_col;     // 0..9, but valid piece placement depends on shape width
    logic [4:0]  piece_row;     // 0..19, but valid piece placement depends on shape height
    logic [2:0]  piece_type;    // I, O, T, S, Z, J, L
    logic [1:0]  piece_rot;     // 0, 1, 2, 3 clockwise rotation states

    // 8-bit LFSR used to choose the next piece.
    // It free-runs while the game runs, so player timing affects the sequence.
    logic [7:0]  lfsr;

    logic [24:0] fall_cnt;
    logic [23:0] lock_cnt;
    logic [21:0] move_cnt;
    logic [20:0] fast_cnt;
    logic [4:0]  clear_row;     // bottom-up scan index during S_CLEAR

    // board[r][c] = 1 -> a locked block occupies cell (r, c)
    logic [FIELD_COLS-1:0] board [FIELD_ROWS-1:0];

    integer i, j;

    // -------------------------------------------------------------------------
    // Pseudo-random piece selection.
    // Maps the lower 3 LFSR bits to one of the 7 tetrominoes.
    // 3'd7 is mapped to T, so this is simple pseudo-random selection, not 7-bag.
    // -------------------------------------------------------------------------
    function automatic logic [2:0] random_piece(input logic [7:0] rnd);
        begin
            case (rnd[2:0])
                3'd0: random_piece = P_I;
                3'd1: random_piece = P_O;
                3'd2: random_piece = P_T;
                3'd3: random_piece = P_S;
                3'd4: random_piece = P_Z;
                3'd5: random_piece = P_J;
                3'd6: random_piece = P_L;
                default: random_piece = P_T;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Shape lookup.
    // Returns 1 when local cell (r, c) inside the 4x4 box is occupied.
    // -------------------------------------------------------------------------
    function automatic logic piece_cell(
        input logic [2:0] ptype,
        input logic [1:0] rot,
        input int r,
        input int c
    );
        begin
            piece_cell = 1'b0;

            case (ptype)
                // I piece
                P_I: begin
                    if (rot[0] == 1'b0)
                        piece_cell = (r == 1) && (c >= 0) && (c <= 3);
                    else
                        piece_cell = (c == 2) && (r >= 0) && (r <= 3);
                end

                // O piece
                P_O: begin
                    piece_cell = ((r == 0) || (r == 1)) &&
                                 ((c == 1) || (c == 2));
                end

                // T piece
                P_T: begin
                    case (rot)
                        2'd0: piece_cell = ((r == 0) && (c == 1)) ||
                                            ((r == 1) && (c >= 0) && (c <= 2));
                        2'd1: piece_cell = ((c == 1) && (r >= 0) && (r <= 2)) ||
                                            ((r == 1) && (c == 2));
                        2'd2: piece_cell = ((r == 1) && (c >= 0) && (c <= 2)) ||
                                            ((r == 2) && (c == 1));
                        2'd3: piece_cell = ((c == 1) && (r >= 0) && (r <= 2)) ||
                                            ((r == 1) && (c == 0));
                    endcase
                end

                // S piece
                P_S: begin
                    if (rot[0] == 1'b0)
                        piece_cell = ((r == 0) && ((c == 1) || (c == 2))) ||
                                     ((r == 1) && ((c == 0) || (c == 1)));
                    else
                        piece_cell = ((c == 1) && ((r == 0) || (r == 1))) ||
                                     ((c == 2) && ((r == 1) || (r == 2)));
                end

                // Z piece
                P_Z: begin
                    if (rot[0] == 1'b0)
                        piece_cell = ((r == 0) && ((c == 0) || (c == 1))) ||
                                     ((r == 1) && ((c == 1) || (c == 2)));
                    else
                        piece_cell = ((c == 2) && ((r == 0) || (r == 1))) ||
                                     ((c == 1) && ((r == 1) || (r == 2)));
                end

                // J piece
                P_J: begin
                    case (rot)
                        2'd0: piece_cell = ((r == 0) && (c == 0)) ||
                                            ((r == 1) && (c >= 0) && (c <= 2));
                        2'd1: piece_cell = ((r == 0) && ((c == 1) || (c == 2))) ||
                                            ((c == 1) && (r >= 1) && (r <= 2));
                        2'd2: piece_cell = ((r == 1) && (c >= 0) && (c <= 2)) ||
                                            ((r == 2) && (c == 2));
                        2'd3: piece_cell = ((c == 1) && (r >= 0) && (r <= 1)) ||
                                            ((r == 2) && ((c == 0) || (c == 1)));
                    endcase
                end

                // L piece
                P_L: begin
                    case (rot)
                        2'd0: piece_cell = ((r == 0) && (c == 2)) ||
                                            ((r == 1) && (c >= 0) && (c <= 2));
                        2'd1: piece_cell = ((c == 1) && (r >= 0) && (r <= 1)) ||
                                            ((r == 2) && ((c == 1) || (c == 2)));
                        2'd2: piece_cell = ((r == 1) && (c >= 0) && (c <= 2)) ||
                                            ((r == 2) && (c == 0));
                        2'd3: piece_cell = ((r == 0) && ((c == 0) || (c == 1))) ||
                                            ((c == 1) && (r >= 1) && (r <= 2));
                    endcase
                end

                default: piece_cell = 1'b0;
            endcase
        end
    endfunction

    // -------------------------------------------------------------------------
    // Placement check.
    // Returns 1 only if all 4 cells are inside the board and not overlapping
    // locked cells.
    // -------------------------------------------------------------------------
    function automatic logic piece_valid(
        input logic [4:0] test_row,
        input logic [3:0] test_col,
        input logic [2:0] test_type,
        input logic [1:0] test_rot
    );
        int rr, cc;
        int abs_r, abs_c;
        begin
            piece_valid = 1'b1;

            for (rr = 0; rr < 4; rr = rr + 1) begin
                for (cc = 0; cc < 4; cc = cc + 1) begin
                    if (piece_cell(test_type, test_rot, rr, cc)) begin
                        abs_r = test_row + rr;
                        abs_c = test_col + cc;

                        if ((abs_r < 0) || (abs_r >= FIELD_ROWS) ||
                            (abs_c < 0) || (abs_c >= FIELD_COLS)) begin
                            piece_valid = 1'b0;
                        end else if (board[abs_r][abs_c]) begin
                            piece_valid = 1'b0;
                        end
                    end
                end
            end
        end
    endfunction

    initial begin
        state      = S_SPAWN;
        piece_col  = 4'd3;
        piece_row  = 5'd0;
        piece_type = P_I;
        piece_rot  = 2'd0;
        lfsr       = 8'hA5;
        fall_cnt   = '0;
        lock_cnt   = '0;
        move_cnt   = '0;
        fast_cnt   = '0;
        clear_row  = '0;
        for (i = 0; i < FIELD_ROWS; i = i + 1)
            board[i] = '0;
    end

    // -------------------------------------------------------------------------
    // Collision and movement checks
    // -------------------------------------------------------------------------
    wire [1:0] rot_next       = piece_rot + 2'd1;
    wire       can_fall       = piece_valid(piece_row + 5'd1, piece_col, piece_type, piece_rot);
    wire       is_landed      = !can_fall;
    wire       can_move_right = piece_valid(piece_row, piece_col + 4'd1, piece_type, piece_rot);
    wire       can_move_left  = (piece_col > 4'd0) &&
                                piece_valid(piece_row, piece_col - 4'd1, piece_type, piece_rot);
    wire       can_rotate     = piece_valid(piece_row, piece_col, piece_type, rot_next);

    // -------------------------------------------------------------------------
    // Main FSM
    // -------------------------------------------------------------------------
    always_ff @(posedge clk) begin
        if (rst) begin
            state      <= S_SPAWN;
            piece_col  <= 4'd3;
            piece_row  <= 5'd0;
            piece_type <= P_I;
            piece_rot  <= 2'd0;
            lfsr       <= 8'hA5;
            fall_cnt   <= '0;
            lock_cnt   <= '0;
            move_cnt   <= '0;
            fast_cnt   <= '0;
            clear_row  <= '0;
            for (i = 0; i < FIELD_ROWS; i = i + 1)
                board[i] <= '0;
        end else begin
            // Free-running LFSR: x^8 + x^6 + x^5 + x^4 + 1 taps.
            // Seed must never be zero.
            lfsr     <= {lfsr[6:0], lfsr[7] ^ lfsr[5] ^ lfsr[4] ^ lfsr[3]};
            fall_cnt <= fall_cnt + 25'd1;
            move_cnt <= move_cnt + 22'd1;

            // GP12 fast drop command. Reset the counter when the button is not held
            // so the next press gets an immediate first drop.
            if (control == 8'd4)
                fast_cnt <= fast_cnt + 21'd1;
            else
                fast_cnt <= '0;

            case (state)

                // ----- Falling ------------------------------------------------
                S_FALLING: begin
                    // Horizontal move / rotate at its own cadence.
                    if (move_cnt == MOVE_TICKS[21:0]) begin
                        move_cnt <= '0;
                        if      (control == 8'd1 && can_move_right) piece_col <= piece_col + 4'd1;
                        else if (control == 8'd2 && can_move_left)  piece_col <= piece_col - 4'd1;
                        else if (control == 8'd3 && can_rotate)     piece_rot <= rot_next;
                    end

                    // Fast drop from GP12. It drops immediately on press, then
                    // repeats every FAST_DROP_TICKS while the button is held.
                    if ((control == 8'd4) &&
                        ((fast_cnt == 21'd0) || (fast_cnt == FAST_DROP_TICKS[20:0]))) begin
                        fast_cnt <= 21'd1;
                        fall_cnt <= '0;
                        if (can_fall)
                            piece_row <= piece_row + 5'd1;
                    end

                    // Gravity drop.
                    if (fall_cnt == FALL_TICKS[24:0]) begin
                        fall_cnt <= '0;
                        if (can_fall)
                            piece_row <= piece_row + 5'd1;
                    end

                    // Start lock timer as soon as the piece is supported.
                    if (is_landed) begin
                        lock_cnt <= '0;
                        state    <= S_LOCKING;
                    end
                end

                // ----- Locking (0.5 s; L/R/rotate still active) ---------------
                S_LOCKING: begin
                    if (move_cnt == MOVE_TICKS[21:0]) begin
                        move_cnt <= '0;
                        if      (control == 8'd1 && can_move_right) piece_col <= piece_col + 4'd1;
                        else if (control == 8'd2 && can_move_left)  piece_col <= piece_col - 4'd1;
                        else if (control == 8'd3 && can_rotate)     piece_rot <= rot_next;
                    end

                    // If a move/rotate made the piece unsupported again, fast drop can
                    // pull it downward before the FSM returns to falling.
                    if ((control == 8'd4) && !is_landed &&
                        ((fast_cnt == 21'd0) || (fast_cnt == FAST_DROP_TICKS[20:0]))) begin
                        fast_cnt <= 21'd1;
                        fall_cnt <= '0;
                        if (can_fall)
                            piece_row <= piece_row + 5'd1;
                    end

                    if (!is_landed) begin
                        // Slid or rotated off support -> resume falling, cancel timer.
                        state    <= S_FALLING;
                        fall_cnt <= '0;
                    end else begin
                        lock_cnt <= lock_cnt + 24'd1;
                        if (lock_cnt == LOCK_TICKS[23:0]) begin
                            // Commit all 4 occupied cells of the active piece.
                            for (i = 0; i < 4; i = i + 1) begin
                                for (j = 0; j < 4; j = j + 1) begin
                                    if (piece_cell(piece_type, piece_rot, i, j)) begin
                                        board[piece_row + i[4:0]][piece_col + j[3:0]] <= 1'b1;
                                    end
                                end
                            end

                            // Row clear happens before the next random spawn.
                            clear_row <= FIELD_ROWS - 1;
                            state     <= S_CLEAR;
                        end
                    end
                end

                // ----- Clear full rows, bottom-up -----------------------------
                S_CLEAR: begin
                    if (&board[clear_row]) begin
                        // Full row: shift everything at/above it down by one,
                        // then re-check the same index next cycle.
                        for (j = FIELD_ROWS - 1; j > 0; j = j - 1)
                            if (j[4:0] <= clear_row)
                                board[j] <= board[j-1];
                        board[0] <= '0;
                    end else if (clear_row == 5'd0) begin
                        state <= S_SPAWN;
                    end else begin
                        clear_row <= clear_row - 5'd1;
                    end
                end

                // ----- Spawn the next random piece ---------------------------
                S_SPAWN: begin
                    piece_col  <= 4'd3;
                    piece_row  <= 5'd0;
                    piece_type <= random_piece(lfsr);
                    piece_rot  <= 2'd0;
                    fall_cnt  <= '0;
                    lock_cnt  <= '0;
                    move_cnt  <= '0;
                    fast_cnt  <= '0;
                    state     <= S_FALLING;
                end

                default: state <= S_SPAWN;

            endcase
        end
    end

    // -------------------------------------------------------------------------
    // Pixel-to-cell mapping
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

    logic in_block;
    logic in_stack;

    always_comb begin
        in_block = 1'b0;
        in_stack = 1'b0;

        if (in_field) begin
            // Locked cells already committed to the board.
            in_stack = board[cell_row][cell_col];

            // Active tetromino cell check. The piece lives in a 4x4 local box.
            if ((cell_row >= piece_row) && (cell_row < piece_row + 5'd4) &&
                (cell_col >= piece_col) && (cell_col < piece_col + 4'd4)) begin
                in_block = piece_cell(piece_type, piece_rot,
                                      cell_row - piece_row,
                                      cell_col - piece_col);
            end
        end
    end

    wire in_active = (vga_x < 10'd640) && (vga_y < 10'd480);

    always_comb begin
        if      (!in_active)    pixel = 24'h000000;
        else if (on_grid_line)  pixel = 24'h003300;
        else if (in_block)      pixel = 24'hFF0000;   // active tetromino (red)
        else if (in_stack)      pixel = 24'hAAAAAA;   // locked cells (grey)
        else if (in_field)      pixel = 24'h001500;
        else if (in_border)     pixel = 24'h00FF00;
        else                    pixel = 24'h000000;
    end

endmodule
