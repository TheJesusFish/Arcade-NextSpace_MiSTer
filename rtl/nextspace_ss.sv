// Save-state controller: sequences the 68000, Z80 and YM3812 and exposes RAMs and registers as save-state chunks
import system_consts::*;

module nextspace_ss (
    input              clk,
    input              reset,
    input              ce_18m,
    input              clk_4m,

    input              do_save,
    input              do_restore,
    input        [1:0] slot,

    output             active,
    output reg         run68,
    output reg         irq7,
    output reg         reset68,
    output reg         hold_z80,
    output reg         reset_z80,
    output reg         dirset,
    output reg [211:0] dir,
    input      [211:0] z80_reg,
    input              z80_m1_n,

    input       [23:1] cpu_a,
    input              cpu_as_n,
    input              cpu_uds_n,
    input              cpu_lds_n,
    input              cpu_rw,
    input        [2:0] cpu_fc,
    input       [15:0] cpu_dout,
    output             ovr,
    output reg  [15:0] ovr_data,

    output             wram_en,
    output      [12:0] wram_addr,
    output      [15:0] wram_d,
    output             wram_we,
    input       [15:0] wram_q,

    output             spr_en,
    output      [12:0] spr_addr,
    output      [15:0] spr_d,
    output             spr_we,
    input       [15:0] spr_q,

    output      [10:0] zram_addr,
    output       [7:0] zram_d,
    output             zram_we,
    input        [7:0] zram_q,

    output       [9:0] zram2_addr,
    output       [7:0] zram2_d,
    output             zram2_we,
    input        [7:0] zram2_q,

    input       [63:0] misc_in,
    output reg  [63:0] misc_out,
    output reg         misc_load,

    input              opl_wr,
    input              opl_a0,
    input        [7:0] opl_d,
    output reg         opl_req,
    output reg         opl_req_a0,
    output reg   [7:0] opl_req_d,

    ddr_if.to_host     ddr
);

localparam int SS_SSP   = 0;
localparam int SS_WRAM  = 1;
localparam int SS_SPR   = 2;
localparam int SS_ZRAM  = 3;
localparam int SS_ZRAM2 = 4;
localparam int SS_Z80   = 5;
localparam int SS_MISC  = 6;
localparam int SS_OPL   = 7;

typedef enum logic [3:0] {
    ST_IDLE,
    ST_SAVE_Z80,
    ST_SAVE_IRQ,
    ST_SAVE_SSP,
    ST_SAVE_WRITE,
    ST_SAVE_EXIT,
    ST_LOAD_READ,
    ST_LOAD_OPL,
    ST_LOAD_Z80,
    ST_LOAD_RESET,
    ST_LOAD_EXIT
} st_t;

st_t st = ST_IDLE;
assign active = st != ST_IDLE;

reg         ss_write = 0;
reg         ss_read = 0;
wire        ss_busy;
reg  [31:0] ssp_saved;
reg  [31:0] ssp_restore;

// save-state stream to DDR3 and its chunk bus
ssbus_if ssbus();
ssbus_if ssb[8]();

ssbus_mux #(.COUNT(8)) ssmux (
    .clk,
    .slave(ssbus),
    .masters(ssb)
);

save_state_data save_state_data (
    .clk,
    .reset,
    .ddr,
    .read_start(ss_read),
    .write_start(ss_write),
    .index(slot),
    .busy(ss_busy),
    .ssbus(ssbus)
);

// 68000 register save / restore handler served at $3F0000 (restore enters at $3F0008)
logic [15:0] handler[16] = '{
    16'h48e7, 16'hfffe,            // movem.l d0-d7/a0-a6,-(a7)
    16'h4e6e,                      // move.l usp,a6
    16'h2f0e,                      // move.l a6,-(a7)
    16'h4df9, 16'h003f, 16'h0000,  // lea $3f0000,a6
    16'h2c8f,                      // move.l a7,(a6)
    16'h2c5f,                      // move.l (a7)+,a6
    16'h4e66,                      // move.l a6,usp
    16'h4cdf, 16'h7fff,            // movem.l (a7)+,d0-d7/a0-a6
    16'h4e73,                      // rte
    16'h0000, 16'h0000, 16'h0000
};

