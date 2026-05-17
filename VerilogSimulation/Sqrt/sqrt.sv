function automatic real sqrt(input real S);
    real sqrt2;
	real m, p;
	real c1, c2, c3;
	real t, sqrt_m_approx, n0;
	real a, b, result;

	sqrt2 = 1.4142135623730951;
	c1 = 0.5;
	c2 = -0.125;
	c3 = 0.0625;


    m = S;
    p = 0;
    if (S > 0.0) begin
        while (m >= 2.0) begin
            m = m / 2.0;
            p = p + 1;
        end
        while (m < 1.0) begin
            m = m * 2.0;
            p = p - 1;
        end
    end else begin
        return 0.0;
    end
    // Для real используем умножение на 0.5, 0.125, 0.0625, но логически это сдвиги.
    t = m - 1.0;

    sqrt_m_approx = c3;
	sqrt_m_approx = c2 + t * sqrt_m_approx;
	sqrt_m_approx = c1 + t * sqrt_m_approx;
	sqrt_m_approx = 1 + t * sqrt_m_approx;

    if (p % 2 == 0) begin
        n0 = sqrt_m_approx * $pow(2.0, p / 2);
    end else begin
        n0 = sqrt2 * sqrt_m_approx * $pow(2.0, (p - 1) / 2);
    end

    a = (S - n0 * n0) / (2.0 * n0);
    b = n0 + a;
    result = b - (a * a) / (2.0 * b);

    return result;
endfunction
