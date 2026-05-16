`timescale 1ns/1ps

module test_normalCDF;
    real x, expected, actual;
    real tolerance_rel = 1.0e-5;
    real tolerance_abs = 1.0e-10;
    real threshold     = 1.0e-9;
    int fd;
    int vectornum, errors;

    initial begin
        fd = $fopen("test_exp.tv", "r");
        if (fd == 0) begin
            $display("Can't open test_exp.tv");
            $finish;
        end

        vectornum = 0;
        errors = 0;
        $display("Exponent test.");

        while ($fscanf(fd, "%f %f", x, expected) == 2) begin
            actual = exp(x);

            if ($abs(expected) > threshold) begin
                if ($abs(actual - expected) > tolerance_rel * $abs(expected)) begin
                    $display("Test %0d: x = %f, excepted %.12e, actual %.12e",
                             vectornum, x, expected, actual);
                    errors = errors + 1;
                end
            end else begin
                if ($abs(actual - expected) > tolerance_abs) begin
                    $display("Test %0d: x = %f, excepted %.12e, actual %.12e",
                             vectornum, x, expected, actual);
                    errors = errors + 1;
                end
            end
            vectornum = vectornum + 1;
        end
        $fclose(fd);
        $display("Tests performed: %0d, with errors: %0d", vectornum, errors);
        if (errors == 0)
            $display("All tests were passed successfully.");
        $finish;
    end
endmodule