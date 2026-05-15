`default_nettype none
module uart_tx #(
	parameter CLK_FREQ = 27_000_000,
    parameter BAUD_RATE = 115_200,
	parameter BUF_SIZE = 2
)(
	input wire logic clk,
	input wire logic [8*BUF_SIZE-1:0] buffer,
	input wire logic nEN,
	output logic uart_tx,
	output logic nReady
);
    
    localparam DELAY_FRAMES = CLK_FREQ / BAUD_RATE; // 234
    localparam COUNTER_WIDTH = $clog2(DELAY_FRAMES); // 8
    localparam BYTE_CNT_WIDTH = $clog2(BUF_SIZE); // 1
    
	
	logic [COUNTER_WIDTH-1:0] txCounter = 0;
    logic [BYTE_CNT_WIDTH:0] txByteCounter = 0;
	logic [7:0] dataOut = 0;
	logic txPinRegister = 1;
	logic [2:0] txBitNumber = 0;	

	assign uart_tx = txPinRegister;

    typedef enum logic [1:0] {
        TX_IDLE,
        TX_START_BIT,
        TX_WRITE,
        TX_STOP_BIT
    } state_t;


    state_t txState = TX_IDLE;
	always_ff @(posedge clk) begin
		case (txState)
			TX_IDLE: begin
				if (nEN == 0) begin
					txState <= TX_START_BIT;
					txCounter <= 0;
					txByteCounter <= 0;
				end else begin
					txPinRegister <= 1;
				end
				// nReady <= 1;
			end

		TX_START_BIT: begin
			txPinRegister <= 0;
			if ((txCounter + 1) == DELAY_FRAMES) begin
				txState <= TX_WRITE;
				dataOut <= buffer[txByteCounter * 8 +: 8];
				txBitNumber <= 0;
				txCounter <= 0;
			end else
				txCounter <= txCounter + 1;
			end

		TX_WRITE: begin
			txPinRegister <= dataOut[txBitNumber];
			if ((txCounter + 1) == DELAY_FRAMES) begin
				if (txBitNumber == 3'd7)
					txState <= TX_STOP_BIT;
				else begin
					txBitNumber <= txBitNumber + 1;
				end
				txCounter <= 0;
			end else
			txCounter <= txCounter + 1;
		end

		TX_STOP_BIT: begin
			txPinRegister <= 1;
			if ((txCounter + 1) == DELAY_FRAMES) begin
				if (txByteCounter == BUF_SIZE - 1) begin
					txState <= TX_IDLE;
					nReady <= 0;
				end else begin
					txByteCounter <= txByteCounter + 1;
					txState <= TX_START_BIT;
				end
				txCounter <= 0;
			end else
				txCounter <= txCounter + 1;
			end
		endcase
	end
endmodule
`default_nettype wire