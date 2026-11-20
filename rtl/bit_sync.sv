// Two-flop synchronizer for an asynchronous level into the clk domain
module bit_sync (
    input      clk,
    input      d,
    output     q
);

(* useioff = 0 *)
(* preserve *)
(* altera_attribute = "-name SYNCHRONIZER_IDENTIFICATION \"FORCED IF ASYNCHRONOUS\"" *)
reg [1:0] sync = 2'b00;

always @(posedge clk) sync <= { sync[0], d };

assign q = sync[1];

endmodule
