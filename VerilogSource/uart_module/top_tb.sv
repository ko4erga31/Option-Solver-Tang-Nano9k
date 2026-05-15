    `timescale 1ns/1ns
    module test();

        logic clk;
        logic uart_rx, uart_tx;
        logic [139:0] data;
        logic [7:0] cnt;
        logic [7:0] i;
        logic [7:0] uart_data;    
        logic result_ready;
        wire [7:0] tx_byte;
        wire       tx_byte_valid;
        logic [15:0] captured_result;
        logic [1:0]  byte_cnt;
        
        top topik (
            .clk,
            .uart_rx,
            .uart_tx
        );
        initial begin
            clk = 0;        
            result_ready = 0;        
            uart_rx = 1;
            cnt = 234;
            i = 0;
            byte_cnt = 2'd0;
            data = 140'b0010100001_0000000001_0000000001_0101101001_0000000001_0000000001_0000000001_0001000001_0101011011_0001000001_0001000001_0000000001_0000000001_0001000001;
        end

        initial forever #18.519 clk = ~clk;
        initial begin
            wait (i >= 140);
            $display("All data was received");
            result_ready = 1;
            cnt = 234;
            wait (topik.solver_done);
            #100;
            $display("computed: %b (%d)", topik.result, topik.result);        
            wait (byte_cnt == 2);
            $display("All data was send");         
            $display("Result = %b (%d)", captured_result, captured_result);        
            #1000;
            $finish;
        end

        always_ff @(posedge clk) begin        
            if (cnt === 234 && i < 140) begin 
                uart_rx <= data[139 - i];
                cnt <= 0;
                i <= i + 1;
            end else begin
                cnt <= cnt + 1;
            end
        end



        uart_rx #(.CLK_FREQ(27_000_000), .BAUD_RATE(115200)) tx_monitor (
            .clk(clk),
            .uart_rx(uart_tx),
            .dataOut(tx_byte),
            .dataReady(tx_byte_valid)
        );

        always_ff @(posedge clk) begin
            if (tx_byte_valid) begin
                if (byte_cnt == 2'd0) begin
                    captured_result[15:8] <= tx_byte;
                    byte_cnt <= 2'd1;
                end else if (byte_cnt == 2'd1) begin
                    captured_result[7:0] <= tx_byte;
                    byte_cnt <= 2'd2;
                end
            end
        end
        
        initial begin 
            $dumpfile("test_out.vcd");
            $dumpvars(0, test);
        end
    endmodule