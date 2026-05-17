`timescale 1ns/1ps

module test_Log;
    real x, expected, actual;
    real tolerance = 1.0e-6;
    int fd;
    int vectornum, errors;

    initial begin
        fd = $fopen("test_log.tv", "r");
        if (fd == 0) begin
            $display("Can't open test_norm.tv");
            $finish;
        end
        $display("Log test.");
        vectornum = 0;
        errors = 0;

        while ($fscanf(fd, "%f %f", x, expected) == 2) begin
            actual = log(x);

            if ($abs(actual - expected) > tolerance) begin
                $display("Test %0d: x = %f, excepted %f, actual %f",
                         vectornum, x, expected, actual);
                errors = errors + 1;
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
