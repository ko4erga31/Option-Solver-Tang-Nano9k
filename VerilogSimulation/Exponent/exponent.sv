function automatic real exp(input real x);
    real q, c1, c2, c3, c4, c5, c6, c7, c8;
    real y, y_int, y_frac;
    real pow2_int, pow2_frac;

    q  = 1.442695041;
    c1 = 0.693147181;
    c2 = 0.240226507;
    c3 = 0.055504109;
    c4 = 0.009618129;
    c5 = 0.001333356;
    c6 = 0.000154035;
    c7 = 0.000015252;
    c8 = 0.000001321;
    
    y = x * q;
    y_int = $floor(y);
    y_frac = y - y_int;

    pow2_int = $pow(2.0, y_int);
    pow2_frac = c8;
    pow2_frac = c7 + pow2_frac * y_frac;
    pow2_frac = c6 + pow2_frac * y_frac;
    pow2_frac = c5 + pow2_frac * y_frac;
    pow2_frac = c4 + pow2_frac * y_frac;
    pow2_frac = c3 + pow2_frac * y_frac;
    pow2_frac = c2 + pow2_frac * y_frac;
    pow2_frac = c1 + pow2_frac * y_frac;
    pow2_frac = 1 + pow2_frac * y_frac;
    
    return pow2_int * pow2_frac;   
endfunction
