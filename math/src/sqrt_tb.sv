`timescale 1ns / 1ps

module test_sqrt;
    logic signed [31:0] x_q16;
    logic signed [31:0] y_q16;
    real                x_real;
    real                y_expected;
    real                y_actual;
    real                diff;
    real                tolerance;

    sqrt u_sqrt (
        .x (x_q16),
        .y (y_q16)
    );

    int fd;
    int vectornum, errors;

    initial begin
        tolerance = 0.0001;

        fd = $fopen("/home/kniv/BS-model/testvectors/test_sqrt.tv", "r");
        if (fd == 0) begin
            $display("ERROR: Cannot open test_sqrt.tv");
            $finish;
        end

        $display("=== Sqrt Test ===");
        vectornum = 0;
        errors    = 0;

        while ($fscanf(fd, "%f %f", x_real, y_expected) == 2) begin
            x_q16 = x_real * 65536.0;
            #1;
            y_actual = real'(y_q16) / 65536.0;
           
            diff = $abs(y_actual - y_expected);
            if (diff > tolerance) begin
                $display("ERROR: test %0d: x = %f, expected = %f, got = %f (diff = %f)",
                         vectornum, x_real, y_expected, y_actual, diff);
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