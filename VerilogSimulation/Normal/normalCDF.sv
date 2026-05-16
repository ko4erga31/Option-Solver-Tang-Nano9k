function automatic real normalCDF(input real x);
    real p, a1, a2, a3, a4, a5;
    real t, b, polynom;
    real x_pos;

    p  =  0.231641893;
    a1 =  0.254829592;
    a2 = -0.284496736;
    a3 =  1.421413741;
    a4 = -1.453152027;
    a5 =  1.061405429;

    if (x < -8.0) 
        return 0;
    if (x > 8.0)
        return 1;

    if (x < 0.0)
        x_pos = -x;
    else
        x_pos = x;  

    t = 1.0 / (1.0 + p * x_pos);
    polynom = a5;
    polynom = a4 + polynom * t;
    polynom = a3 + polynom * t;
    polynom = a2 + polynom * t;
    polynom = a1 + polynom * t;
    b = polynom * t;

    if (x >= 0.0)
        return 1.0 - 0.5 * b * exp(-0.5 * x_pos * x_pos);
    else        
        return 0.5 * b * exp(-0.5 * x_pos * x_pos);
endfunction
