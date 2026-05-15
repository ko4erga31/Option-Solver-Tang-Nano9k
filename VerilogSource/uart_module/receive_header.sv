`default_nettype none
module receive_header (
    input  wire         clk,
    input  wire         rst_n,
    input  wire         restart,
    input  wire [7:0]   byte_data,
    input  wire         byte_valid,
    output logic [23:0] noc,
    output logic [31:0] nnz,
    output logic [15:0] modulo,
    output logic [7:0]  bits_val,
    output logic [23:0] row_val,
    output logic [7:0]  col_max_nnz,
    output logic        header_done
);

    typedef enum logic [4:0] {
        S_WAIT  = 5'd0,
        S_NOR0  = 5'd1, S_NOR1 = 5'd2, S_NOR2 = 5'd3,
        S_NNZ0  = 5'd4, S_NNZ1 = 5'd5, S_NNZ2 = 5'd6, S_NNZ3 = 5'd7,
        S_MOD0  = 5'd8, S_MOD1 = 5'd9,
        S_BVAL  = 5'd10,
        S_RVAL0 = 5'd11, S_RVAL1 = 5'd12, S_RVAL2 = 5'd13,
        S_CMAX  = 5'd14,
        S_DONE  = 5'd15
    } state_t;
    
    state_t state = S_WAIT;

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n)
            state <= S_WAIT;
        else if (restart)
            state <= S_WAIT;
        else
            case (state)
                S_WAIT:  state <= S_NOR0;
                S_NOR0:  if (byte_valid) state <= S_NOR1;
                S_NOR1:  if (byte_valid) state <= S_NOR2;
                S_NOR2:  if (byte_valid) state <= S_NNZ0;
                S_NNZ0:  if (byte_valid) state <= S_NNZ1;
                S_NNZ1:  if (byte_valid) state <= S_NNZ2;
                S_NNZ2:  if (byte_valid) state <= S_NNZ3;
                S_NNZ3:  if (byte_valid) state <= S_MOD0;
                S_MOD0:  if (byte_valid) state <= S_MOD1;
                S_MOD1:  if (byte_valid) state <= S_BVAL;
                S_BVAL:  if (byte_valid) state <= S_RVAL0;
                S_RVAL0: if (byte_valid) state <= S_RVAL1;
                S_RVAL1: if (byte_valid) state <= S_RVAL2;
                S_RVAL2: if (byte_valid) state <= S_CMAX;                
                S_CMAX:  if (byte_valid) state <= S_DONE;
                S_DONE:  ; // ждём restart               
            endcase
    end

    always_ff @(posedge clk, negedge rst_n, posedge restart) begin
        if (!rst_n || restart) begin
            noc         <= 24'd0;
            nnz         <= 32'd0;
            modulo      <= 16'd0;
            bits_val    <= 8'd0;
            row_val     <= 24'd0;
            col_max_nnz <= 8'd0;            
        end else if (byte_valid) begin
            case (state)
                S_WAIT:  noc[7:0]   <= byte_data;
                S_NOR0:  noc[7:0]   <= byte_data;
                S_NOR1:  noc[15:8]  <= byte_data;
                S_NOR2:  noc[23:16] <= byte_data;
                S_NNZ0:  nnz[7:0]   <= byte_data;
                S_NNZ1:  nnz[15:8]  <= byte_data;
                S_NNZ2:  nnz[23:16] <= byte_data;
                S_NNZ3:  nnz[31:24] <= byte_data;
                S_MOD0:  modulo[7:0]  <= byte_data;
                S_MOD1:  modulo[15:8] <= byte_data;
                S_BVAL:  bits_val     <= byte_data;
                S_RVAL0: row_val[7:0]   <= byte_data;
                S_RVAL1: row_val[15:8]  <= byte_data;
                S_RVAL2: row_val[23:16] <= byte_data;                
                S_CMAX:  col_max_nnz    <= byte_data;
                default: ;
            endcase
        end
    end

    assign header_done = (state == S_DONE);
endmodule
`default_nettype wire