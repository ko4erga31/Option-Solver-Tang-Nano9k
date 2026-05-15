`default_nettype none
module solver (
    input  wire        clk,
    input  wire        rst_n,
    input  wire        start,
    input  wire [7:0]  bits_val,
    input  wire [23:0] row_val,
    input  wire [7:0]  col_max_nnz,
    input  wire [15:0] modulo,
    output logic [15:0] det_out,
    output logic        done
);
    always_ff @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            det_out <= 0;
            done    <= 0;
        end else begin
            done <= 0;
            if (start) begin
                det_out <= {8'b0, bits_val};
                done    <= 1'b1;
            end
        end
    end
endmodule
`default_nettype wire