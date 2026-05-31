function automatic signed [31:0] mul_q16 (
    input logic signed [31:0] a,
    input logic signed [31:0] b
);
    automatic logic signed [63:0] product;
    begin
        product = a * b;
        product = product + 64'h0000_0000_0000_8000;
        return product >>> 16;
    end
endfunction

function automatic signed [31:0] div_q16 (
    input signed [31:0] numerator,
    input signed [31:0] denominator
);
    logic signed [63:0] num_scaled;
    begin
        num_scaled = { {32{numerator[31]}}, numerator };   // 64-битное знаковое расширение
        num_scaled = (num_scaled <<< 16) + (denominator >>> 1);
        div_q16 = num_scaled / denominator;
        return div_q16;
    end    
endfunction


// Все еще можно попробовать доработать и уменьшить количество делений
// 0.006687038122132228 <= x <= 2.5939563987410637

module sqrt (
    input logic signed [31:0] x,
    output logic signed [31:0] y
);
    // Taylor + Normalizing + Newton
    localparam logic signed [31:0] sqrt2 = 32'sh00016A0A;
    localparam logic signed [31:0] two = 32'sh00020000;
    localparam logic signed [31:0] one = 32'sh00010000;
    

    localparam logic signed [31:0] c1 = 32'sh00008000;
    localparam logic signed [31:0] c2 = 32'sh00002000;
    localparam logic signed [31:0] c3 = 32'sh00001000;

    logic signed [31:0] result;
    logic signed [31:0] t;
    logic signed [31:0] taylor;
    
    always_comb begin 
        if (x > two) begin            
            t = x - one;
            taylor = c3;
            taylor = mul_q16(t, taylor) - c2;
            taylor = c1 + mul_q16(t, taylor);
            taylor = one + mul_q16(t, taylor);
            result = mul_q16(taylor, sqrt2);
            
            y = (result + div_q16(x, result)) >>> 1;
            y = (y + div_q16(x, y)) >>> 1;
            y = (y + div_q16(x, y)) >>> 1;
        end else if (x == two) begin
            y = sqrt2;
        end else if (x > one) begin
            t = x - one;
            taylor = c3;
            taylor = c2 + mul_q16(t, taylor);
            taylor = c1 + mul_q16(t, taylor);
            taylor = one + mul_q16(t, taylor);
            result = taylor;
            
            y = (result + div_q16(x, result)) >>> 1;
            y = (y + div_q16(x, y)) >>> 1;
            y = (y + div_q16(x, y)) >>> 1;
        end else if (x == one) begin
            y = one;
        end else begin            
            t = one - x;   
            taylor = c3;            
            taylor = c2 + mul_q16(t, taylor);
            taylor = c1 + mul_q16(t, taylor);
            taylor = one - mul_q16(t, taylor);            
            result = taylor;

            y = (result + div_q16(x, result)) >>> 1;
            y = (y + div_q16(x, y)) >>> 1;
            y = (y + div_q16(x, y)) >>> 1;
            y = (y + div_q16(x, y)) >>> 1;
        end
    end        
endmodule

// 0.37071641791044774 <= x <= 1.7742857142857142
module ln (
    input logic signed [31:0] x,    
    output logic signed [31:0] y
);
    // Normalizing + Abramovic-Stigan
    localparam logic signed [31:0] ln2 = 32'h0000B172;
    localparam logic signed [31:0] one = 32'sh00010000;
    localparam logic signed [31:0] c1 = 32'sh0000FFDF;
    localparam logic signed [31:0] c2 = 32'shFFFF8212;
    localparam logic signed [31:0] c3 = 32'sh00004A1B;
    localparam logic signed [31:0] c4 = 32'shFFFFDD2B;
    localparam logic signed [31:0] c5 = 32'sh0000083C;
    logic signed [31:0] poly;
    logic signed [31:0] t;

    always_comb begin
        if (x < (one >>> 3)) begin
            t = x <<< 4;
            t = t - one;
            poly = c5;
            poly = c4 + mul_q16(poly, t);            
            poly = c3 + mul_q16(poly, t);
            poly = c2 + mul_q16(poly, t);
            poly = c1 + mul_q16(poly, t);
            poly = mul_q16(poly, t);
            y = poly - (ln2 <<< 3);
        end else if (x < (one >>> 2)) begin
            t = x <<< 3;
            t = t - one;
            poly = c5;
            poly = c4 + mul_q16(poly, t);            
            poly = c3 + mul_q16(poly, t);
            poly = c2 + mul_q16(poly, t);
            poly = c1 + mul_q16(poly, t);
            poly = mul_q16(poly, t);
            y = poly - (ln2 <<< 2);
        end else if (x < (one >>> 1)) begin
            t = x <<< 2;
            t = t - one;
            poly = c5;
            poly = c4 + mul_q16(poly, t);            
            poly = c3 + mul_q16(poly, t);
            poly = c2 + mul_q16(poly, t);
            poly = c1 + mul_q16(poly, t);
            poly = mul_q16(poly, t);
            y = poly - (ln2 <<< 1);
        end else if (x < one) begin
            t = x <<< 1;
            t = t - one;
            poly = c5;
            poly = c4 + mul_q16(poly, t);
            poly = c3 + mul_q16(poly, t);
            poly = c2 + mul_q16(poly, t);
            poly = c1 + mul_q16(poly, t);
            poly = mul_q16(poly, t);
            y = poly - ln2;
        end else if (x == one) begin
            y = 32'sh00000000;
        end else begin
            t = x - one;
            poly = c5;
            poly = c4 + mul_q16(poly, t);
            poly = c3 + mul_q16(poly, t);
            poly = c2 + mul_q16(poly, t);
            poly = c1 + mul_q16(poly, t);
            poly = mul_q16(poly, t); 
            y = poly;
        end 
    end
