`default_nettype none
module top (
    input  wire logic clk,
    input  wire logic uart_rx,
    output logic uart_tx
);
    logic rst_n;
    power_on_reset por (.clk, .rst_n);

    logic [7:0]  rx_byte;
    logic rx_valid;
    uart_rx #(.CLK_FREQ(27_000_000), .BAUD_RATE(115200)) uart_rx_inst (
        .clk, .uart_rx, .dataOut(rx_byte), .dataReady(rx_valid)
    );

    logic [23:0] noc;
    logic [31:0] nnz;
    logic [15:0] modulo;
    logic [7:0]  bits_val, col_max_nnz;
    logic [23:0] row_val;
    logic header_done;

    logic restart_hdr;
    logic solver_start;
    logic  solver_done;
    logic [15:0] result;    

    receive_header header (
        .clk, .rst_n,
        .restart(restart_hdr),
        .byte_data(rx_byte), .byte_valid(rx_valid),
        .noc, .nnz, .modulo, .bits_val, .row_val, .col_max_nnz,
        .header_done
    );

    solver solver_inst (
        .clk, .rst_n,
        .start(solver_start),
        .bits_val, .row_val, .col_max_nnz, .modulo,
        .det_out(result),
        .done(solver_done)
    );

    logic tx_send;
    logic  tx_ready;
    uart_tx #(.CLK_FREQ(27_000_000), .BAUD_RATE(115200), .BUF_SIZE(2)) uart_tx_inst (
        .clk,
        .buffer({result[7:0], result[15:8]}),
        .nEN(~tx_send),
        .uart_tx,
        .nReady(tx_ready)
    );

    typedef enum logic [1:0] {S_IDLE, S_SOLVE, S_SEND} state_t;
    state_t state;

    always_ff @(posedge clk, negedge rst_n) begin
        if (!rst_n) begin
            state  <= S_IDLE;            
            restart_hdr  <= 0;
            solver_start <= 0;
            tx_send      <= 0; 
        end else begin
            restart_hdr  <= 1'b0;
            solver_start <= 1'b0;
            tx_send      <= 1'b0;        
            case (state)
                S_IDLE: begin
                    if (header_done) begin
                        solver_start <= 1;
                        state <= S_SOLVE;                    
                    end
                end
                S_SOLVE: begin
                    if (solver_done) begin
                        tx_send <= 1;
                        state <= S_SEND;
                    end
                end
                S_SEND: begin
                    if (!tx_ready) begin                    
                        restart_hdr <= 1;                    
                        state <= S_IDLE;                    
                    end
                end
                default: state <= S_IDLE;
            endcase
        end
    end
endmodule
`default_nettype wire