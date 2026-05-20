`timescale 1ns / 1ps

module tb_bs_price;
    logic        opt_type;
    logic signed [31:0] S, K, r, T, sigma;
    logic signed [31:0] price;
    real S_real, K_real, r_real, T_real, sigma_real, expected_real;
    real price_real, diff;
    int  opt_type_int;
    real tolerance = 0.001;

    bs_price u_bs (
        .opt_type(opt_type),
        .S(S),
        .K(K),
        .T(T),
        .sigma(sigma),
        .price(price)
    );
    int fd;
    int vectornum, errors;

    initial begin
        fd = $fopen("/home/kniv/BS-model/testvectors/test_bs.tv", "r");
        if (fd == 0) begin
            $display("ERROR: Cannot open test_bs.tv");
            $finish;
        end

        $display("=== Price calculator test ===");
        vectornum = 0;
        errors    = 0;

        while ($fscanf(fd, "%d %f %f %f %f %f %f",
                       opt_type_int,
                       S_real, K_real, r_real, T_real, sigma_real,
                       expected_real) == 7) begin

            opt_type = opt_type_int[0];
            S    = S_real    * 65536.0;
            K    = K_real    * 65536.0;
            r    = 0.15    * 65536.0;
            T    = T_real    * 65536.0;
            sigma = sigma_real * 65536.0;
            #1;
            price_real = real'(price) / 65536.0;

            diff = $abs(price_real - expected_real);
            if (diff > tolerance) begin
                $display("Error in test %0d:", vectornum);
                $display("Input: opt=%0d S=%f K=%f r=%f T=%f sigma=%f",
                         opt_type_int, S_real, K_real, r_real, T_real, sigma_real);
                $display("Excepted: %f, got: %f (diff %f)", expected_real, price_real, diff);
                errors = errors + 1;
            end

            vectornum = vectornum + 1;
        end

        $fclose(fd);

        $display("Tests performed: %0d, errors: %0d", vectornum, errors);
        if (errors == 0)
            $display("SUCCESS: All tests passed.");
        else
            $display("FAILURE: Some tests failed.");

        $finish;
    end
endmodule