endmodule
    
// Ошибка чуть чуть больше: 0.0002 вместо 0.0001 у других
// -20 <= x <= 0
module exp (
    input  logic signed [31:0] x,
    output logic signed [31:0] y
);
    // Normalizing for 2^y and Taylor
    localparam logic signed [31:0] q   = 32'sh00017132;
    localparam logic signed [31:0] c1  = 32'sh0000B173;
    localparam logic signed [31:0] c2  = 32'sh00003D7F;
    localparam logic signed [31:0] c3  = 32'sh00000E36;
    localparam logic signed [31:0] c4  = 32'sh00000276;
    localparam logic signed [31:0] c5  = 32'sh00000057;
    localparam logic signed [31:0] c6  = 32'sh0000000A;
    localparam logic signed [31:0] c7  = 32'sh00000001;
    localparam logic signed [31:0] c8  = 32'sh00000001;

    logic signed [31:0] t, k, r, pow2_frac, pow2_int;
    logic signed [31:0] one = 32'sh00010000;

    always_comb begin
        t = mul_q16(x, q);

        k = t >>> 16;
        r = t - (k <<< 16);

        if (r < 0) begin
            k = k - 1;
            r = r + one;
        end
        
        pow2_frac = c8;
        pow2_frac = c7 + mul_q16(pow2_frac, r);
        pow2_frac = c6 + mul_q16(pow2_frac, r);
        pow2_frac = c5 + mul_q16(pow2_frac, r);
        pow2_frac = c4 + mul_q16(pow2_frac, r);
        pow2_frac = c3 + mul_q16(pow2_frac, r);
        pow2_frac = c2 + mul_q16(pow2_frac, r);
        pow2_frac = c1 + mul_q16(pow2_frac, r);
        pow2_frac = one + mul_q16(pow2_frac, r);

        if (k >= 0) begin
            pow2_int = one <<< k;
        end else begin
            pow2_int = one >>> (-k);
        end

        y = mul_q16(pow2_int, pow2_frac);
    end
endmodule

