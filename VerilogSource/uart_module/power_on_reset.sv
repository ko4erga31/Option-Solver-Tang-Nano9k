`default_nettype none
module power_on_reset (
    input  wire clk,
    output logic rst_n
);
    logic cnt = 0;
    always_ff @(posedge clk) begin
        if (cnt != 1)
            cnt = cnt + 1;
    end
    assign rst_n = (cnt == 1);
endmodule
`default_nettype wire