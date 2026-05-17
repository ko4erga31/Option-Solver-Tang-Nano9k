function automatic real log(input real x);
    real ln_2, c1, c2, c3, c4, c5, c6, c7, c8;
    real m, t, p;
    real pow2_int, pow2_frac;
	real polynom;

	ln_2 = 0.6931471806;
	c1 =   0.9999964239;
	c2 =  -0.4998741238;
	c3 =   0.3317990258;
	c4 =  -0.2407338084;
	c5 =   0.1676540711;
	c6 =  -0.0953293897;
	c7 =   0.0360884937;
	c8 =  -0.0064535442;
	

    m = x;
    p = 0;
    while (m >= 2.0) begin
        m = m / 2.0;
        p = p + 1;
    end
    while (m < 1.0) begin
        m = m * 2.0;
        p = p - 1;
    end
    t = m - 1.0;


	polynom = c8;
	polynom = c7 + polynom * t;
	polynom = c6 + polynom * t;
	polynom = c5 + polynom * t;
	polynom = c4 + polynom * t;
	polynom = c3 + polynom * t;
	polynom = c2 + polynom * t;
	polynom = c1 + polynom * t;

	return polynom * t + p * ln_2;
endfunction

