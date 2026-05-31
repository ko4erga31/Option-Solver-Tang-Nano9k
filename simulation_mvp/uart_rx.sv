`default_nettype none
module uart_rx #(
    parameter CLK_FREQ   = 27_000_000,
    parameter BAUD_RATE  = 115_200
)(
    input wire logic clk,
    input wire logic uart_rx,
    output logic [7:0] dataOut,
    output logic dataReady
);
    
    logic rx_sync1 = 1'b1;
    logic rx_sync2 = 1'b1;
    logic rx = 1'b1;


    always_ff @(posedge clk) begin
        rx_sync1 <= uart_rx;
        rx_sync2 <= rx_sync1;
        rx <= rx_sync2;
    end
    
    localparam DELAY_FRAMES = CLK_FREQ / BAUD_RATE; //234
    localparam HALF_DELAY_WAIT  = DELAY_FRAMES / 2; //117

    localparam COUNTER_WIDTH = $clog2(DELAY_FRAMES); // 8

    logic [COUNTER_WIDTH-1:0] rxCounter = 0;
    logic [2:0] rxBitNumber = 0;  
    logic [7:0] dataIn = 0;
    logic byteReady = 0;

    assign dataReady = byteReady;
    assign dataOut = dataIn;

    typedef enum logic[2:0] {
        RX_IDLE,
        RX_START_BIT,
        RX_READ_WAIT,
        RX_READ,
        RX_STOP_BIT
    } state_t;

    state_t rxState = RX_IDLE;

    always_ff @(posedge clk) begin
        byteReady <= 0;
        case (rxState)
            RX_IDLE: begin                    
                if (rx == 0) begin
                    dataIn <= 8'b0;
                    rxState <= RX_START_BIT;
                    rxCounter <= 1;
                    rxBitNumber <= 0;
                end
            end
            RX_START_BIT: begin
                if (rxCounter == HALF_DELAY_WAIT) begin
                    if (rx == 0) begin 
                        rxState <= RX_READ_WAIT;
                    end else begin
                        rxState <= RX_IDLE;
                    end
                    rxCounter <= 1;
                end else 
                    rxCounter <= rxCounter + 1;
            end
            RX_READ_WAIT: begin
                rxCounter <= rxCounter + 1;
                if ((rxCounter + 1) == DELAY_FRAMES) begin
                    rxState <= RX_READ;
                end
            end
            RX_READ: begin
                rxCounter <= 1;
                dataIn <= {rx, dataIn[7:1]};
                rxBitNumber <= rxBitNumber + 1;
                if (rxBitNumber == 3'b111)
                    rxState <= RX_STOP_BIT;
                else
                    rxState <= RX_READ_WAIT;
            end
            RX_STOP_BIT: begin
                rxCounter <= rxCounter + 1;
                if ((rxCounter + 1) == DELAY_FRAMES) begin
                    rxState <= RX_IDLE;
                    rxCounter <= 0;
                    if (rx == 1) byteReady <= 1;
                end
            end
        default: rxState <= RX_IDLE;
        endcase
    end
endmodule
`default_nettype wire