wire handler_hit = cpu_a[23:5] == 19'h1F800;
wire vec7_hit    = cpu_a[23:2] == 22'h00001F;
wire rstvec_hit  = cpu_a[23:3] == 21'h000000;
wire save_side   = (st == ST_SAVE_IRQ) | (st == ST_SAVE_SSP) | (st == ST_SAVE_WRITE) | (st == ST_SAVE_EXIT);
wire load_side   = (st == ST_LOAD_RESET) | (st == ST_LOAD_EXIT);

assign ovr = ~cpu_as_n & cpu_rw & ((active & handler_hit) | (save_side & vec7_hit) | (load_side & rstvec_hit));

always_comb begin
    ovr_data = handler[cpu_a[4:1]];
    if (save_side & vec7_hit) ovr_data = cpu_a[1] ? 16'h0000 : 16'h003f;
    if (load_side & rstvec_hit) begin
        case (cpu_a[2:1])
            2'd0: ovr_data = ssp_restore[31:16];
            2'd1: ovr_data = ssp_restore[15:0];
            2'd2: ovr_data = 16'h003f;
            2'd3: ovr_data = 16'h0008;
        endcase
    end
end

// program fetch outside the handler (and outside the reset vectors)
wire game_fetch = ~cpu_as_n & cpu_rw & (cpu_fc[1:0] == 2'b10) & ~handler_hit & ~rstvec_hit;
wire iack7      = ~cpu_as_n & (cpu_fc == 3'b111) & (cpu_a[3:1] == 3'b111);
wire ssp_wr     = ~cpu_as_n & ~cpu_rw & ~cpu_uds_n & ~cpu_lds_n & (cpu_a[23:2] == 22'h0FC000);

reg         m1_l;
reg  [21:0] tmo;
reg   [5:0] rst_cnt;
reg   [3:0] dir_cnt;

// YM3812 replay: register index, phase (0 select, 1 data, 2 final select), wait counter
reg   [7:0] rp_reg;
reg   [1:0] rp_phase;
reg  [11:0] rp_wait;
reg   [7:0] opl_sel;
reg   [7:0] opl_sh_q;

always_ff @(posedge clk) begin
    m1_l <= z80_m1_n;
    misc_load <= 0;
    if (opl_req & clk_4m) opl_req <= 0;

    if (reset) begin
        st <= ST_IDLE;
        run68 <= 0;
        irq7 <= 0;
        reset68 <= 0;
        hold_z80 <= 0;
        reset_z80 <= 0;
        dirset <= 0;
        ss_write <= 0;
        ss_read <= 0;
        opl_req <= 0;
    end else begin
        case (st)
            ST_IDLE: begin
                run68 <= 0;
                irq7 <= 0;
                reset68 <= 0;
                hold_z80 <= 0;
                reset_z80 <= 0;
                dirset <= 0;
                tmo <= 0;
                if (do_save) begin
                    st <= ST_SAVE_Z80;
                end else if (do_restore) begin
                    hold_z80 <= 1;
                    reset_z80 <= 1;
                    ss_read <= 1;
                    st <= ST_LOAD_READ;
                end
            end

            // 68000 held; Z80 runs to the start of its next opcode fetch, then held
            ST_SAVE_Z80: begin
                tmo <= tmo + 1'd1;
                if (m1_l & ~z80_m1_n) begin
                    hold_z80 <= 1;
                    run68 <= 1;
                    irq7 <= 1;
                    tmo <= 0;
                    st <= ST_SAVE_IRQ;
                end else if (&tmo) begin
                    st <= ST_IDLE;
                end
            end

            // 68000 runs into a level 7 interrupt served by the handler
            ST_SAVE_IRQ: begin
                tmo <= tmo + 1'd1;
                if (iack7) begin
                    irq7 <= 0;
                    st <= ST_SAVE_SSP;
                end else if (&tmo) begin
                    st <= ST_IDLE;
                end
            end

            // handler pushes the registers and writes the supervisor stack pointer to $3F0000
            ST_SAVE_SSP: begin
                if (ssp_wr & ~cpu_a[1]) ssp_saved[31:16] <= cpu_dout;
                if (ssp_wr & cpu_a[1]) begin
                    ssp_saved[15:0] <= cpu_dout;
                    run68 <= 0;
                    ss_write <= 1;
                    st <= ST_SAVE_WRITE;
                end
            end

            ST_SAVE_WRITE: begin
                if (ss_busy & ss_write) begin
                    ss_write <= 0;
                end else if (~ss_busy & ~ss_write) begin
                    run68 <= 1;
                    st <= ST_SAVE_EXIT;
                end
            end

            // handler pops the registers and returns to the game
            ST_SAVE_EXIT: begin
                if (game_fetch) begin
                    run68 <= 0;
                    hold_z80 <= 0;
                    st <= ST_IDLE;
                end
            end

            ST_LOAD_READ: begin
                if (ss_busy & ss_read) begin
                    ss_read <= 0;
                end else if (~ss_busy & ~ss_read) begin
                    rp_reg <= 0;
                    rp_phase <= 0;
                    rp_wait <= 0;
                    st <= ST_LOAD_OPL;
                end
            end

            // replay the YM3812 registers, then reselect the saved register
            ST_LOAD_OPL: begin
                if (rp_wait != 0) begin
                    rp_wait <= rp_wait - 1'd1;
                end else if (~opl_req) begin
                    case (rp_phase)
                        2'd0: begin
                            opl_req <= 1;
                            opl_req_a0 <= 0;
                            opl_req_d <= rp_reg;
                            rp_wait <= 12'd300;
                            rp_phase <= 2'd1;
                        end
                        2'd1: begin
                            opl_req <= 1;
                            opl_req_a0 <= 1;
                            opl_req_d <= opl_sh_q;
                            rp_wait <= 12'd2000;
                            rp_reg <= rp_reg + 1'd1;
                            rp_phase <= (rp_reg == 8'hff) ? 2'd2 : 2'd0;
                        end
                        2'd2: begin
                            opl_req <= 1;
                            opl_req_a0 <= 0;
                            opl_req_d <= opl_sel;
                            rp_wait <= 12'd300;
                            rp_phase <= 2'd3;
                        end
                        2'd3: begin
                            reset_z80 <= 0;
                            dirset <= 1;
                            dir_cnt <= 0;
                            st <= ST_LOAD_Z80;
                        end
                    endcase
                end
            end

            // Z80 out of reset, registers loaded, still held
            ST_LOAD_Z80: begin
                dir_cnt <= dir_cnt + 1'd1;
                if (&dir_cnt) begin
                    dirset <= 0;
                    run68 <= 1;
                    reset68 <= 1;
                    rst_cnt <= 0;
                    st <= ST_LOAD_RESET;
                end
            end

            // 68000 reset with the saved stack pointer and the handler as reset vectors
            ST_LOAD_RESET: begin
                if (ce_18m) begin
                    rst_cnt <= rst_cnt + 1'd1;
                    if (&rst_cnt) begin
                        reset68 <= 0;
                        misc_load <= 1;
                        st <= ST_LOAD_EXIT;
                    end
                end
            end

            ST_LOAD_EXIT: begin
                if (game_fetch) begin
                    run68 <= 0;
                    hold_z80 <= 0;
                    st <= ST_IDLE;
                end
            end

            default: st <= ST_IDLE;
        endcase
    end
end

// chunk 0: supervisor stack pointer (one 64-bit element: every chunk ends on a 64-bit word)
always_ff @(posedge clk) begin
    ssb[SS_SSP].setup(SS_SSP, 1, 3);
    if (ssb[SS_SSP].access(SS_SSP)) begin
        if (ssb[SS_SSP].write) begin
            ssp_restore <= ssb[SS_SSP].data[31:0];
            ssb[SS_SSP].write_ack(SS_SSP);
        end else if (ssb[SS_SSP].read) begin
            ssb[SS_SSP].read_response(SS_SSP, {32'd0, ssp_saved});
        end
    end
end

// chunk 1: work RAM (8K x 16)
assign wram_en   = ssb[SS_WRAM].access(SS_WRAM);
assign wram_addr = ssb[SS_WRAM].addr[12:0];
assign wram_d    = ssb[SS_WRAM].data[15:0];
assign wram_we   = wram_en & ssb[SS_WRAM].write;

reg wram_rd_dly;
always_ff @(posedge clk) begin
    ssb[SS_WRAM].setup(SS_WRAM, 8192, 1);
    if (ssb[SS_WRAM].access(SS_WRAM)) begin
        if (ssb[SS_WRAM].write) begin
            ssb[SS_WRAM].write_ack(SS_WRAM);
        end else if (ssb[SS_WRAM].read) begin
            if (wram_rd_dly) ssb[SS_WRAM].read_response(SS_WRAM, {48'd0, wram_q});
            wram_rd_dly <= 1;
        end
    end else begin
        wram_rd_dly <= 0;
    end
end

// chunk 2: sprite RAM, the 8K x 16 the 68000 can address
assign spr_en   = ssb[SS_SPR].access(SS_SPR);
assign spr_addr = ssb[SS_SPR].addr[12:0];
assign spr_d    = ssb[SS_SPR].data[15:0];
assign spr_we   = spr_en & ssb[SS_SPR].write;

reg spr_rd_dly;
always_ff @(posedge clk) begin
    ssb[SS_SPR].setup(SS_SPR, 8192, 1);
    if (ssb[SS_SPR].access(SS_SPR)) begin
        if (ssb[SS_SPR].write) begin
            ssb[SS_SPR].write_ack(SS_SPR);
        end else if (ssb[SS_SPR].read) begin
            if (spr_rd_dly) ssb[SS_SPR].read_response(SS_SPR, {48'd0, spr_q});
            spr_rd_dly <= 1;
        end
    end else begin
        spr_rd_dly <= 0;
    end
end

// chunk 3: Z80 RAM (2K x 8)
assign zram_addr = ssb[SS_ZRAM].addr[10:0];
assign zram_d    = ssb[SS_ZRAM].data[7:0];
assign zram_we   = ssb[SS_ZRAM].access(SS_ZRAM) & ssb[SS_ZRAM].write;

reg zram_rd_dly;
always_ff @(posedge clk) begin
    ssb[SS_ZRAM].setup(SS_ZRAM, 2048, 0);
    if (ssb[SS_ZRAM].access(SS_ZRAM)) begin
        if (ssb[SS_ZRAM].write) begin
            ssb[SS_ZRAM].write_ack(SS_ZRAM);
        end else if (ssb[SS_ZRAM].read) begin
            if (zram_rd_dly) ssb[SS_ZRAM].read_response(SS_ZRAM, {56'd0, zram_q});
            zram_rd_dly <= 1;
        end
    end else begin
        zram_rd_dly <= 0;
    end
end

// chunk 4: Z80 RAM2 (1K x 8)
assign zram2_addr = ssb[SS_ZRAM2].addr[9:0];
assign zram2_d    = ssb[SS_ZRAM2].data[7:0];
assign zram2_we   = ssb[SS_ZRAM2].access(SS_ZRAM2) & ssb[SS_ZRAM2].write;

reg zram2_rd_dly;
always_ff @(posedge clk) begin
    ssb[SS_ZRAM2].setup(SS_ZRAM2, 1024, 0);
    if (ssb[SS_ZRAM2].access(SS_ZRAM2)) begin
        if (ssb[SS_ZRAM2].write) begin
            ssb[SS_ZRAM2].write_ack(SS_ZRAM2);
        end else if (ssb[SS_ZRAM2].read) begin
            if (zram2_rd_dly) ssb[SS_ZRAM2].read_response(SS_ZRAM2, {56'd0, zram2_q});
            zram2_rd_dly <= 1;
        end
    end else begin
        zram2_rd_dly <= 0;
    end
end

// chunk 5: T80 registers (212 bits in 4 x 64)
wire [255:0] z80_reg_w = {44'd0, z80_reg};
always_ff @(posedge clk) begin
    ssb[SS_Z80].setup(SS_Z80, 4, 3);
    if (ssb[SS_Z80].access(SS_Z80)) begin
        if (ssb[SS_Z80].write) begin
            case (ssb[SS_Z80].addr[1:0])
                2'd0: dir[63:0]    <= ssb[SS_Z80].data;
                2'd1: dir[127:64]  <= ssb[SS_Z80].data;
                2'd2: dir[191:128] <= ssb[SS_Z80].data;
                2'd3: dir[211:192] <= ssb[SS_Z80].data[19:0];
            endcase
            ssb[SS_Z80].write_ack(SS_Z80);
        end else if (ssb[SS_Z80].read) begin
            ssb[SS_Z80].read_response(SS_Z80, z80_reg_w[ssb[SS_Z80].addr[1:0] * 64 +: 64]);
        end
    end
end

// chunk 6: board registers
always_ff @(posedge clk) begin
    ssb[SS_MISC].setup(SS_MISC, 1, 3);
    if (ssb[SS_MISC].access(SS_MISC)) begin
        if (ssb[SS_MISC].write) begin
            misc_out <= ssb[SS_MISC].data;
            ssb[SS_MISC].write_ack(SS_MISC);
        end else if (ssb[SS_MISC].read) begin
            ssb[SS_MISC].read_response(SS_MISC, misc_in);
        end
    end
end

// chunk 7: YM3812 register shadow (256 registers, the selected register, padding to 264)
reg  [7:0] opl_sh[256];
wire       opl_ss_acc = ssb[SS_OPL].access(SS_OPL);
wire       opl_ss_wr  = opl_ss_acc & ssb[SS_OPL].write & ~ssb[SS_OPL].addr[8];
wire       opl_snoop  = ~active & clk_4m & opl_wr & opl_a0;
wire [7:0] opl_sh_rd_a = (st == ST_LOAD_OPL) ? rp_reg : ssb[SS_OPL].addr[7:0];

always_ff @(posedge clk) begin
    if (opl_ss_wr | opl_snoop) opl_sh[opl_ss_wr ? ssb[SS_OPL].addr[7:0] : opl_sel] <= opl_ss_wr ? ssb[SS_OPL].data[7:0] : opl_d;
    opl_sh_q <= opl_sh[opl_sh_rd_a];
end

reg opl_rd_dly;
always_ff @(posedge clk) begin
    if (~active & clk_4m & opl_wr & ~opl_a0) opl_sel <= opl_d;

    ssb[SS_OPL].setup(SS_OPL, 264, 0);
    if (opl_ss_acc) begin
        if (ssb[SS_OPL].write) begin
            if (ssb[SS_OPL].addr[8:0] == 9'h100) opl_sel <= ssb[SS_OPL].data[7:0];
            ssb[SS_OPL].write_ack(SS_OPL);
        end else if (ssb[SS_OPL].read) begin
            if (opl_rd_dly) ssb[SS_OPL].read_response(SS_OPL, {56'd0, (ssb[SS_OPL].addr[8:0] == 9'h100) ? opl_sel : ssb[SS_OPL].addr[8] ? 8'h00 : opl_sh_q});
            opl_rd_dly <= 1;
        end
    end else begin
        opl_rd_dly <= 0;
    end
end

endmodule
