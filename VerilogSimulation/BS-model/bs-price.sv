`include "exponent.sv"
`include "normalCDF.sv"

function automatic real bs_price(
    input int option_type,
    input real S, K, r, T, sigma
);
    real d1, d2, price;
    if (T <= 0.0 || sigma <= 0.0)
        return 0.0;

    d1 = ($ln(S / K) + (r + 0.5 * sigma * sigma) * T) / (sigma * $sqrt(T));
    d2 = d1 - sigma * $sqrt(T);

    if (option_type == 0) begin // Call
        price = S * normalCDF(d1) - K * exp(-r * T) * normalCDF(d2);
    end else begin              // Put
        price = K * exp(-r * T) * normalCDF(-d2) - S * normalCDF(-d1);
    end
    return price;
endfunction
