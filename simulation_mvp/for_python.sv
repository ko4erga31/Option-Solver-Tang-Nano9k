`timescale 1ns / 1ps
`default_nettype none

module tb_top_file_io();
    // DUT Signals
    logic clk = 0;
    logic rst = 0;
    logic uart_rx_pin = 1;
    logic uart_tx_pin;
    logic [7:0] rx_resp [0:3];

    // Instantiate DUT (Имя модуля должно совпадать с вашим top.sv)
    top u_top (
        .clk     (clk),
        .rst     (rst),
        .uart_rx (uart_rx_pin),
        .uart_tx (uart_tx_pin)
    );

    // Clock Generation: 27 MHz (~37.037 ns period)
    always #18.5185 clk = ~clk;

    // UART Timing Constants (27_000_000 / 115_200 = 234)
    localparam int BIT_CYCLES = 234;
    localparam int HALF_BIT   = 117;

    // File descriptors
    integer fd_in, fd_out;
    logic [7:0] req_data [0:16];
    logic [7:0] resp_byte;
    int chars_read;

    // Task: Send a byte from File -> DUT (UART TX in TB -> uart_rx in DUT)
    task automatic tb_uart_send(input logic [7:0] data);
        uart_rx_pin = 0; // Start bit
        repeat(BIT_CYCLES) @(posedge clk);
        for (int i = 0; i < 8; i++) begin // LSB First
            uart_rx_pin = data[i];
            repeat(BIT_CYCLES) @(posedge clk);
        end
        uart_rx_pin = 1; // Stop bit
        repeat(BIT_CYCLES) @(posedge clk);
    endtask

    // Task: Receive a byte from DUT -> File (uart_tx in DUT -> UART RX in TB)
    task automatic tb_uart_recv(output logic [7:0] data);
        wait(uart_tx_pin == 0); // Wait for start bit
        repeat(HALF_BIT) @(posedge clk); // Sample in middle
        for (int i = 0; i < 8; i++) begin
            repeat(BIT_CYCLES) @(posedge clk);
            data[i] = uart_tx_pin; // LSB First
        end
        repeat(BIT_CYCLES) @(posedge clk); // Stop bit
    endtask

    // Main Simulation Sequence
    initial begin
        
        // 1. Read Request File
        fd_in = $fopen("/home/kniv/BS-model/uart_request.bin", "rb");
        if (fd_in == 0) begin
            $display("FATAL: Cannot open uart_request.bin");
            $finish;
        end
        
        chars_read = $fread(req_data, fd_in);
        $fclose(fd_in);
        
        if (chars_read != 17) begin
            $display("FATAL: Expected 17 bytes in uart_request.bin, got %0d", chars_read);
            $finish;
        end

        // 2. Reset Sequence
        rst = 1;
        repeat(100) @(posedge clk);
        rst = 0;
        repeat(50) @(posedge clk);

        // 3. Send 20 bytes to DUT
        for (int i = 0; i < 17; i++) begin
            tb_uart_send(req_data[i]);
        end
        //$display("Type: %f, received: %f", req_data[0], u_top.opt_type);
        //$display("S: %f, received: %f", real'({req_data[1], req_data[2], req_data[3], req_data[4]}) / 65536.0, real'(u_top.S) / 65536.0);
        //$display("K: %f, received: %f", real'({req_data[5], req_data[6], req_data[7], req_data[8]}) / 65536.0, real'(u_top.K) / 65536.0);
        //$display("T: %f, received: %f", real'({req_data[9], req_data[10], req_data[11], req_data[12]}) / 65536.0, real'(u_top.T) / 65536.0);
        //$display("market: %f, received: %f", real'({req_data[13], req_data[14], req_data[15], req_data[16]}) / 65536.0, real'(u_top.market_price) / 65536.0);

        // 4. Receive 4 bytes from DUT
        fd_out = $fopen("/home/kniv/BS-model/uart_response.bin", "wb");
        if (fd_out == 0) begin
            $display("FATAL: Cannot open uart_response.bin for writing");
            $finish;
        end

        for (int i = 0; i < 4; i++) begin
            int timeout = 0;
            while(uart_tx_pin !== 0) begin
                @(posedge clk);
                timeout++;
                if (timeout > 500_000) begin
                    $display("FATAL: Timeout waiting for TX byte %0d", i);
                    $fclose(fd_out);
                    $finish;
                end
            end
            tb_uart_recv(resp_byte);
            $fwrite(fd_out, "%c", resp_byte);
            //$display("%b", resp_byte);
        end
        //$display("sigma: %f", real'(u_top.sigma_out) / 65536.0);
        //$display("sigma Q1616: %b", u_top.sigma_out);
        
        $fclose(fd_out);
        $finish;
    end
endmodule
`default_nettype wire