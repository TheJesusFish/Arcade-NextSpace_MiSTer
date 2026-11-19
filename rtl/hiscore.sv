// High-score keeper: MAME hiscore.dat entries (ioctl index 3) and the saved table (index 4, nvram upload) in 68000 work RAM
module hiscore (
    input             clk,
    input             reset,
    input             vblank,

    input             ioctl_download,
    input             ioctl_upload,
    input             ioctl_wr,
    input      [26:0] ioctl_addr,
    input       [7:0] ioctl_dout,
    input      [15:0] ioctl_index,
    output reg  [7:0] ioctl_din,
    output reg        upload_req,

    input             osd_open,
    input             autosave,
    input             save_now,
    output            present,

    input             ram_busy,
    output     [12:0] ram_addr,
    output      [7:0] ram_d,
    output            ram_we_h,
    output            ram_we_l,
    input      [15:0] ram_q
);

// up to four entries: address[4], length[2], start byte, end byte
reg  [7:0] ent[32];
reg  [2:0] n_ent = 0;
reg  [7:0] tbl[256];
reg        tbl_loaded = 0;

wire dl_ent = ioctl_download & (ioctl_index == 16'd3);
wire dl_tbl = ioctl_download & (ioctl_index == 16'd4);
wire ul_tbl = ioctl_upload & (ioctl_index == 16'd4);

assign present = n_ent != 0;

wire [13:0] e_addr[4];
wire  [8:0] e_len[4];
wire  [8:0] e_off[5];
assign e_off[0] = 9'd0;
genvar g;
generate
    for (g = 0; g < 4; g = g + 1) begin : gen_ent
        assign e_addr[g]  = {ent[g*8+2][5:0], ent[g*8+3]};
        assign e_len[g]   = (g < n_ent) ? {ent[g*8+4][0], ent[g*8+5]} : 9'd0;
        assign e_off[g+1] = e_off[g] + e_len[g];
    end
endgenerate
wire [8:0] tbl_len = e_off[4];

// work RAM byte address of table offset o
function automatic [13:0] tbl_addr(input [8:0] o);
    begin
        if (o < e_off[1])      tbl_addr = e_addr[0] + o;
        else if (o < e_off[2]) tbl_addr = e_addr[1] + (o - e_off[1]);
        else if (o < e_off[3]) tbl_addr = e_addr[2] + (o - e_off[2]);
        else                   tbl_addr = e_addr[3] + (o - e_off[3]);
    end
endfunction

always_ff @(posedge clk) begin
    if (dl_ent & ioctl_wr & ~|ioctl_addr[26:5]) begin
        ent[ioctl_addr[4:0]] <= ioctl_dout;
        if (ioctl_addr[2:0] == 3'd7) n_ent <= ioctl_addr[4:3] + 1'd1;
    end
    if (dl_tbl & ioctl_wr & ~|ioctl_addr[26:8]) begin
        tbl[ioctl_addr[7:0]] <= ioctl_dout;
        tbl_loaded <= 1;
    end
end

// check / restore sequencer
typedef enum logic [2:0] { H_WAIT, H_CHECK, H_READ, H_CMP, H_FETCH, H_WRITE, H_DONE } hst_t;
hst_t hst = H_WAIT;

reg  [5:0] frames;
reg        vbl_l;
reg  [1:0] ck_ent;
reg        ck_end;
reg  [8:0] wr_off;
reg [13:0] cur_addr;
reg        table_ok;
reg  [1:0] rd_dly;
reg  [7:0] tbl_q;

wire [13:0] ck_addr  = e_addr[ck_ent] + (ck_end ? e_len[ck_ent] - 1'd1 : 9'd0);
wire  [7:0] ck_want  = ent[{ck_ent, 3'd0} + (ck_end ? 5'd7 : 5'd6)];
wire  [7:0] ram_byte = cur_addr[0] ? ram_q[7:0] : ram_q[15:8];
wire [13:0] wr_addr  = tbl_addr(wr_off);
wire        wr_go    = (hst == H_WRITE) & ~ram_busy;

assign ram_addr = (hst == H_WRITE) ? wr_addr[13:1] : cur_addr[13:1];
assign ram_d    = tbl_q;
assign ram_we_h = wr_go & ~wr_addr[0];
assign ram_we_l = wr_go & wr_addr[0];

always_ff @(posedge clk) begin
    vbl_l <= vblank;
    tbl_q <= tbl[wr_off[7:0]];

    if (reset | ioctl_download) begin
        hst <= H_WAIT;
        frames <= 0;
        table_ok <= 0;
    end else begin
        case (hst)
            H_WAIT: if (vblank & ~vbl_l & present) begin
                frames <= frames + 1'd1;
                if (frames == 6'd30) hst <= H_CHECK;
            end

            H_CHECK: if (vblank & ~vbl_l) begin
                ck_ent <= 0;
                ck_end <= 0;
                hst <= H_READ;
            end

            H_READ: begin
                cur_addr <= ck_addr;
                rd_dly <= 0;
                hst <= H_CMP;
            end

            H_CMP: begin
                rd_dly <= rd_dly + 1'd1;
                if (rd_dly == 2'd2) begin
                    if (ram_byte != ck_want) begin
                        hst <= H_CHECK;
                    end else if (~ck_end) begin
                        ck_end <= 1;
                        hst <= H_READ;
                    end else if ({1'b0, ck_ent} + 3'd1 < n_ent) begin
                        ck_ent <= ck_ent + 1'd1;
                        ck_end <= 0;
                        hst <= H_READ;
                    end else begin
                        table_ok <= 1;
                        wr_off <= 0;
                        hst <= tbl_loaded ? H_FETCH : H_DONE;
                    end
                end
            end

            // saved table into work RAM, one byte at a time while the 68000 is not on work RAM
            H_FETCH: hst <= (wr_off == tbl_len) ? H_DONE : H_WRITE;

            H_WRITE: if (wr_go) begin
                wr_off <= wr_off + 1'd1;
                hst <= H_FETCH;
            end

            default: ;
        endcase

        // nvram upload reads the live table
        if (ul_tbl) cur_addr <= tbl_addr(ioctl_addr[8:0]);
    end
end

always_ff @(posedge clk) ioctl_din <= ram_byte;

// request a save when the OSD opens (autosave) or on the OSD action, once the table is valid
reg osd_l, save_l;
always_ff @(posedge clk) begin
    osd_l <= osd_open;
    save_l <= save_now;
    upload_req <= table_ok & ((autosave & osd_open & ~osd_l) | (save_now & ~save_l));
end

endmodule
