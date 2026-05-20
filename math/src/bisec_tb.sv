`timescale 1ns / 1ps

module tb_implied_vol;

    // Тактовый сигнал и сброс
    logic clk = 0;
    logic rst = 1;

    // Подключение к модулю
    logic                start;
    logic                opt_type;
    logic signed [31:0]  S, K, r, T, market_price;
    logic signed [31:0]  sigma_out;
    logic                done, busy;

    bisection uut (
        .clk          (clk),
        .rst          (rst),
        .start        (start),
        .opt_type     (opt_type),
        .S            (S),
        .K            (K),
        .T            (T),
        .market_price (market_price),
        .sigma_out    (sigma_out),
        .done         (done),
        .busy         (busy)
    );

    // Файл с тестовыми векторами
    int fd_in, fd_out;          // дескрипторы файлов
    int vectornum, errors;

    int    opt_type_int;
    real   S_real, K_real, r_real, T_real, market_real, expected_sigma_real;
    real   sigma_actual_real, diff, moneyness;
    real   tolerance = 0.005;

    always #5 clk = ~clk;

    initial begin
        rst <= 1;
        start <= 0;
        #20;
        rst <= 0;
        #10;

        // Файл с входными векторами (чтение)
        fd_in = $fopen("/home/kniv/BS-model/testvectors/test_bisection.tv", "r");
        if (fd_in == 0) begin
            $display("Ошибка: не удалось открыть test_bisection.tv");
            $finish;
        end

        // Файл для выходных данных (запись)
        fd_out = $fopen("/home/kniv/BS-model/results.csv", "w");
        if (fd_out == 0) begin
            $display("Ошибка: не удалось создать results.csv");
            $finish;
        end
        // Заголовок CSV
        $fwrite(fd_out, "opt_type,moneyness,sigma_actual_percent,sigma_expected_percent\n");

        $display("=== Тестирование модуля implied_vol ===");
        vectornum = 0;
        errors    = 0;

        while ($fscanf(fd_in, "%d %f %f %f %f %f %f",
                       opt_type_int,
                       S_real, K_real, r_real, T_real, market_real,
                       expected_sigma_real) == 7) begin

            opt_type     = opt_type_int[0];
            S            = S_real    * 65536.0;
            K            = K_real    * 65536.0;
            r            = r_real    * 65536.0;
            T            = T_real    * 65536.0;
            market_price = market_real * 65536.0;

            // Запуск вычисления
            start <= 1;
            @(posedge clk);
            start <= 0;

            wait (done == 1);

            sigma_actual_real = real'(sigma_out) / 65536.0;
            diff = $abs(sigma_actual_real - expected_sigma_real);
            moneyness = S_real / K_real;

            // Запись в выходной файл
            $fwrite(fd_out, "%0d,%f,%f,%f\n",
                    opt_type_int,
                    moneyness,
                    sigma_actual_real * 100.0,   // перевод в проценты
                    expected_sigma_real * 100.0);

            if (diff > tolerance) begin
                $display("Ошибка в тесте %0d:", vectornum);
                $display("  opt=%0d S=%f K=%f r=%f T=%f market=%f",
                         opt_type_int, S_real, K_real, r_real, T_real, market_real);
                $display("  Ожидаемая sigma=%f, получена sigma=%f (разница %f)",
                         expected_sigma_real, sigma_actual_real, diff);
                errors = errors + 1;
            end

            vectornum = vectornum + 1;
        end

        $fclose(fd_in);
        $fclose(fd_out);

        $display("Выполнено тестов: %0d, ошибок: %0d", vectornum, errors);
        if (errors == 0)
            $display("Все тесты пройдены успешно.");
        else
            $display("НАЙДЕНЫ ОШИБКИ.");

        $finish;
    end
endmodule