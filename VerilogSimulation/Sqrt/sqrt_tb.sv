`timescale 1ns/1ps

module test_sqrt;
    real x, expected, actual;
    real tolerance = 1.0e-7;
    int fd;
    int vectornum, errors;

    initial begin
        fd = $fopen("test_sqrt.tv", "r");
        if (fd == 0) begin
            $display("Can't open test_sqrt.tv");
            $finish;
        end
        $display("Sqrt test.");
        vectornum = 0;
        errors = 0;

        while ($fscanf(fd, "%f %f", x, expected) == 2) begin
            actual = sqrt(x);

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