// -1046.8514515542781 <= x <= 1046.8514515542781
module normalCDF (
    input logic signed [31:0] x,
    output logic signed [31:0] y
);
    localparam logic signed [31:0] p   = 32'sh00003B4D;
    localparam logic signed [31:0] a1  = 32'sh0000413D;
    localparam logic signed [31:0] a2  = 32'shFFFFB72B;
    localparam logic signed [31:0] a3  = 32'sh00016BE2;
    localparam logic signed [31:0] a4  = 32'shFFFE8BFC;
    localparam logic signed [31:0] a5  = 32'sh00010FB8;
    localparam logic signed [31:0] one = 32'sh00010000;
    
    logic signed [31:0] xpos, t;
    logic signed [31:0] polynom;
    logic signed [31:0] exp_res;
    logic signed [31:0] tmp;

    exp exponent (
        .x (tmp),
        .y (exp_res)
    );

    always_comb begin
        if (x <= 32'shFFF80000) begin
            y = 32'sh00000000;
        end else if (x >= 32'sh00080000) begin
            y = one;
        end else begin
            if (x < 32'sh00000000) begin
                xpos = -x;
            end else begin
                xpos = x;
            end
            t = div_q16(one, one + mul_q16(p, xpos));
            polynom = a5;
            polynom = a4 + mul_q16(polynom, t);
            polynom = a3 + mul_q16(polynom, t);
            polynom = a2 + mul_q16(polynom, t);
            polynom = a1 + mul_q16(polynom, t);
            polynom = mul_q16(polynom, t);

            tmp = mul_q16(xpos, xpos);
            tmp = tmp >>> 1;
            tmp = -tmp;
            if (x > 32'sh00000000) begin
                y = one - (mul_q16(polynom, exp_res) >>> 1);
            end else begin
                y = (mul_q16(polynom, exp_res) >>> 1);
            end
        end
    end
endmodule


// Call - 0, Put - 1
// Ошибка в среднем в третьем знаке после запятой, можно доработать/взять числа поточнее, есть что доработать при наличии времени
module bs_price #(
    parameter logic signed [31:0] r = 32'sh00002666
) (
    input  logic                 opt_type,
    input  logic signed [31:0]   S,
    input  logic signed [31:0]   K,
    input  logic signed [31:0]   T,
    input  logic signed [31:0]   sigma,
    output logic signed [31:0]   price
);
    wire signed [31:0] sqrt_T;
    wire signed [31:0] sigma_mul_sqrt_T = mul_q16(sigma, sqrt_T);
    wire signed [31:0] sigma_eps = sigma_mul_sqrt_T;
    wire signed [31:0] S_div_K = div_q16(S, K);
    wire signed [31:0] ln_S_div_K;
    wire signed [31:0] sigma_sq = mul_q16(sigma, sigma);
    wire signed [31:0] sigma_sq_div2 = sigma_sq >>> 1;
    wire signed [31:0] r_plus_sigma = r + sigma_sq_div2;
    wire signed [31:0] r_plus_sigma_T = mul_q16(r_plus_sigma, T);
    wire signed [31:0] numerator_d1 = ln_S_div_K + r_plus_sigma_T;
    wire signed [31:0] d1 = div_q16(numerator_d1, sigma_eps);
    wire signed [31:0] d2 = d1 - sigma_mul_sqrt_T;
    wire signed [31:0] d1_neg = -d1;
    wire signed [31:0] d2_neg = -d2;

    wire signed [31:0] cdf_d1, cdf_d2, cdf_neg_d1, cdf_neg_d2;
    wire signed [31:0] rT = mul_q16(r, T);
    wire signed [31:0] neg_rT = -rT;
    wire signed [31:0] exp_neg_rT;

    sqrt        u_sqrt         (.x(T),       .y(sqrt_T));
    ln          u_ln           (.x(S_div_K), .y(ln_S_div_K));
    exp    u_exp          (.x(neg_rT),  .y(exp_neg_rT));
    normalCDF   u_cdf_d1       (.x(d1),      .y(cdf_d1));
    normalCDF   u_cdf_d2       (.x(d2),      .y(cdf_d2));
    normalCDF   u_cdf_neg_d1   (.x(d1_neg),  .y(cdf_neg_d1));
    normalCDF   u_cdf_neg_d2   (.x(d2_neg),  .y(cdf_neg_d2));

    wire signed [31:0] call_term1 = mul_q16(S, cdf_d1);
    wire signed [31:0] call_term2 = mul_q16(K, mul_q16(exp_neg_rT, cdf_d2));
    wire signed [31:0] put_term1  = mul_q16(S, cdf_neg_d1);
    wire signed [31:0] put_term2  = mul_q16(K, mul_q16(exp_neg_rT, cdf_neg_d2));

    wire signed [31:0] call_price = call_term1 - call_term2;
    wire signed [31:0] put_price  = put_term2 - put_term1;

    always_comb begin
        if (opt_type == 1'b0)
            price = call_price;
        else
            price = put_price;
    end
endmodule

// Колбасит на каких-то значениях, скорее всего чувствительные к сигма значения выпадают из диапазонов и нужно сделать нормально на всю ось...
module bisection (
    input  logic clk,
    input  logic rst,
    input  logic start,
    input logic opt_type,
    input logic signed [31:0] S,
    input logic signed [31:0] K,
    input logic signed [31:0] T,
    input logic signed [31:0] market_price,
    output logic signed [31:0] sigma_out,
    output logic done,
    output logic busy
);

    typedef enum logic [1:0] { IDLE, INIT, ITERATE, DONE_ST } state_t;
    state_t state;

    localparam signed [31:0] LOW_INIT   = 32'h00000001;
    localparam signed [31:0] HIGH_INIT  = 32'h00050000;
    localparam signed [31:0] TOLERANCE  = 32'h00000001;
    localparam int           MAX_ITER   = 32;

    logic signed [31:0] low, high;
    logic [6:0] iter_count;

    wire signed [31:0] mid = (low + high) >>> 1;

    wire signed [31:0] price;
    bs_price u_bs_price (
        .opt_type (opt_type),
        .S        (S),
        .K        (K),
        .T        (T),
        .sigma    (mid),
        .price    (price)
    );

    wire signed [31:0] diff = (price > market_price) ?
                              (price - market_price) :
                              (market_price - price);
    wire converged = (diff < TOLERANCE) || ((high - low) <= 32'h00000001);

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state      <= IDLE;
            low        <= 0;
            high       <= 0;
            iter_count <= 0;
            done       <= 1'b0;
            busy       <= 1'b0;
            sigma_out  <= 0;
        end else begin
            done <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= INIT;
                        busy  <= 1'b1;
                    end else begin
                        busy  <= 1'b0;
                    end
                end

                INIT: begin
                    low        <= LOW_INIT;
                    high       <= HIGH_INIT;
                    iter_count <= 0;
                    state      <= ITERATE;
                end

                ITERATE: begin
                    if (converged) begin
                        sigma_out <= mid;
                        done      <= 1'b1;
                        busy      <= 1'b0;
                        state     <= DONE_ST;
                    end else if (iter_count >= MAX_ITER - 1) begin
                        sigma_out <= mid;
                        done      <= 1'b1;
                        busy      <= 1'b0;
                        state     <= DONE_ST;
                    end else begin
                        if (price > market_price)
                            high <= mid;
                        else
                            low  <= mid;
                        iter_count <= iter_count + 1;
                    end
                end

                DONE_ST: begin
                    state <= IDLE;
                end

                default: state <= IDLE;
            endcase
        end
    end
endmodule


module top (
    input wire logic clk,
    input wire logic rst,
    input wire logic uart_rx,
    output wire logic uart_tx
);

    localparam CLK_FREQ   = 27_000_000;
    localparam BAUD_RATE  = 115_200;
    localparam RX_BYTES    = 17;
    localparam TX_BYTES    = 4;

    logic [7:0] rx_data;
    logic       rx_ready;
    logic [4:0] rx_cnt;
    logic [7:0] rx_buffer [16:0];

    logic [31:0] tx_byte;
    logic       tx_nEN;
    logic       tx_ready;
    logic [1:0] tx_byte_cnt;

    logic       start;
    logic       opt_type;
    logic signed [31:0] S, K, T, market_price;
    logic signed [31:0] sigma_out;
    logic       done;
    logic       busy;

    uart_rx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE)) u_rx (
        .clk(clk), .uart_rx(uart_rx), .dataOut(rx_data), .dataReady(rx_ready)
    );

    uart_tx #(.CLK_FREQ(CLK_FREQ), .BAUD_RATE(BAUD_RATE), .BUF_SIZE(TX_BYTES)) u_tx (
        .clk(clk), .buffer(tx_byte), .nEN(tx_nEN), .uart_tx(uart_tx), .nReady(tx_ready)
    );

    bisection u_bisection (
        .clk(clk), .rst(rst), .start(start),
        .opt_type(opt_type), .S(S), .K(K), .T(T), .market_price(market_price),
        .sigma_out(sigma_out), .done(done), .busy(busy)
    );

    typedef enum logic [1:0] { ST_IDLE, ST_RECV, ST_WAIT_BISECTION, ST_SEND } state_t;
    state_t state = ST_IDLE;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            rx_cnt <= 0;
            tx_byte_cnt <= 0;
            tx_nEN <= 1;
            start <= 0;
            opt_type <= 0;
            S <= 0; K <= 0; T <= 0; market_price <= 0;
        end else begin
            start <= 0;
            case (state)
                ST_IDLE: begin
                    rx_cnt <= 0;
                    state <= ST_RECV;
                end

                ST_RECV: begin
                    if (rx_ready) begin
                        rx_buffer[rx_cnt] <= rx_data;
                        if (rx_cnt == RX_BYTES-1) begin
                            opt_type <= rx_buffer[0][0];
                            S <= { rx_buffer[1], rx_buffer[2], rx_buffer[3], rx_buffer[4] };
                            K <= { rx_buffer[5], rx_buffer[6], rx_buffer[7], rx_buffer[8] };
                            T <= { rx_buffer[9], rx_buffer[10], rx_buffer[11], rx_buffer[12] };
                            market_price <= { rx_buffer[13], rx_buffer[14], rx_buffer[15], rx_data };
                            state <= ST_WAIT_BISECTION;
                        end else begin
                            rx_cnt <= rx_cnt + 1;
                        end
                    end
                end

                ST_WAIT_BISECTION: begin

                    if (!busy && !start && !done)
                        start <= 1;

                    if (busy)
                        start <= 0;

                    if (done) begin
                        start <= 0;
                        state <= ST_SEND;
                        tx_byte_cnt <= 0;
                    end

                end

                ST_SEND: begin
                    if (!tx_ready) begin
                        tx_byte <= sigma_out;
                        tx_nEN <= 1'b0;
                    end else begin
                        tx_nEN <= 1'b1;
                        state <= ST_IDLE;
                    end
                end
            endcase
        end
    end
endmodule