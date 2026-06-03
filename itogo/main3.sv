module mul_q16 (
    input  clk,
    input  signed [31:0] a, 
    input  signed [31:0] b,
    input logic start,
    output signed [31:0] result,
    output logic valid
);
    reg signed [63:0] product_reg;
    
    always_ff @(posedge clk) begin
        if (start) begin
            product_reg <= a * b;
            valid <= 1'b1;
        end else begin
            valid <= 1'b0;
        end
    end
    assign result = (product_reg + 64'h8000) >>> 16;
endmodule

//48 тактов
module div_q16 #(
    parameter WIDTH = 32,
    parameter FBITS = 16
) (
    input  wire logic                clk,
    input  wire logic                start,
    output      logic                busy,
    output      logic                valid,
    input  wire logic signed [WIDTH-1:0] num,
    input  wire logic signed [WIDTH-1:0] den,
    output      logic signed [WIDTH-1:0] quo,
    output      logic signed [WIDTH-1:0] rem
);

    localparam ITER = WIDTH + FBITS;
    logic sign_num_reg, sign_den_reg, sign_quo_reg;
    logic [WIDTH-1:0] num_abs_reg;
    logic [WIDTH-1:0] den_abs_reg;
    logic den_is_zero_reg;
    logic [WIDTH:0]   rem_reg;
    logic [WIDTH-1:0] num_reg;
    logic [WIDTH-1:0] quo_reg;
    logic [$clog2(ITER)-1:0] i_reg;

    logic [WIDTH:0] sub_res;
    logic sub_ok;
    logic [WIDTH:0] rem_next;
    logic [WIDTH-1:0] num_next;
    logic [WIDTH-1:0] quo_next;
    assign sub_res = {rem_reg[WIDTH-1:0], num_reg[WIDTH-1]} - {1'b0, den_abs_reg};
    assign sub_ok = den_is_zero_reg ? 1'b0 : ~sub_res[WIDTH];

    assign rem_next = sub_ok ? sub_res : {rem_reg[WIDTH-1:0], num_reg[WIDTH-1]};
    assign num_next = {num_reg[WIDTH-2:0], 1'b0};
    assign quo_next = {quo_reg[WIDTH-2:0], sub_ok};

    always_ff @(posedge clk) begin
        if (start) begin
            busy          <= 1'b1;
            valid         <= 1'b0;
            i_reg         <= 0;
            sign_num_reg  <= num[WIDTH-1];
            sign_den_reg  <= den[WIDTH-1];
            sign_quo_reg  <= num[WIDTH-1] ^ den[WIDTH-1];
            num_abs_reg   <= num[WIDTH-1] ? -num : num;
            den_abs_reg   <= den[WIDTH-1] ? -den : den;
            den_is_zero_reg <= (den == 0); 
            
            rem_reg       <= 0;
            num_reg       <= num[WIDTH-1] ? -num : num;
            quo_reg       <= 0;
            
        end else if (busy) begin
            if (i_reg == ITER - 1) begin
                busy   <= 1'b0;
                valid  <= 1'b1;
                quo <= sign_quo_reg ? -quo_next : quo_next;
                rem <= den_is_zero_reg ? 0 : (sign_num_reg ? -rem_next[WIDTH-1:0] : rem_next[WIDTH-1:0]);
                
            end else begin
                i_reg    <= i_reg + 1;
                rem_reg  <= rem_next;
                num_reg  <= num_next;
                quo_reg  <= quo_next;
            end
        end else begin
            valid <= 1'b0;
        end
    end

endmodule


//24 такта на весь диапазон

module sqrt #(
    parameter WIDTH=32,
    parameter FBITS=16
    ) (
    input wire logic clk,
    input wire logic start,
    output     logic busy,
    output     logic valid,
    input wire logic signed [WIDTH-1:0] rad,
    output     logic signed [WIDTH-1:0] root,
    output     logic signed [WIDTH-1:0] rem
    );

    logic [WIDTH-1:0] x, x_next;    // radicand copy
    logic [WIDTH-1:0] q, q_next;    // intermediate root (quotient)
    logic [WIDTH+1:0] ac, ac_next;  // accumulator (2 bits wider)
    logic [WIDTH+1:0] test_res;     // sign test result (2 bits wider)

    localparam ITER = (WIDTH + FBITS) >> 1;  // iterations are half radicand+fbits width
    logic [$clog2(ITER)-1:0] i;            // iteration counter

    always_comb begin
        test_res = ac - {q, 2'b01};
        if (test_res[WIDTH+1] == 0) begin       // test_res ≥0?
            {ac_next, x_next} = {test_res[0 +: WIDTH], x, 2'b0};
            q_next = {q[WIDTH-2:0], 1'b1};
        end else begin
            {ac_next, x_next} = {ac[0 +: WIDTH], x, 2'b0};
            q_next = q << 1;
        end
    end

    always_ff @(posedge clk) begin
        if (start) begin
            busy <= 1;
            valid <= 0;
            i <= 0;
            q <= 0;
            {ac, x} <= {{WIDTH{1'b0}}, rad, 2'b0};
        end else if (busy) begin
            if (i == ITER-1) begin  // we're done
                busy <= 0;
                valid <= 1;
                root <= q_next;
                rem <= ac_next[2 +: WIDTH];   // вместо ac_next[WIDTH+1:2]  // undo final shift
            end else begin  // next iteration
                i <= i + 1;
                x <= x_next;
                ac <= ac_next;
                q <= q_next;
            end
        end
    end
endmodule

// 0.34 <= x <= 1.7742857142857142
module log (
    input  logic clk,
    input logic rst,
    input  logic start,
    input  logic signed [31:0] x,
    output logic signed [31:0] y,
    output logic valid
);
    localparam logic signed [31:0] X_MIN = 32'sh00004000;
    localparam logic signed [31:0] X_MAX = 32'sh0001E666;
    localparam logic signed [31:0] STEP  = 32'sh000000D3;
    localparam logic signed [31:0] INV_STEP = 32'sh01364D93;

    function automatic signed [31:0] rom_lookup(input logic [8:0] idx);
        unique case (idx)
            9'd0: return 32'shFFFE9D1C; 9'd1: return 32'shFFFEA063; 9'd2: return 32'shFFFEA3A0; 9'd3: return 32'shFFFEA6D2;
            9'd4: return 32'shFFFEA9FB; 9'd5: return 32'shFFFEAD19; 9'd6: return 32'shFFFEB02E; 9'd7: return 32'shFFFEB33A;
            9'd8: return 32'shFFFEB63C; 9'd9: return 32'shFFFEB935; 9'd10: return 32'shFFFEBC26; 9'd11: return 32'shFFFEBF0E;
            9'd12: return 32'shFFFEC1EE; 9'd13: return 32'shFFFEC4C5; 9'd14: return 32'shFFFEC795; 9'd15: return 32'shFFFECA5D;
            9'd16: return 32'shFFFECD1D; 9'd17: return 32'shFFFECFD6; 9'd18: return 32'shFFFED287; 9'd19: return 32'shFFFED531;
            9'd20: return 32'shFFFED7D4; 9'd21: return 32'shFFFEDA70; 9'd22: return 32'shFFFEDD06; 9'd23: return 32'shFFFEDF95;
            9'd24: return 32'shFFFEE21D; 9'd25: return 32'shFFFEE49F; 9'd26: return 32'shFFFEE71B; 9'd27: return 32'shFFFEE991;
            9'd28: return 32'shFFFEEC00; 9'd29: return 32'shFFFEEE6A; 9'd30: return 32'shFFFEF0CE; 9'd31: return 32'shFFFEF32D;
            9'd32: return 32'shFFFEF585; 9'd33: return 32'shFFFEF7D9; 9'd34: return 32'shFFFEFA27; 9'd35: return 32'shFFFEFC70;
            9'd36: return 32'shFFFEFEB3; 9'd37: return 32'shFFFF00F2; 9'd38: return 32'shFFFF032B; 9'd39: return 32'shFFFF0560;
            9'd40: return 32'shFFFF0790; 9'd41: return 32'shFFFF09BB; 9'd42: return 32'shFFFF0BE1; 9'd43: return 32'shFFFF0E03;
            9'd44: return 32'shFFFF1020; 9'd45: return 32'shFFFF1239; 9'd46: return 32'shFFFF144D; 9'd47: return 32'shFFFF165E;
            9'd48: return 32'shFFFF186A; 9'd49: return 32'shFFFF1A71; 9'd50: return 32'shFFFF1C75; 9'd51: return 32'shFFFF1E75;
            9'd52: return 32'shFFFF2070; 9'd53: return 32'shFFFF2268; 9'd54: return 32'shFFFF245C; 9'd55: return 32'shFFFF264D;
            9'd56: return 32'shFFFF2839; 9'd57: return 32'shFFFF2A22; 9'd58: return 32'shFFFF2C07; 9'd59: return 32'shFFFF2DE9;
            9'd60: return 32'shFFFF2FC7; 9'd61: return 32'shFFFF31A1; 9'd62: return 32'shFFFF3379; 9'd63: return 32'shFFFF354C;
            9'd64: return 32'shFFFF371D; 9'd65: return 32'shFFFF38EA; 9'd66: return 32'shFFFF3AB4; 9'd67: return 32'shFFFF3C7B;
            9'd68: return 32'shFFFF3E3F; 9'd69: return 32'shFFFF4000; 9'd70: return 32'shFFFF41BD; 9'd71: return 32'shFFFF4378;
            9'd72: return 32'shFFFF452F; 9'd73: return 32'shFFFF46E4; 9'd74: return 32'shFFFF4896; 9'd75: return 32'shFFFF4A45;
            9'd76: return 32'shFFFF4BF1; 9'd77: return 32'shFFFF4D9A; 9'd78: return 32'shFFFF4F41; 9'd79: return 32'shFFFF50E5;
            9'd80: return 32'shFFFF5286; 9'd81: return 32'shFFFF5425; 9'd82: return 32'shFFFF55C1; 9'd83: return 32'shFFFF575A;
            9'd84: return 32'shFFFF58F1; 9'd85: return 32'shFFFF5A85; 9'd86: return 32'shFFFF5C17; 9'd87: return 32'shFFFF5DA6;
            9'd88: return 32'shFFFF5F33; 9'd89: return 32'shFFFF60BE; 9'd90: return 32'shFFFF6246; 9'd91: return 32'shFFFF63CC;
            9'd92: return 32'shFFFF6550; 9'd93: return 32'shFFFF66D1; 9'd94: return 32'shFFFF6850; 9'd95: return 32'shFFFF69CD;
            9'd96: return 32'shFFFF6B48; 9'd97: return 32'shFFFF6CC0; 9'd98: return 32'shFFFF6E37; 9'd99: return 32'shFFFF6FAB;
            9'd100: return 32'shFFFF711D; 9'd101: return 32'shFFFF728D; 9'd102: return 32'shFFFF73FB; 9'd103: return 32'shFFFF7567;
            9'd104: return 32'shFFFF76D1; 9'd105: return 32'shFFFF7839; 9'd106: return 32'shFFFF799F; 9'd107: return 32'shFFFF7B03;
            9'd108: return 32'shFFFF7C65; 9'd109: return 32'shFFFF7DC5; 9'd110: return 32'shFFFF7F23; 9'd111: return 32'shFFFF8080;
            9'd112: return 32'shFFFF81DA; 9'd113: return 32'shFFFF8333; 9'd114: return 32'shFFFF848A; 9'd115: return 32'shFFFF85DF;
            9'd116: return 32'shFFFF8733; 9'd117: return 32'shFFFF8885; 9'd118: return 32'shFFFF89D4; 9'd119: return 32'shFFFF8B23;
            9'd120: return 32'shFFFF8C6F; 9'd121: return 32'shFFFF8DBA; 9'd122: return 32'shFFFF8F03; 9'd123: return 32'shFFFF904B;
            9'd124: return 32'shFFFF9191; 9'd125: return 32'shFFFF92D5; 9'd126: return 32'shFFFF9418; 9'd127: return 32'shFFFF9559;
            9'd128: return 32'shFFFF9699; 9'd129: return 32'shFFFF97D7; 9'd130: return 32'shFFFF9913; 9'd131: return 32'shFFFF9A4E;
            9'd132: return 32'shFFFF9B87; 9'd133: return 32'shFFFF9CBF; 9'd134: return 32'shFFFF9DF6; 9'd135: return 32'shFFFF9F2B;
            9'd136: return 32'shFFFFA05F; 9'd137: return 32'shFFFFA191; 9'd138: return 32'shFFFFA2C1; 9'd139: return 32'shFFFFA3F1;
            9'd140: return 32'shFFFFA51F; 9'd141: return 32'shFFFFA64B; 9'd142: return 32'shFFFFA776; 9'd143: return 32'shFFFFA8A0;
            9'd144: return 32'shFFFFA9C8; 9'd145: return 32'shFFFFAAF0; 9'd146: return 32'shFFFFAC15; 9'd147: return 32'shFFFFAD3A;
            9'd148: return 32'shFFFFAE5D; 9'd149: return 32'shFFFFAF7F; 9'd150: return 32'shFFFFB0A0; 9'd151: return 32'shFFFFB1BF;
            9'd152: return 32'shFFFFB2DD; 9'd153: return 32'shFFFFB3FA; 9'd154: return 32'shFFFFB515; 9'd155: return 32'shFFFFB630;
            9'd156: return 32'shFFFFB749; 9'd157: return 32'shFFFFB861; 9'd158: return 32'shFFFFB978; 9'd159: return 32'shFFFFBA8D;
            9'd160: return 32'shFFFFBBA2; 9'd161: return 32'shFFFFBCB5; 9'd162: return 32'shFFFFBDC7; 9'd163: return 32'shFFFFBED8;
            9'd164: return 32'shFFFFBFE8; 9'd165: return 32'shFFFFC0F7; 9'd166: return 32'shFFFFC204; 9'd167: return 32'shFFFFC311;
            9'd168: return 32'shFFFFC41C; 9'd169: return 32'shFFFFC527; 9'd170: return 32'shFFFFC630; 9'd171: return 32'shFFFFC738;
            9'd172: return 32'shFFFFC83F; 9'd173: return 32'shFFFFC945; 9'd174: return 32'shFFFFCA4A; 9'd175: return 32'shFFFFCB4E;
            9'd176: return 32'shFFFFCC51; 9'd177: return 32'shFFFFCD53; 9'd178: return 32'shFFFFCE54; 9'd179: return 32'shFFFFCF54;
            9'd180: return 32'shFFFFD053; 9'd181: return 32'shFFFFD151; 9'd182: return 32'shFFFFD24E; 9'd183: return 32'shFFFFD34A;
            9'd184: return 32'shFFFFD445; 9'd185: return 32'shFFFFD53F; 9'd186: return 32'shFFFFD638; 9'd187: return 32'shFFFFD730;
            9'd188: return 32'shFFFFD827; 9'd189: return 32'shFFFFD91E; 9'd190: return 32'shFFFFDA13; 9'd191: return 32'shFFFFDB08;
            9'd192: return 32'shFFFFDBFB; 9'd193: return 32'shFFFFDCEE; 9'd194: return 32'shFFFFDDE0; 9'd195: return 32'shFFFFDED0;
            9'd196: return 32'shFFFFDFC0; 9'd197: return 32'shFFFFE0AF; 9'd198: return 32'shFFFFE19E; 9'd199: return 32'shFFFFE28B;
            9'd200: return 32'shFFFFE378; 9'd201: return 32'shFFFFE463; 9'd202: return 32'shFFFFE54E; 9'd203: return 32'shFFFFE638;
            9'd204: return 32'shFFFFE721; 9'd205: return 32'shFFFFE80A; 9'd206: return 32'shFFFFE8F1; 9'd207: return 32'shFFFFE9D8;
            9'd208: return 32'shFFFFEABE; 9'd209: return 32'shFFFFEBA3; 9'd210: return 32'shFFFFEC87; 9'd211: return 32'shFFFFED6B;
            9'd212: return 32'shFFFFEE4D; 9'd213: return 32'shFFFFEF2F; 9'd214: return 32'shFFFFF010; 9'd215: return 32'shFFFFF0F1;
            9'd216: return 32'shFFFFF1D0; 9'd217: return 32'shFFFFF2AF; 9'd218: return 32'shFFFFF38D; 9'd219: return 32'shFFFFF46B;
            9'd220: return 32'shFFFFF547; 9'd221: return 32'shFFFFF623; 9'd222: return 32'shFFFFF6FE; 9'd223: return 32'shFFFFF7D9;
            9'd224: return 32'shFFFFF8B2; 9'd225: return 32'shFFFFF98B; 9'd226: return 32'shFFFFFA64; 9'd227: return 32'shFFFFFB3B;
            9'd228: return 32'shFFFFFC12; 9'd229: return 32'shFFFFFCE8; 9'd230: return 32'shFFFFFDBD; 9'd231: return 32'shFFFFFE92;
            9'd232: return 32'shFFFFFF66; 9'd233: return 32'sh0000003A; 9'd234: return 32'sh0000010C; 9'd235: return 32'sh000001DE;
            9'd236: return 32'sh000002B0; 9'd237: return 32'sh00000380; 9'd238: return 32'sh00000450; 9'd239: return 32'sh00000520;
            9'd240: return 32'sh000005EE; 9'd241: return 32'sh000006BC; 9'd242: return 32'sh0000078A; 9'd243: return 32'sh00000856;
            9'd244: return 32'sh00000923; 9'd245: return 32'sh000009EE; 9'd246: return 32'sh00000AB9; 9'd247: return 32'sh00000B83;
            9'd248: return 32'sh00000C4D; 9'd249: return 32'sh00000D16; 9'd250: return 32'sh00000DDE; 9'd251: return 32'sh00000EA6;
            9'd252: return 32'sh00000F6D; 9'd253: return 32'sh00001034; 9'd254: return 32'sh000010F9; 9'd255: return 32'sh000011BF;
            9'd256: return 32'sh00001284; 9'd257: return 32'sh00001348; 9'd258: return 32'sh0000140B; 9'd259: return 32'sh000014CE;
            9'd260: return 32'sh00001591; 9'd261: return 32'sh00001653; 9'd262: return 32'sh00001714; 9'd263: return 32'sh000017D5;
            9'd264: return 32'sh00001895; 9'd265: return 32'sh00001954; 9'd266: return 32'sh00001A13; 9'd267: return 32'sh00001AD2;
            9'd268: return 32'sh00001B90; 9'd269: return 32'sh00001C4D; 9'd270: return 32'sh00001D0A; 9'd271: return 32'sh00001DC6;
            9'd272: return 32'sh00001E82; 9'd273: return 32'sh00001F3D; 9'd274: return 32'sh00001FF8; 9'd275: return 32'sh000020B2;
            9'd276: return 32'sh0000216C; 9'd277: return 32'sh00002225; 9'd278: return 32'sh000022DD; 9'd279: return 32'sh00002395;
            9'd280: return 32'sh0000244D; 9'd281: return 32'sh00002504; 9'd282: return 32'sh000025BA; 9'd283: return 32'sh00002670;
            9'd284: return 32'sh00002726; 9'd285: return 32'sh000027DB; 9'd286: return 32'sh0000288F; 9'd287: return 32'sh00002943;
            9'd288: return 32'sh000029F7; 9'd289: return 32'sh00002AAA; 9'd290: return 32'sh00002B5C; 9'd291: return 32'sh00002C0F;
            9'd292: return 32'sh00002CC0; 9'd293: return 32'sh00002D71; 9'd294: return 32'sh00002E22; 9'd295: return 32'sh00002ED2;
            9'd296: return 32'sh00002F82; 9'd297: return 32'sh00003031; 9'd298: return 32'sh000030E0; 9'd299: return 32'sh0000318E;
            9'd300: return 32'sh0000323C; 9'd301: return 32'sh000032E9; 9'd302: return 32'sh00003396; 9'd303: return 32'sh00003442;
            9'd304: return 32'sh000034EE; 9'd305: return 32'sh0000359A; 9'd306: return 32'sh00003645; 9'd307: return 32'sh000036EF;
            9'd308: return 32'sh0000379A; 9'd309: return 32'sh00003843; 9'd310: return 32'sh000038ED; 9'd311: return 32'sh00003996;
            9'd312: return 32'sh00003A3E; 9'd313: return 32'sh00003AE6; 9'd314: return 32'sh00003B8E; 9'd315: return 32'sh00003C35;
            9'd316: return 32'sh00003CDB; 9'd317: return 32'sh00003D82; 9'd318: return 32'sh00003E28; 9'd319: return 32'sh00003ECD;
            9'd320: return 32'sh00003F72; 9'd321: return 32'sh00004017; 9'd322: return 32'sh000040BB; 9'd323: return 32'sh0000415F;
            9'd324: return 32'sh00004202; 9'd325: return 32'sh000042A5; 9'd326: return 32'sh00004348; 9'd327: return 32'sh000043EA;
            9'd328: return 32'sh0000448C; 9'd329: return 32'sh0000452D; 9'd330: return 32'sh000045CE; 9'd331: return 32'sh0000466F;
            9'd332: return 32'sh0000470F; 9'd333: return 32'sh000047AF; 9'd334: return 32'sh0000484E; 9'd335: return 32'sh000048ED;
            9'd336: return 32'sh0000498C; 9'd337: return 32'sh00004A2A; 9'd338: return 32'sh00004AC8; 9'd339: return 32'sh00004B66;
            9'd340: return 32'sh00004C03; 9'd341: return 32'sh00004C9F; 9'd342: return 32'sh00004D3C; 9'd343: return 32'sh00004DD8;
            9'd344: return 32'sh00004E74; 9'd345: return 32'sh00004F0F; 9'd346: return 32'sh00004FAA; 9'd347: return 32'sh00005044;
            9'd348: return 32'sh000050DE; 9'd349: return 32'sh00005178; 9'd350: return 32'sh00005212; 9'd351: return 32'sh000052AB;
            9'd352: return 32'sh00005344; 9'd353: return 32'sh000053DC; 9'd354: return 32'sh00005474; 9'd355: return 32'sh0000550C;
            9'd356: return 32'sh000055A3; 9'd357: return 32'sh0000563A; 9'd358: return 32'sh000056D1; 9'd359: return 32'sh00005767;
            9'd360: return 32'sh000057FD; 9'd361: return 32'sh00005892; 9'd362: return 32'sh00005928; 9'd363: return 32'sh000059BD;
            9'd364: return 32'sh00005A51; 9'd365: return 32'sh00005AE5; 9'd366: return 32'sh00005B79; 9'd367: return 32'sh00005C0D;
            9'd368: return 32'sh00005CA0; 9'd369: return 32'sh00005D33; 9'd370: return 32'sh00005DC6; 9'd371: return 32'sh00005E58;
            9'd372: return 32'sh00005EEA; 9'd373: return 32'sh00005F7B; 9'd374: return 32'sh0000600D; 9'd375: return 32'sh0000609E;
            9'd376: return 32'sh0000612E; 9'd377: return 32'sh000061BF; 9'd378: return 32'sh0000624F; 9'd379: return 32'sh000062DE;
            9'd380: return 32'sh0000636E; 9'd381: return 32'sh000063FD; 9'd382: return 32'sh0000648C; 9'd383: return 32'sh0000651A;
            9'd384: return 32'sh000065A8; 9'd385: return 32'sh00006636; 9'd386: return 32'sh000066C3; 9'd387: return 32'sh00006751;
            9'd388: return 32'sh000067DE; 9'd389: return 32'sh0000686A; 9'd390: return 32'sh000068F7; 9'd391: return 32'sh00006983;
            9'd392: return 32'sh00006A0E; 9'd393: return 32'sh00006A9A; 9'd394: return 32'sh00006B25; 9'd395: return 32'sh00006BB0;
            9'd396: return 32'sh00006C3A; 9'd397: return 32'sh00006CC4; 9'd398: return 32'sh00006D4E; 9'd399: return 32'sh00006DD8;
            9'd400: return 32'sh00006E61; 9'd401: return 32'sh00006EEA; 9'd402: return 32'sh00006F73; 9'd403: return 32'sh00006FFC;
            9'd404: return 32'sh00007084; 9'd405: return 32'sh0000710C; 9'd406: return 32'sh00007194; 9'd407: return 32'sh0000721B;
            9'd408: return 32'sh000072A2; 9'd409: return 32'sh00007329; 9'd410: return 32'sh000073AF; 9'd411: return 32'sh00007436;
            9'd412: return 32'sh000074BC; 9'd413: return 32'sh00007541; 9'd414: return 32'sh000075C7; 9'd415: return 32'sh0000764C;
            9'd416: return 32'sh000076D1; 9'd417: return 32'sh00007756; 9'd418: return 32'sh000077DA; 9'd419: return 32'sh0000785E;
            9'd420: return 32'sh000078E2; 9'd421: return 32'sh00007966; 9'd422: return 32'sh000079E9; 9'd423: return 32'sh00007A6C;
            9'd424: return 32'sh00007AEF; 9'd425: return 32'sh00007B71; 9'd426: return 32'sh00007BF4; 9'd427: return 32'sh00007C76;
            9'd428: return 32'sh00007CF7; 9'd429: return 32'sh00007D79; 9'd430: return 32'sh00007DFA; 9'd431: return 32'sh00007E7B;
            9'd432: return 32'sh00007EFC; 9'd433: return 32'sh00007F7C; 9'd434: return 32'sh00007FFC; 9'd435: return 32'sh0000807C;
            9'd436: return 32'sh000080FC; 9'd437: return 32'sh0000817C; 9'd438: return 32'sh000081FB; 9'd439: return 32'sh0000827A;
            9'd440: return 32'sh000082F9; 9'd441: return 32'sh00008377; 9'd442: return 32'sh000083F5; 9'd443: return 32'sh00008473;
            9'd444: return 32'sh000084F1; 9'd445: return 32'sh0000856F; 9'd446: return 32'sh000085EC; 9'd447: return 32'sh00008669;
            9'd448: return 32'sh000086E6; 9'd449: return 32'sh00008762; 9'd450: return 32'sh000087DF; 9'd451: return 32'sh0000885B;
            9'd452: return 32'sh000088D7; 9'd453: return 32'sh00008952; 9'd454: return 32'sh000089CE; 9'd455: return 32'sh00008A49;
            9'd456: return 32'sh00008AC4; 9'd457: return 32'sh00008B3F; 9'd458: return 32'sh00008BB9; 9'd459: return 32'sh00008C33;
            9'd460: return 32'sh00008CAD; 9'd461: return 32'sh00008D27; 9'd462: return 32'sh00008DA1; 9'd463: return 32'sh00008E1A;
            9'd464: return 32'sh00008E93; 9'd465: return 32'sh00008F0C; 9'd466: return 32'sh00008F85; 9'd467: return 32'sh00008FFD;
            9'd468: return 32'sh00009075; 9'd469: return 32'sh000090ED; 9'd470: return 32'sh00009165; 9'd471: return 32'sh000091DD;
            9'd472: return 32'sh00009254; 9'd473: return 32'sh000092CB; 9'd474: return 32'sh00009342; 9'd475: return 32'sh000093B9;
            9'd476: return 32'sh0000942F; 9'd477: return 32'sh000094A6; 9'd478: return 32'sh0000951C; 9'd479: return 32'sh00009592;
            9'd480: return 32'sh00009607; 9'd481: return 32'sh0000967D; 9'd482: return 32'sh000096F2; 9'd483: return 32'sh00009767;
            9'd484: return 32'sh000097DC; 9'd485: return 32'sh00009850; 9'd486: return 32'sh000098C5; 9'd487: return 32'sh00009939;
            9'd488: return 32'sh000099AD; 9'd489: return 32'sh00009A21; 9'd490: return 32'sh00009A94; 9'd491: return 32'sh00009B08;
            9'd492: return 32'sh00009B7B; 9'd493: return 32'sh00009BEE; 9'd494: return 32'sh00009C61; 9'd495: return 32'sh00009CD3;
            9'd496: return 32'sh00009D45; 9'd497: return 32'sh00009DB8; 9'd498: return 32'sh00009E2A; 9'd499: return 32'sh00009E9B;
            9'd500: return 32'sh00009F0D; 9'd501: return 32'sh00009F7E; 9'd502: return 32'sh00009FEF; 9'd503: return 32'sh0000A060;
            9'd504: return 32'sh0000A0D1; 9'd505: return 32'sh0000A142; 9'd506: return 32'sh0000A1B2; 9'd507: return 32'sh0000A222;
            9'd508: return 32'sh0000A292; 9'd509: return 32'sh0000A302; 9'd510: return 32'sh0000A372; 9'd511: return 32'sh0000A3E1;
            default: return 32'h00000000;
        endcase
    endfunction
    logic signed [31:0] mul_a, mul_b;
    logic signed [31:0] mul_result;
    logic mul_start, mul_valid;
    mul_q16 u_mul (
        .clk(clk),
        .start(mul_start),
        .a(mul_a),
        .b(mul_b),
        .result(mul_result),
        .valid(mul_valid)
    );

    logic signed [31:0] diff_reg, y0_reg, y1_reg, frac_reg;
    logic signed [31:0] mul1_reg, mul2_reg, mul3_reg;
    logic [8:0] idx_reg;

    typedef enum logic [3:0] { 
        ST_IDLE, 
        ST_WAIT_MUL1, ST_CALC_IDX,
        ST_WAIT_MUL2, ST_CALC_FRAC,
        ST_WAIT_MUL3, ST_CALC_RESULT
    } state_t;
    state_t state = ST_IDLE;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            valid <= 1'b0;
            y <= 32'b0;
            mul_a <= 32'b0;
            mul_b <= 32'b0;
            mul_start <= 1'b0;
            diff_reg <= 32'b0; y0_reg <= 32'b0; y1_reg <= 32'b0; frac_reg <= 32'b0;
            mul1_reg <= 32'b0; mul2_reg <= 32'b0; mul3_reg <= 32'b0;
            idx_reg <= 8'b0;
        end else begin
            valid <= 1'b0;
            mul_start <= 1'b0;
            
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        if (x <= X_MIN) begin
                            y <= rom_lookup(9'd0); valid <= 1'b1;
                        end else if (x >= X_MAX) begin
                            y <= rom_lookup(9'd511); valid <= 1'b1;
                        end else begin
                            diff_reg <= x - X_MIN;
                            mul_a <= x - X_MIN; 
                            mul_b <= INV_STEP;
                            mul_start <= 1'b1;
                            state <= ST_WAIT_MUL1;
                        end
                    end
                end
                
                ST_WAIT_MUL1: begin
                    if (mul_valid) begin
                        mul1_reg <= mul_result;
                        state <= ST_CALC_IDX;
                    end
                end
                
                ST_CALC_IDX: begin
                    idx_reg <= mul1_reg[24:16]; 
                    y0_reg <= rom_lookup(mul1_reg[24:16]);
                    y1_reg <= (mul1_reg[24:16] == 9'd511) ? 
                              rom_lookup(9'd511) : rom_lookup(mul1_reg[24:16] + 9'd1);
                    mul_a <= {mul1_reg[24:16], 16'b0};
                    mul_b <= STEP;
                    mul_start <= 1'b1;
                    state <= ST_WAIT_MUL2;
                end
                
                ST_WAIT_MUL2: begin
                    if (mul_valid) begin
                        mul2_reg <= mul_result;
                        state <= ST_CALC_FRAC;
                    end
                end
                
                ST_CALC_FRAC: begin
                    frac_reg <= diff_reg - mul2_reg;
                    
                    mul_a <= y1_reg - y0_reg;
                    mul_b <= diff_reg - mul2_reg; 
                    mul_start <= 1'b1;
                    state <= ST_WAIT_MUL3;
                end
                
                ST_WAIT_MUL3: begin
                    if (mul_valid) begin
                        mul3_reg <= mul_result;
                        state <= ST_CALC_RESULT;
                    end
                end
                
                ST_CALC_RESULT: begin
                    y <= y0_reg + mul3_reg;
                    valid <= 1'b1;
                    state <= ST_IDLE;
                end 
                
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

// довольно большая ошибка из за таблички, можно попробовать сделать поточнее если будет место
module exp (
    input  logic clk,
    input logic rst,
    input  logic start,
    input  logic signed [31:0] x,
    output logic signed [31:0] y,
    output logic valid
);
    localparam logic signed [31:0] X_MIN =  32'shFFF40000;
    localparam logic signed [31:0] ONE   =  32'sh00010000;
    localparam logic signed [31:0] STEP  =  32'sh00000600;
    localparam logic signed [31:0] INV_STEP = 32'sh002AAAAA;

    function automatic signed [31:0] rom_lookup(input logic [8:0] idx);
        unique case (idx)
            9'd0: return 32'sh00000000; 9'd1: return 32'sh00000000; 9'd2: return 32'sh00000000; 9'd3: return 32'sh00000000;
            9'd4: return 32'sh00000000; 9'd5: return 32'sh00000000; 9'd6: return 32'sh00000000; 9'd7: return 32'sh00000000;
            9'd8: return 32'sh00000000; 9'd9: return 32'sh00000000; 9'd10: return 32'sh00000001; 9'd11: return 32'sh00000001;
            9'd12: return 32'sh00000001; 9'd13: return 32'sh00000001; 9'd14: return 32'sh00000001; 9'd15: return 32'sh00000001;
            9'd16: return 32'sh00000001; 9'd17: return 32'sh00000001; 9'd18: return 32'sh00000001; 9'd19: return 32'sh00000001;
            9'd20: return 32'sh00000001; 9'd21: return 32'sh00000001; 9'd22: return 32'sh00000001; 9'd23: return 32'sh00000001;
            9'd24: return 32'sh00000001; 9'd25: return 32'sh00000001; 9'd26: return 32'sh00000001; 9'd27: return 32'sh00000001;
            9'd28: return 32'sh00000001; 9'd29: return 32'sh00000001; 9'd30: return 32'sh00000001; 9'd31: return 32'sh00000001;
            9'd32: return 32'sh00000001; 9'd33: return 32'sh00000001; 9'd34: return 32'sh00000001; 9'd35: return 32'sh00000001;
            9'd36: return 32'sh00000001; 9'd37: return 32'sh00000001; 9'd38: return 32'sh00000001; 9'd39: return 32'sh00000001;
            9'd40: return 32'sh00000001; 9'd41: return 32'sh00000001; 9'd42: return 32'sh00000001; 9'd43: return 32'sh00000001;
            9'd44: return 32'sh00000001; 9'd45: return 32'sh00000001; 9'd46: return 32'sh00000001; 9'd47: return 32'sh00000001;
            9'd48: return 32'sh00000001; 9'd49: return 32'sh00000001; 9'd50: return 32'sh00000001; 9'd51: return 32'sh00000001;
            9'd52: return 32'sh00000001; 9'd53: return 32'sh00000001; 9'd54: return 32'sh00000001; 9'd55: return 32'sh00000001;
            9'd56: return 32'sh00000001; 9'd57: return 32'sh00000002; 9'd58: return 32'sh00000002; 9'd59: return 32'sh00000002;
            9'd60: return 32'sh00000002; 9'd61: return 32'sh00000002; 9'd62: return 32'sh00000002; 9'd63: return 32'sh00000002;
            9'd64: return 32'sh00000002; 9'd65: return 32'sh00000002; 9'd66: return 32'sh00000002; 9'd67: return 32'sh00000002;
            9'd68: return 32'sh00000002; 9'd69: return 32'sh00000002; 9'd70: return 32'sh00000002; 9'd71: return 32'sh00000002;
            9'd72: return 32'sh00000002; 9'd73: return 32'sh00000002; 9'd74: return 32'sh00000002; 9'd75: return 32'sh00000002;
            9'd76: return 32'sh00000002; 9'd77: return 32'sh00000002; 9'd78: return 32'sh00000003; 9'd79: return 32'sh00000003;
            9'd80: return 32'sh00000003; 9'd81: return 32'sh00000003; 9'd82: return 32'sh00000003; 9'd83: return 32'sh00000003;
            9'd84: return 32'sh00000003; 9'd85: return 32'sh00000003; 9'd86: return 32'sh00000003; 9'd87: return 32'sh00000003;
            9'd88: return 32'sh00000003; 9'd89: return 32'sh00000003; 9'd90: return 32'sh00000003; 9'd91: return 32'sh00000003;
            9'd92: return 32'sh00000003; 9'd93: return 32'sh00000004; 9'd94: return 32'sh00000004; 9'd95: return 32'sh00000004;
            9'd96: return 32'sh00000004; 9'd97: return 32'sh00000004; 9'd98: return 32'sh00000004; 9'd99: return 32'sh00000004;
            9'd100: return 32'sh00000004; 9'd101: return 32'sh00000004; 9'd102: return 32'sh00000004; 9'd103: return 32'sh00000005;
            9'd104: return 32'sh00000005; 9'd105: return 32'sh00000005; 9'd106: return 32'sh00000005; 9'd107: return 32'sh00000005;
            9'd108: return 32'sh00000005; 9'd109: return 32'sh00000005; 9'd110: return 32'sh00000005; 9'd111: return 32'sh00000005;
            9'd112: return 32'sh00000006; 9'd113: return 32'sh00000006; 9'd114: return 32'sh00000006; 9'd115: return 32'sh00000006;
            9'd116: return 32'sh00000006; 9'd117: return 32'sh00000006; 9'd118: return 32'sh00000006; 9'd119: return 32'sh00000007;
            9'd120: return 32'sh00000007; 9'd121: return 32'sh00000007; 9'd122: return 32'sh00000007; 9'd123: return 32'sh00000007;
            9'd124: return 32'sh00000007; 9'd125: return 32'sh00000008; 9'd126: return 32'sh00000008; 9'd127: return 32'sh00000008;
            9'd128: return 32'sh00000008; 9'd129: return 32'sh00000008; 9'd130: return 32'sh00000008; 9'd131: return 32'sh00000009;
            9'd132: return 32'sh00000009; 9'd133: return 32'sh00000009; 9'd134: return 32'sh00000009; 9'd135: return 32'sh0000000A;
            9'd136: return 32'sh0000000A; 9'd137: return 32'sh0000000A; 9'd138: return 32'sh0000000A; 9'd139: return 32'sh0000000A;
            9'd140: return 32'sh0000000B; 9'd141: return 32'sh0000000B; 9'd142: return 32'sh0000000B; 9'd143: return 32'sh0000000B;
            9'd144: return 32'sh0000000C; 9'd145: return 32'sh0000000C; 9'd146: return 32'sh0000000C; 9'd147: return 32'sh0000000D;
            9'd148: return 32'sh0000000D; 9'd149: return 32'sh0000000D; 9'd150: return 32'sh0000000E; 9'd151: return 32'sh0000000E;
            9'd152: return 32'sh0000000E; 9'd153: return 32'sh0000000F; 9'd154: return 32'sh0000000F; 9'd155: return 32'sh0000000F;
            9'd156: return 32'sh00000010; 9'd157: return 32'sh00000010; 9'd158: return 32'sh00000010; 9'd159: return 32'sh00000011;
            9'd160: return 32'sh00000011; 9'd161: return 32'sh00000012; 9'd162: return 32'sh00000012; 9'd163: return 32'sh00000012;
            9'd164: return 32'sh00000013; 9'd165: return 32'sh00000013; 9'd166: return 32'sh00000014; 9'd167: return 32'sh00000014;
            9'd168: return 32'sh00000015; 9'd169: return 32'sh00000015; 9'd170: return 32'sh00000016; 9'd171: return 32'sh00000016;
            9'd172: return 32'sh00000017; 9'd173: return 32'sh00000017; 9'd174: return 32'sh00000018; 9'd175: return 32'sh00000018;
            9'd176: return 32'sh00000019; 9'd177: return 32'sh0000001A; 9'd178: return 32'sh0000001A; 9'd179: return 32'sh0000001B;
            9'd180: return 32'sh0000001B; 9'd181: return 32'sh0000001C; 9'd182: return 32'sh0000001D; 9'd183: return 32'sh0000001D;
            9'd184: return 32'sh0000001E; 9'd185: return 32'sh0000001F; 9'd186: return 32'sh0000001F; 9'd187: return 32'sh00000020;
            9'd188: return 32'sh00000021; 9'd189: return 32'sh00000022; 9'd190: return 32'sh00000023; 9'd191: return 32'sh00000023;
            9'd192: return 32'sh00000024; 9'd193: return 32'sh00000025; 9'd194: return 32'sh00000026; 9'd195: return 32'sh00000027;
            9'd196: return 32'sh00000028; 9'd197: return 32'sh00000029; 9'd198: return 32'sh0000002A; 9'd199: return 32'sh0000002B;
            9'd200: return 32'sh0000002C; 9'd201: return 32'sh0000002D; 9'd202: return 32'sh0000002E; 9'd203: return 32'sh0000002F;
            9'd204: return 32'sh00000030; 9'd205: return 32'sh00000031; 9'd206: return 32'sh00000032; 9'd207: return 32'sh00000034;
            9'd208: return 32'sh00000035; 9'd209: return 32'sh00000036; 9'd210: return 32'sh00000037; 9'd211: return 32'sh00000039;
            9'd212: return 32'sh0000003A; 9'd213: return 32'sh0000003B; 9'd214: return 32'sh0000003D; 9'd215: return 32'sh0000003E;
            9'd216: return 32'sh00000040; 9'd217: return 32'sh00000041; 9'd218: return 32'sh00000043; 9'd219: return 32'sh00000044;
            9'd220: return 32'sh00000046; 9'd221: return 32'sh00000048; 9'd222: return 32'sh00000049; 9'd223: return 32'sh0000004B;
            9'd224: return 32'sh0000004D; 9'd225: return 32'sh0000004F; 9'd226: return 32'sh00000050; 9'd227: return 32'sh00000052;
            9'd228: return 32'sh00000054; 9'd229: return 32'sh00000056; 9'd230: return 32'sh00000058; 9'd231: return 32'sh0000005A;
            9'd232: return 32'sh0000005D; 9'd233: return 32'sh0000005F; 9'd234: return 32'sh00000061; 9'd235: return 32'sh00000063;
            9'd236: return 32'sh00000066; 9'd237: return 32'sh00000068; 9'd238: return 32'sh0000006B; 9'd239: return 32'sh0000006D;
            9'd240: return 32'sh00000070; 9'd241: return 32'sh00000072; 9'd242: return 32'sh00000075; 9'd243: return 32'sh00000078;
            9'd244: return 32'sh0000007B; 9'd245: return 32'sh0000007E; 9'd246: return 32'sh00000081; 9'd247: return 32'sh00000084;
            9'd248: return 32'sh00000087; 9'd249: return 32'sh0000008A; 9'd250: return 32'sh0000008D; 9'd251: return 32'sh00000090;
            9'd252: return 32'sh00000094; 9'd253: return 32'sh00000097; 9'd254: return 32'sh0000009B; 9'd255: return 32'sh0000009F;
            9'd256: return 32'sh000000A2; 9'd257: return 32'sh000000A6; 9'd258: return 32'sh000000AA; 9'd259: return 32'sh000000AE;
            9'd260: return 32'sh000000B2; 9'd261: return 32'sh000000B7; 9'd262: return 32'sh000000BB; 9'd263: return 32'sh000000BF;
            9'd264: return 32'sh000000C4; 9'd265: return 32'sh000000C9; 9'd266: return 32'sh000000CD; 9'd267: return 32'sh000000D2;
            9'd268: return 32'sh000000D7; 9'd269: return 32'sh000000DC; 9'd270: return 32'sh000000E2; 9'd271: return 32'sh000000E7;
            9'd272: return 32'sh000000EC; 9'd273: return 32'sh000000F2; 9'd274: return 32'sh000000F8; 9'd275: return 32'sh000000FE;
            9'd276: return 32'sh00000104; 9'd277: return 32'sh0000010A; 9'd278: return 32'sh00000110; 9'd279: return 32'sh00000116;
            9'd280: return 32'sh0000011D; 9'd281: return 32'sh00000124; 9'd282: return 32'sh0000012B; 9'd283: return 32'sh00000132;
            9'd284: return 32'sh00000139; 9'd285: return 32'sh00000141; 9'd286: return 32'sh00000148; 9'd287: return 32'sh00000150;
            9'd288: return 32'sh00000158; 9'd289: return 32'sh00000160; 9'd290: return 32'sh00000168; 9'd291: return 32'sh00000171;
            9'd292: return 32'sh0000017A; 9'd293: return 32'sh00000183; 9'd294: return 32'sh0000018C; 9'd295: return 32'sh00000195;
            9'd296: return 32'sh0000019F; 9'd297: return 32'sh000001A9; 9'd298: return 32'sh000001B3; 9'd299: return 32'sh000001BD;
            9'd300: return 32'sh000001C8; 9'd301: return 32'sh000001D2; 9'd302: return 32'sh000001DD; 9'd303: return 32'sh000001E9;
            9'd304: return 32'sh000001F4; 9'd305: return 32'sh00000200; 9'd306: return 32'sh0000020C; 9'd307: return 32'sh00000219;
            9'd308: return 32'sh00000226; 9'd309: return 32'sh00000233; 9'd310: return 32'sh00000240; 9'd311: return 32'sh0000024E;
            9'd312: return 32'sh0000025C; 9'd313: return 32'sh0000026A; 9'd314: return 32'sh00000279; 9'd315: return 32'sh00000288;
            9'd316: return 32'sh00000297; 9'd317: return 32'sh000002A7; 9'd318: return 32'sh000002B7; 9'd319: return 32'sh000002C7;
            9'd320: return 32'sh000002D8; 9'd321: return 32'sh000002E9; 9'd322: return 32'sh000002FB; 9'd323: return 32'sh0000030D;
            9'd324: return 32'sh00000320; 9'd325: return 32'sh00000333; 9'd326: return 32'sh00000346; 9'd327: return 32'sh0000035A;
            9'd328: return 32'sh0000036E; 9'd329: return 32'sh00000383; 9'd330: return 32'sh00000398; 9'd331: return 32'sh000003AE;
            9'd332: return 32'sh000003C4; 9'd333: return 32'sh000003DB; 9'd334: return 32'sh000003F3; 9'd335: return 32'sh0000040B;
            9'd336: return 32'sh00000423; 9'd337: return 32'sh0000043C; 9'd338: return 32'sh00000456; 9'd339: return 32'sh00000470;
            9'd340: return 32'sh0000048B; 9'd341: return 32'sh000004A7; 9'd342: return 32'sh000004C3; 9'd343: return 32'sh000004E0;
            9'd344: return 32'sh000004FE; 9'd345: return 32'sh0000051C; 9'd346: return 32'sh0000053B; 9'd347: return 32'sh0000055B;
            9'd348: return 32'sh0000057B; 9'd349: return 32'sh0000059D; 9'd350: return 32'sh000005BF; 9'd351: return 32'sh000005E2;
            9'd352: return 32'sh00000605; 9'd353: return 32'sh0000062A; 9'd354: return 32'sh0000064F; 9'd355: return 32'sh00000676;
            9'd356: return 32'sh0000069D; 9'd357: return 32'sh000006C5; 9'd358: return 32'sh000006EE; 9'd359: return 32'sh00000718;
            9'd360: return 32'sh00000743; 9'd361: return 32'sh0000076F; 9'd362: return 32'sh0000079C; 9'd363: return 32'sh000007CB;
            9'd364: return 32'sh000007FA; 9'd365: return 32'sh0000082A; 9'd366: return 32'sh0000085C; 9'd367: return 32'sh0000088F;
            9'd368: return 32'sh000008C3; 9'd369: return 32'sh000008F8; 9'd370: return 32'sh0000092E; 9'd371: return 32'sh00000966;
            9'd372: return 32'sh0000099F; 9'd373: return 32'sh000009D9; 9'd374: return 32'sh00000A15; 9'd375: return 32'sh00000A52;
            9'd376: return 32'sh00000A91; 9'd377: return 32'sh00000AD1; 9'd378: return 32'sh00000B13; 9'd379: return 32'sh00000B56;
            9'd380: return 32'sh00000B9B; 9'd381: return 32'sh00000BE1; 9'd382: return 32'sh00000C29; 9'd383: return 32'sh00000C73;
            9'd384: return 32'sh00000CBF; 9'd385: return 32'sh00000D0C; 9'd386: return 32'sh00000D5B; 9'd387: return 32'sh00000DAD;
            9'd388: return 32'sh00000E00; 9'd389: return 32'sh00000E55; 9'd390: return 32'sh00000EAC; 9'd391: return 32'sh00000F05;
            9'd392: return 32'sh00000F60; 9'd393: return 32'sh00000FBD; 9'd394: return 32'sh0000101D; 9'd395: return 32'sh0000107E;
            9'd396: return 32'sh000010E3; 9'd397: return 32'sh00001149; 9'd398: return 32'sh000011B2; 9'd399: return 32'sh0000121D;
            9'd400: return 32'sh0000128B; 9'd401: return 32'sh000012FC; 9'd402: return 32'sh0000136F; 9'd403: return 32'sh000013E5;
            9'd404: return 32'sh0000145E; 9'd405: return 32'sh000014DA; 9'd406: return 32'sh00001558; 9'd407: return 32'sh000015DA;
            9'd408: return 32'sh0000165E; 9'd409: return 32'sh000016E6; 9'd410: return 32'sh00001771; 9'd411: return 32'sh00001800;
            9'd412: return 32'sh00001891; 9'd413: return 32'sh00001926; 9'd414: return 32'sh000019BF; 9'd415: return 32'sh00001A5B;
            9'd416: return 32'sh00001AFB; 9'd417: return 32'sh00001B9F; 9'd418: return 32'sh00001C47; 9'd419: return 32'sh00001CF3;
            9'd420: return 32'sh00001DA2; 9'd421: return 32'sh00001E56; 9'd422: return 32'sh00001F0E; 9'd423: return 32'sh00001FCB;
            9'd424: return 32'sh0000208C; 9'd425: return 32'sh00002152; 9'd426: return 32'sh0000221C; 9'd427: return 32'sh000022EB;
            9'd428: return 32'sh000023BF; 9'd429: return 32'sh00002498; 9'd430: return 32'sh00002576; 9'd431: return 32'sh00002659;
            9'd432: return 32'sh00002742; 9'd433: return 32'sh00002831; 9'd434: return 32'sh00002925; 9'd435: return 32'sh00002A1E;
            9'd436: return 32'sh00002B1E; 9'd437: return 32'sh00002C24; 9'd438: return 32'sh00002D30; 9'd439: return 32'sh00002E42;
            9'd440: return 32'sh00002F5B; 9'd441: return 32'sh0000307A; 9'd442: return 32'sh000031A1; 9'd443: return 32'sh000032CE;
            9'd444: return 32'sh00003402; 9'd445: return 32'sh0000353E; 9'd446: return 32'sh00003681; 9'd447: return 32'sh000037CC;
            9'd448: return 32'sh0000391F; 9'd449: return 32'sh00003A7A; 9'd450: return 32'sh00003BDD; 9'd451: return 32'sh00003D48;
            9'd452: return 32'sh00003EBC; 9'd453: return 32'sh00004039; 9'd454: return 32'sh000041BF; 9'd455: return 32'sh0000434E;
            9'd456: return 32'sh000044E7; 9'd457: return 32'sh00004689; 9'd458: return 32'sh00004835; 9'd459: return 32'sh000049EC;
            9'd460: return 32'sh00004BAC; 9'd461: return 32'sh00004D78; 9'd462: return 32'sh00004F4E; 9'd463: return 32'sh00005130;
            9'd464: return 32'sh0000531C; 9'd465: return 32'sh00005515; 9'd466: return 32'sh0000571A; 9'd467: return 32'sh0000592A;
            9'd468: return 32'sh00005B48; 9'd469: return 32'sh00005D72; 9'd470: return 32'sh00005FA9; 9'd471: return 32'sh000061EE;
            9'd472: return 32'sh00006440; 9'd473: return 32'sh000066A1; 9'd474: return 32'sh00006910; 9'd475: return 32'sh00006B8E;
            9'd476: return 32'sh00006E1B; 9'd477: return 32'sh000070B7; 9'd478: return 32'sh00007363; 9'd479: return 32'sh00007620;
            9'd480: return 32'sh000078ED; 9'd481: return 32'sh00007BCB; 9'd482: return 32'sh00007EBB; 9'd483: return 32'sh000081BC;
            9'd484: return 32'sh000084D0; 9'd485: return 32'sh000087F6; 9'd486: return 32'sh00008B2F; 9'd487: return 32'sh00008E7C;
            9'd488: return 32'sh000091DD; 9'd489: return 32'sh00009553; 9'd490: return 32'sh000098DD; 9'd491: return 32'sh00009C7D;
            9'd492: return 32'sh0000A033; 9'd493: return 32'sh0000A400; 9'd494: return 32'sh0000A7E4; 9'd495: return 32'sh0000ABDF;
            9'd496: return 32'sh0000AFF2; 9'd497: return 32'sh0000B41E; 9'd498: return 32'sh0000B864; 9'd499: return 32'sh0000BCC3;
            9'd500: return 32'sh0000C13D; 9'd501: return 32'sh0000C5D2; 9'd502: return 32'sh0000CA83; 9'd503: return 32'sh0000CF51;
            9'd504: return 32'sh0000D43B; 9'd505: return 32'sh0000D944; 9'd506: return 32'sh0000DE6B; 9'd507: return 32'sh0000E3B1;
            9'd508: return 32'sh0000E917; 9'd509: return 32'sh0000EE9E; 9'd510: return 32'sh0000F447; 9'd511: return 32'sh0000FA12;
            default: return 32'h00000000;
        endcase
    endfunction

    
    logic signed [31:0] mul_a, mul_b;
    logic signed [31:0] mul_result;
    logic mul_start, mul_valid;
    mul_q16 u_mul (
        .clk(clk),
        .start(mul_start),
        .a(mul_a),
        .b(mul_b),
        .result(mul_result),
        .valid(mul_valid)
    );

    logic signed [31:0] diff_reg, y0_reg, y1_reg, frac_reg;
    logic signed [31:0] mul1_reg, mul2_reg, mul3_reg;
    logic [8:0] idx_reg;

    typedef enum logic [3:0] { 
        ST_IDLE, 
        ST_WAIT_MUL1, ST_CALC_IDX,
        ST_WAIT_MUL2, ST_CALC_FRAC,
        ST_WAIT_MUL3, ST_CALC_RESULT
    } state_t;
    state_t state = ST_IDLE;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE;
            valid <= 1'b0;
            y <= 32'b0;
            mul_a <= 32'b0;
            mul_b <= 32'b0;
            mul_start <= 1'b0;
            diff_reg <= 32'b0; y0_reg <= 32'b0; y1_reg <= 32'b0; frac_reg <= 32'b0;
            mul1_reg <= 32'b0; mul2_reg <= 32'b0; mul3_reg <= 32'b0;
            idx_reg <= 8'b0;
        end else begin
            valid <= 1'b0;
            mul_start <= 1'b0;
            
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        if (x <= X_MIN) begin
                            y <= rom_lookup(9'd0); valid <= 1'b1;
                        end else if (x >= 0) begin
                            y <= 32'sh00010000; valid <= 1'b1;
                        end else begin
                            diff_reg <= x - X_MIN;
                            mul_a <= x - X_MIN; 
                            mul_b <= INV_STEP;
                            mul_start <= 1'b1;
                            state <= ST_WAIT_MUL1;
                        end
                    end
                end
                
                ST_WAIT_MUL1: begin
                    if (mul_valid) begin
                        mul1_reg <= mul_result;
                        state <= ST_CALC_IDX;
                    end
                end
                
                ST_CALC_IDX: begin
                    idx_reg <= mul1_reg[24:16]; 
                    y0_reg <= rom_lookup(mul1_reg[24:16]);
                    y1_reg <= (mul1_reg[24:16] == 9'd511) ? 
                              rom_lookup(9'd511) : rom_lookup(mul1_reg[24:16] + 9'd1);
                    mul_a <= {mul1_reg[24:16], 16'b0};
                    mul_b <= STEP;
                    mul_start <= 1'b1;
                    state <= ST_WAIT_MUL2;
                end
                
                ST_WAIT_MUL2: begin
                    if (mul_valid) begin
                        mul2_reg <= mul_result;
                        state <= ST_CALC_FRAC;
                    end
                end
                
                ST_CALC_FRAC: begin
                    frac_reg <= diff_reg - mul2_reg;
                    
                    mul_a <= y1_reg - y0_reg;
                    mul_b <= diff_reg - mul2_reg; 
                    mul_start <= 1'b1;
                    state <= ST_WAIT_MUL3;
                end
                
                ST_WAIT_MUL3: begin
                    if (mul_valid) begin
                        mul3_reg <= mul_result;
                        state <= ST_CALC_RESULT;
                    end
                end
                
                ST_CALC_RESULT: begin
                    y <= y0_reg + mul3_reg;
                    valid <= 1'b1;
                    state <= ST_IDLE;
                end 
                
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

// -1046.8514515542781 <= x <= 1046.8514515542781
module normalCDF (
    input  logic clk,
    input logic rst,
    input  logic start,
    input  logic signed [31:0] x,
    output logic signed [31:0] y,
    output logic valid
);
    localparam logic signed [31:0] X_MAX = 32'sh00080000;
    localparam logic signed [31:0] STEP  = 32'sh00000400;
    localparam logic signed [31:0] INV_STEP = 32'sh00400000;
    localparam logic signed [31:0] ONE = 32'sh00010000;

    function automatic signed [31:0] rom_lookup(input logic [8:0] idx);
        unique case (idx)
            9'd0: return 32'sh00008000; 9'd1: return 32'sh00008199; 9'd2: return 32'sh00008331; 9'd3: return 32'sh000084C9;
            9'd4: return 32'sh00008661; 9'd5: return 32'sh000087F9; 9'd6: return 32'sh00008990; 9'd7: return 32'sh00008B26;
            9'd8: return 32'sh00008CBC; 9'd9: return 32'sh00008E51; 9'd10: return 32'sh00008FE5; 9'd11: return 32'sh00009178;
            9'd12: return 32'sh0000930A; 9'd13: return 32'sh0000949A; 9'd14: return 32'sh0000962A; 9'd15: return 32'sh000097B8;
            9'd16: return 32'sh00009945; 9'd17: return 32'sh00009AD0; 9'd18: return 32'sh00009C5A; 9'd19: return 32'sh00009DE1;
            9'd20: return 32'sh00009F67; 9'd21: return 32'sh0000A0EB; 9'd22: return 32'sh0000A26D; 9'd23: return 32'sh0000A3EE;
            9'd24: return 32'sh0000A56B; 9'd25: return 32'sh0000A6E7; 9'd26: return 32'sh0000A860; 9'd27: return 32'sh0000A9D7;
            9'd28: return 32'sh0000AB4C; 9'd29: return 32'sh0000ACBE; 9'd30: return 32'sh0000AE2D; 9'd31: return 32'sh0000AF9A;
            9'd32: return 32'sh0000B104; 9'd33: return 32'sh0000B26B; 9'd34: return 32'sh0000B3CF; 9'd35: return 32'sh0000B530;
            9'd36: return 32'sh0000B68F; 9'd37: return 32'sh0000B7EA; 9'd38: return 32'sh0000B942; 9'd39: return 32'sh0000BA97;
            9'd40: return 32'sh0000BBE8; 9'd41: return 32'sh0000BD37; 9'd42: return 32'sh0000BE82; 9'd43: return 32'sh0000BFC9;
            9'd44: return 32'sh0000C10E; 9'd45: return 32'sh0000C24F; 9'd46: return 32'sh0000C38C; 9'd47: return 32'sh0000C4C6;
            9'd48: return 32'sh0000C5FC; 9'd49: return 32'sh0000C72E; 9'd50: return 32'sh0000C85D; 9'd51: return 32'sh0000C988;
            9'd52: return 32'sh0000CAB0; 9'd53: return 32'sh0000CBD4; 9'd54: return 32'sh0000CCF4; 9'd55: return 32'sh0000CE10;
            9'd56: return 32'sh0000CF29; 9'd57: return 32'sh0000D03D; 9'd58: return 32'sh0000D14E; 9'd59: return 32'sh0000D25B;
            9'd60: return 32'sh0000D364; 9'd61: return 32'sh0000D46A; 9'd62: return 32'sh0000D56B; 9'd63: return 32'sh0000D669;
            9'd64: return 32'sh0000D762; 9'd65: return 32'sh0000D858; 9'd66: return 32'sh0000D94A; 9'd67: return 32'sh0000DA38;
            9'd68: return 32'sh0000DB23; 9'd69: return 32'sh0000DC09; 9'd70: return 32'sh0000DCEB; 9'd71: return 32'sh0000DDCA;
            9'd72: return 32'sh0000DEA5; 9'd73: return 32'sh0000DF7C; 9'd74: return 32'sh0000E04F; 9'd75: return 32'sh0000E11F;
            9'd76: return 32'sh0000E1EB; 9'd77: return 32'sh0000E2B2; 9'd78: return 32'sh0000E377; 9'd79: return 32'sh0000E437;
            9'd80: return 32'sh0000E4F4; 9'd81: return 32'sh0000E5AD; 9'd82: return 32'sh0000E663; 9'd83: return 32'sh0000E715;
            9'd84: return 32'sh0000E7C3; 9'd85: return 32'sh0000E86E; 9'd86: return 32'sh0000E916; 9'd87: return 32'sh0000E9B9;
            9'd88: return 32'sh0000EA5A; 9'd89: return 32'sh0000EAF7; 9'd90: return 32'sh0000EB91; 9'd91: return 32'sh0000EC27;
            9'd92: return 32'sh0000ECBA; 9'd93: return 32'sh0000ED4A; 9'd94: return 32'sh0000EDD6; 9'd95: return 32'sh0000EE60;
            9'd96: return 32'sh0000EEE6; 9'd97: return 32'sh0000EF69; 9'd98: return 32'sh0000EFE9; 9'd99: return 32'sh0000F066;
            9'd100: return 32'sh0000F0E0; 9'd101: return 32'sh0000F157; 9'd102: return 32'sh0000F1CB; 9'd103: return 32'sh0000F23C;
            9'd104: return 32'sh0000F2AB; 9'd105: return 32'sh0000F317; 9'd106: return 32'sh0000F380; 9'd107: return 32'sh0000F3E6;
            9'd108: return 32'sh0000F449; 9'd109: return 32'sh0000F4AB; 9'd110: return 32'sh0000F509; 9'd111: return 32'sh0000F565;
            9'd112: return 32'sh0000F5BF; 9'd113: return 32'sh0000F616; 9'd114: return 32'sh0000F66B; 9'd115: return 32'sh0000F6BD;
            9'd116: return 32'sh0000F70D; 9'd117: return 32'sh0000F75B; 9'd118: return 32'sh0000F7A7; 9'd119: return 32'sh0000F7F0;
            9'd120: return 32'sh0000F838; 9'd121: return 32'sh0000F87D; 9'd122: return 32'sh0000F8C1; 9'd123: return 32'sh0000F902;
            9'd124: return 32'sh0000F942; 9'd125: return 32'sh0000F97F; 9'd126: return 32'sh0000F9BB; 9'd127: return 32'sh0000F9F5;
            9'd128: return 32'sh0000FA2D; 9'd129: return 32'sh0000FA63; 9'd130: return 32'sh0000FA98; 9'd131: return 32'sh0000FACB;
            9'd132: return 32'sh0000FAFD; 9'd133: return 32'sh0000FB2D; 9'd134: return 32'sh0000FB5B; 9'd135: return 32'sh0000FB88;
            9'd136: return 32'sh0000FBB3; 9'd137: return 32'sh0000FBDD; 9'd138: return 32'sh0000FC06; 9'd139: return 32'sh0000FC2D;
            9'd140: return 32'sh0000FC53; 9'd141: return 32'sh0000FC78; 9'd142: return 32'sh0000FC9C; 9'd143: return 32'sh0000FCBE;
            9'd144: return 32'sh0000FCDF; 9'd145: return 32'sh0000FCFF; 9'd146: return 32'sh0000FD1E; 9'd147: return 32'sh0000FD3B;
            9'd148: return 32'sh0000FD58; 9'd149: return 32'sh0000FD74; 9'd150: return 32'sh0000FD8E; 9'd151: return 32'sh0000FDA8;
            9'd152: return 32'sh0000FDC1; 9'd153: return 32'sh0000FDD9; 9'd154: return 32'sh0000FDF0; 9'd155: return 32'sh0000FE06;
            9'd156: return 32'sh0000FE1B; 9'd157: return 32'sh0000FE30; 9'd158: return 32'sh0000FE44; 9'd159: return 32'sh0000FE57;
            9'd160: return 32'sh0000FE69; 9'd161: return 32'sh0000FE7B; 9'd162: return 32'sh0000FE8C; 9'd163: return 32'sh0000FE9C;
            9'd164: return 32'sh0000FEAB; 9'd165: return 32'sh0000FEBA; 9'd166: return 32'sh0000FEC9; 9'd167: return 32'sh0000FED7;
            9'd168: return 32'sh0000FEE4; 9'd169: return 32'sh0000FEF1; 9'd170: return 32'sh0000FEFD; 9'd171: return 32'sh0000FF09;
            9'd172: return 32'sh0000FF14; 9'd173: return 32'sh0000FF1F; 9'd174: return 32'sh0000FF29; 9'd175: return 32'sh0000FF33;
            9'd176: return 32'sh0000FF3D; 9'd177: return 32'sh0000FF46; 9'd178: return 32'sh0000FF4F; 9'd179: return 32'sh0000FF57;
            9'd180: return 32'sh0000FF5F; 9'd181: return 32'sh0000FF67; 9'd182: return 32'sh0000FF6E; 9'd183: return 32'sh0000FF75;
            9'd184: return 32'sh0000FF7C; 9'd185: return 32'sh0000FF82; 9'd186: return 32'sh0000FF88; 9'd187: return 32'sh0000FF8E;
            9'd188: return 32'sh0000FF94; 9'd189: return 32'sh0000FF99; 9'd190: return 32'sh0000FF9E; 9'd191: return 32'sh0000FFA3;
            9'd192: return 32'sh0000FFA8; 9'd193: return 32'sh0000FFAC; 9'd194: return 32'sh0000FFB0; 9'd195: return 32'sh0000FFB4;
            9'd196: return 32'sh0000FFB8; 9'd197: return 32'sh0000FFBC; 9'd198: return 32'sh0000FFBF; 9'd199: return 32'sh0000FFC3;
            9'd200: return 32'sh0000FFC6; 9'd201: return 32'sh0000FFC9; 9'd202: return 32'sh0000FFCC; 9'd203: return 32'sh0000FFCE;
            9'd204: return 32'sh0000FFD1; 9'd205: return 32'sh0000FFD3; 9'd206: return 32'sh0000FFD6; 9'd207: return 32'sh0000FFD8;
            9'd208: return 32'sh0000FFDA; 9'd209: return 32'sh0000FFDC; 9'd210: return 32'sh0000FFDE; 9'd211: return 32'sh0000FFE0;
            9'd212: return 32'sh0000FFE2; 9'd213: return 32'sh0000FFE3; 9'd214: return 32'sh0000FFE5; 9'd215: return 32'sh0000FFE6;
            9'd216: return 32'sh0000FFE8; 9'd217: return 32'sh0000FFE9; 9'd218: return 32'sh0000FFEA; 9'd219: return 32'sh0000FFEC;
            9'd220: return 32'sh0000FFED; 9'd221: return 32'sh0000FFEE; 9'd222: return 32'sh0000FFEF; 9'd223: return 32'sh0000FFF0;
            9'd224: return 32'sh0000FFF1; 9'd225: return 32'sh0000FFF2; 9'd226: return 32'sh0000FFF2; 9'd227: return 32'sh0000FFF3;
            9'd228: return 32'sh0000FFF4; 9'd229: return 32'sh0000FFF5; 9'd230: return 32'sh0000FFF5; 9'd231: return 32'sh0000FFF6;
            9'd232: return 32'sh0000FFF7; 9'd233: return 32'sh0000FFF7; 9'd234: return 32'sh0000FFF8; 9'd235: return 32'sh0000FFF8;
            9'd236: return 32'sh0000FFF9; 9'd237: return 32'sh0000FFF9; 9'd238: return 32'sh0000FFF9; 9'd239: return 32'sh0000FFFA;
            9'd240: return 32'sh0000FFFA; 9'd241: return 32'sh0000FFFB; 9'd242: return 32'sh0000FFFB; 9'd243: return 32'sh0000FFFB;
            9'd244: return 32'sh0000FFFB; 9'd245: return 32'sh0000FFFC; 9'd246: return 32'sh0000FFFC; 9'd247: return 32'sh0000FFFC;
            9'd248: return 32'sh0000FFFD; 9'd249: return 32'sh0000FFFD; 9'd250: return 32'sh0000FFFD; 9'd251: return 32'sh0000FFFD;
            9'd252: return 32'sh0000FFFD; 9'd253: return 32'sh0000FFFD; 9'd254: return 32'sh0000FFFE; 9'd255: return 32'sh0000FFFE;
            9'd256: return 32'sh0000FFFE; 9'd257: return 32'sh0000FFFE; 9'd258: return 32'sh0000FFFE; 9'd259: return 32'sh0000FFFE;
            9'd260: return 32'sh0000FFFE; 9'd261: return 32'sh0000FFFF; 9'd262: return 32'sh0000FFFF; 9'd263: return 32'sh0000FFFF;
            9'd264: return 32'sh0000FFFF; 9'd265: return 32'sh0000FFFF; 9'd266: return 32'sh0000FFFF; 9'd267: return 32'sh0000FFFF;
            9'd268: return 32'sh0000FFFF; 9'd269: return 32'sh0000FFFF; 9'd270: return 32'sh0000FFFF; 9'd271: return 32'sh0000FFFF;
            9'd272: return 32'sh0000FFFF; 9'd273: return 32'sh0000FFFF; 9'd274: return 32'sh0000FFFF; 9'd275: return 32'sh0000FFFF;
            9'd276: return 32'sh0000FFFF; 9'd277: return 32'sh00010000; 9'd278: return 32'sh00010000; 9'd279: return 32'sh00010000;
            9'd280: return 32'sh00010000; 9'd281: return 32'sh00010000; 9'd282: return 32'sh00010000; 9'd283: return 32'sh00010000;
            9'd284: return 32'sh00010000; 9'd285: return 32'sh00010000; 9'd286: return 32'sh00010000; 9'd287: return 32'sh00010000;
            9'd288: return 32'sh00010000; 9'd289: return 32'sh00010000; 9'd290: return 32'sh00010000; 9'd291: return 32'sh00010000;
            9'd292: return 32'sh00010000; 9'd293: return 32'sh00010000; 9'd294: return 32'sh00010000; 9'd295: return 32'sh00010000;
            9'd296: return 32'sh00010000; 9'd297: return 32'sh00010000; 9'd298: return 32'sh00010000; 9'd299: return 32'sh00010000;
            9'd300: return 32'sh00010000; 9'd301: return 32'sh00010000; 9'd302: return 32'sh00010000; 9'd303: return 32'sh00010000;
            9'd304: return 32'sh00010000; 9'd305: return 32'sh00010000; 9'd306: return 32'sh00010000; 9'd307: return 32'sh00010000;
            9'd308: return 32'sh00010000; 9'd309: return 32'sh00010000; 9'd310: return 32'sh00010000; 9'd311: return 32'sh00010000;
            9'd312: return 32'sh00010000; 9'd313: return 32'sh00010000; 9'd314: return 32'sh00010000; 9'd315: return 32'sh00010000;
            9'd316: return 32'sh00010000; 9'd317: return 32'sh00010000; 9'd318: return 32'sh00010000; 9'd319: return 32'sh00010000;
            9'd320: return 32'sh00010000; 9'd321: return 32'sh00010000; 9'd322: return 32'sh00010000; 9'd323: return 32'sh00010000;
            9'd324: return 32'sh00010000; 9'd325: return 32'sh00010000; 9'd326: return 32'sh00010000; 9'd327: return 32'sh00010000;
            9'd328: return 32'sh00010000; 9'd329: return 32'sh00010000; 9'd330: return 32'sh00010000; 9'd331: return 32'sh00010000;
            9'd332: return 32'sh00010000; 9'd333: return 32'sh00010000; 9'd334: return 32'sh00010000; 9'd335: return 32'sh00010000;
            9'd336: return 32'sh00010000; 9'd337: return 32'sh00010000; 9'd338: return 32'sh00010000; 9'd339: return 32'sh00010000;
            9'd340: return 32'sh00010000; 9'd341: return 32'sh00010000; 9'd342: return 32'sh00010000; 9'd343: return 32'sh00010000;
            9'd344: return 32'sh00010000; 9'd345: return 32'sh00010000; 9'd346: return 32'sh00010000; 9'd347: return 32'sh00010000;
            9'd348: return 32'sh00010000; 9'd349: return 32'sh00010000; 9'd350: return 32'sh00010000; 9'd351: return 32'sh00010000;
            9'd352: return 32'sh00010000; 9'd353: return 32'sh00010000; 9'd354: return 32'sh00010000; 9'd355: return 32'sh00010000;
            9'd356: return 32'sh00010000; 9'd357: return 32'sh00010000; 9'd358: return 32'sh00010000; 9'd359: return 32'sh00010000;
            9'd360: return 32'sh00010000; 9'd361: return 32'sh00010000; 9'd362: return 32'sh00010000; 9'd363: return 32'sh00010000;
            9'd364: return 32'sh00010000; 9'd365: return 32'sh00010000; 9'd366: return 32'sh00010000; 9'd367: return 32'sh00010000;
            9'd368: return 32'sh00010000; 9'd369: return 32'sh00010000; 9'd370: return 32'sh00010000; 9'd371: return 32'sh00010000;
            9'd372: return 32'sh00010000; 9'd373: return 32'sh00010000; 9'd374: return 32'sh00010000; 9'd375: return 32'sh00010000;
            9'd376: return 32'sh00010000; 9'd377: return 32'sh00010000; 9'd378: return 32'sh00010000; 9'd379: return 32'sh00010000;
            9'd380: return 32'sh00010000; 9'd381: return 32'sh00010000; 9'd382: return 32'sh00010000; 9'd383: return 32'sh00010000;
            9'd384: return 32'sh00010000; 9'd385: return 32'sh00010000; 9'd386: return 32'sh00010000; 9'd387: return 32'sh00010000;
            9'd388: return 32'sh00010000; 9'd389: return 32'sh00010000; 9'd390: return 32'sh00010000; 9'd391: return 32'sh00010000;
            9'd392: return 32'sh00010000; 9'd393: return 32'sh00010000; 9'd394: return 32'sh00010000; 9'd395: return 32'sh00010000;
            9'd396: return 32'sh00010000; 9'd397: return 32'sh00010000; 9'd398: return 32'sh00010000; 9'd399: return 32'sh00010000;
            9'd400: return 32'sh00010000; 9'd401: return 32'sh00010000; 9'd402: return 32'sh00010000; 9'd403: return 32'sh00010000;
            9'd404: return 32'sh00010000; 9'd405: return 32'sh00010000; 9'd406: return 32'sh00010000; 9'd407: return 32'sh00010000;
            9'd408: return 32'sh00010000; 9'd409: return 32'sh00010000; 9'd410: return 32'sh00010000; 9'd411: return 32'sh00010000;
            9'd412: return 32'sh00010000; 9'd413: return 32'sh00010000; 9'd414: return 32'sh00010000; 9'd415: return 32'sh00010000;
            9'd416: return 32'sh00010000; 9'd417: return 32'sh00010000; 9'd418: return 32'sh00010000; 9'd419: return 32'sh00010000;
            9'd420: return 32'sh00010000; 9'd421: return 32'sh00010000; 9'd422: return 32'sh00010000; 9'd423: return 32'sh00010000;
            9'd424: return 32'sh00010000; 9'd425: return 32'sh00010000; 9'd426: return 32'sh00010000; 9'd427: return 32'sh00010000;
            9'd428: return 32'sh00010000; 9'd429: return 32'sh00010000; 9'd430: return 32'sh00010000; 9'd431: return 32'sh00010000;
            9'd432: return 32'sh00010000; 9'd433: return 32'sh00010000; 9'd434: return 32'sh00010000; 9'd435: return 32'sh00010000;
            9'd436: return 32'sh00010000; 9'd437: return 32'sh00010000; 9'd438: return 32'sh00010000; 9'd439: return 32'sh00010000;
            9'd440: return 32'sh00010000; 9'd441: return 32'sh00010000; 9'd442: return 32'sh00010000; 9'd443: return 32'sh00010000;
            9'd444: return 32'sh00010000; 9'd445: return 32'sh00010000; 9'd446: return 32'sh00010000; 9'd447: return 32'sh00010000;
            9'd448: return 32'sh00010000; 9'd449: return 32'sh00010000; 9'd450: return 32'sh00010000; 9'd451: return 32'sh00010000;
            9'd452: return 32'sh00010000; 9'd453: return 32'sh00010000; 9'd454: return 32'sh00010000; 9'd455: return 32'sh00010000;
            9'd456: return 32'sh00010000; 9'd457: return 32'sh00010000; 9'd458: return 32'sh00010000; 9'd459: return 32'sh00010000;
            9'd460: return 32'sh00010000; 9'd461: return 32'sh00010000; 9'd462: return 32'sh00010000; 9'd463: return 32'sh00010000;
            9'd464: return 32'sh00010000; 9'd465: return 32'sh00010000; 9'd466: return 32'sh00010000; 9'd467: return 32'sh00010000;
            9'd468: return 32'sh00010000; 9'd469: return 32'sh00010000; 9'd470: return 32'sh00010000; 9'd471: return 32'sh00010000;
            9'd472: return 32'sh00010000; 9'd473: return 32'sh00010000; 9'd474: return 32'sh00010000; 9'd475: return 32'sh00010000;
            9'd476: return 32'sh00010000; 9'd477: return 32'sh00010000; 9'd478: return 32'sh00010000; 9'd479: return 32'sh00010000;
            9'd480: return 32'sh00010000; 9'd481: return 32'sh00010000; 9'd482: return 32'sh00010000; 9'd483: return 32'sh00010000;
            9'd484: return 32'sh00010000; 9'd485: return 32'sh00010000; 9'd486: return 32'sh00010000; 9'd487: return 32'sh00010000;
            9'd488: return 32'sh00010000; 9'd489: return 32'sh00010000; 9'd490: return 32'sh00010000; 9'd491: return 32'sh00010000;
            9'd492: return 32'sh00010000; 9'd493: return 32'sh00010000; 9'd494: return 32'sh00010000; 9'd495: return 32'sh00010000;
            9'd496: return 32'sh00010000; 9'd497: return 32'sh00010000; 9'd498: return 32'sh00010000; 9'd499: return 32'sh00010000;
            9'd500: return 32'sh00010000; 9'd501: return 32'sh00010000; 9'd502: return 32'sh00010000; 9'd503: return 32'sh00010000;
            9'd504: return 32'sh00010000; 9'd505: return 32'sh00010000; 9'd506: return 32'sh00010000; 9'd507: return 32'sh00010000;
            9'd508: return 32'sh00010000; 9'd509: return 32'sh00010000; 9'd510: return 32'sh00010000; 9'd511: return 32'sh00010000;
            default: return 32'h00008000;
        endcase
    endfunction

    
    
    logic signed [31:0] mul_a, mul_b, mul_result;
    logic mul_start, mul_valid;
    mul_q16 u_mul (.clk(clk), .start(mul_start), .a(mul_a), .b(mul_b), .result(mul_result), .valid(mul_valid));

    logic signed [31:0] xpos_reg, y0_reg, y1_reg, frac_reg;
    logic signed [31:0] mul1_reg, mul2_reg, mul3_reg;
    logic signed [31:0] tmp_y_reg, inv_tmp_y_reg;
    logic [8:0] idx_reg;
    logic sign_reg;

    typedef enum logic [3:0] { 
        ST_IDLE, ST_WAIT_MUL1, ST_CALC_IDX,
        ST_WAIT_MUL2, ST_CALC_FRAC,
        ST_WAIT_MUL3, ST_CALC_SUM, 
        ST_CALC_OPOS, ST_CALC_RESULT
    } state_t;
    state_t state = ST_IDLE;

    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= ST_IDLE; valid <= 1'b0; y <= 32'b0;
            mul_a <= 32'b0; mul_b <= 32'b0; mul_start <= 1'b0;
            xpos_reg <= 32'b0; y0_reg <= 32'b0; y1_reg <= 32'b0; frac_reg <= 32'b0;
            mul1_reg <= 32'b0; mul2_reg <= 32'b0; mul3_reg <= 32'b0;
            idx_reg <= 8'b0; sign_reg <= 1'b0;
        end else begin
            valid <= 1'b0; mul_start <= 1'b0;
            case (state)
                ST_IDLE: begin
                    if (start) begin
                        if (x <= -X_MAX) begin 
                            y <= 32'sh00000000;
                            valid <= 1'b1;
                        end else if (x >= X_MAX) begin 
                            y <= ONE;
                            valid <= 1'b1;
                        end else begin
                            sign_reg <= x[31];
                            xpos_reg <= x[31] ? -x : x;
                            mul_a <= x[31] ? -x : x; mul_b <= INV_STEP; mul_start <= 1'b1;
                            state <= ST_WAIT_MUL1;
                        end
                    end
                end
                ST_WAIT_MUL1: begin
                    if (mul_valid) begin 
                        mul1_reg <= mul_result;
                        state <= ST_CALC_IDX;
                    end
                end
                ST_CALC_IDX: begin
                    idx_reg <= mul1_reg[24:16]; 
                    y0_reg <= rom_lookup(mul1_reg[24:16]);
                    y1_reg <= (mul1_reg[24:16] == 9'd511) ? 
                              rom_lookup(9'd511) : rom_lookup(mul1_reg[24:16] + 9'd1);
                    mul_a <= {mul1_reg[24:16], 16'b0};
                    mul_b <= STEP; mul_start <= 1'b1;
                    state <= ST_WAIT_MUL2;
                end
                ST_WAIT_MUL2: begin
                    if (mul_valid) begin
                        mul2_reg <= mul_result;
                        state <= ST_CALC_FRAC;
                    end
                end
                ST_CALC_FRAC: begin
                    frac_reg <= xpos_reg - mul2_reg;
                    mul_a <= y1_reg - y0_reg; mul_b <= xpos_reg - mul2_reg; mul_start <= 1'b1;
                    state <= ST_WAIT_MUL3;
                end
                ST_WAIT_MUL3: begin
                    if (mul_valid) begin
                        mul3_reg <= mul_result;
                        state <= ST_CALC_SUM;
                    end
                end
                ST_CALC_SUM: begin
                    tmp_y_reg <= y0_reg + mul3_reg;
                    state <= ST_CALC_OPOS;
                end
                ST_CALC_OPOS: begin
                    inv_tmp_y_reg <= ONE - tmp_y_reg;
                    state <= ST_CALC_RESULT;
                end
                ST_CALC_RESULT: begin
                    y <= sign_reg ? inv_tmp_y_reg : tmp_y_reg;
                    valid <= 1'b1; state <= ST_IDLE;
                end 
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule

// Call - 0, Put - 1
// Ошибка в среднем в третьем знаке после запятой, можно доработать/взять числа поточнее, есть что доработать при наличии времени
module bs_price #(
    parameter logic signed [31:0] r = 32'sh00002666
) (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 start,
    input  logic                 opt_type,
    input  logic signed [31:0]   S,
    input  logic signed [31:0]   K,
    input  logic signed [31:0]   T,
    input  logic signed [31:0]   sigma,
    output logic signed [31:0]   price,
    output logic                 done,
    output logic                 busy
);
    localparam logic signed [31:0] denom_min = 32'sh00003333;
    typedef enum logic [5:0] {
        IDLE,
        ST_SQRT_WAIT,
        ST_DIV_SK_WAIT,
        ST_LN_WAIT,
        ST_MUL_RT_WAIT,
        ST_EXP_WAIT,
        ST_MUL_SIGMA2_WAIT,
        ST_MUL_R_TERM_WAIT,
        ST_MUL_SIGMA_SQRT_WAIT,
        ST_DIV_D1_WAIT,
        ST_CDF1_WAIT,
        ST_CDF2_WAIT,
        ST_MUL_K_EXP_WAIT,
        ST_MUL_S_CDF1_WAIT,
        ST_MUL_KEXP_CDF2_WAIT,
        ST_MUL_INV_CDF2_WAIT,
        ST_MUL_INV_CDF1_WAIT,
        ST_ABS,
        ST_DONE
    } state_t;
    
    state_t state = IDLE;
    
    logic signed [31:0] mul_a, mul_b, mul_result;
    logic mul_start, mul_valid;
    mul_q16 u_mul (
        .clk(clk), .start(mul_start), .a(mul_a), .b(mul_b), 
        .result(mul_result), .valid(mul_valid)
    );
    
    logic signed [31:0] div_a, div_b, div_result;
    logic div_start, div_busy, div_valid;
    div_q16 u_div (
        .clk(clk), .start(div_start), .busy(div_busy), .valid(div_valid),
        .num(div_a), .den(div_b), .quo(div_result), .rem()
    );
    
    logic sqrt_start, sqrt_busy, sqrt_valid;
    logic signed [31:0] sqrt_root;
    sqrt u_sqrt (
        .clk(clk), .start(sqrt_start), .busy(sqrt_busy), .valid(sqrt_valid),
        .rad(T), .root(sqrt_root), .rem()
    );
    
    logic ln_start, ln_valid;
    logic signed [31:0] ln_x, ln_out;
    log u_ln (
        .clk(clk), .rst(rst), .start(ln_start), .x(ln_x), 
        .y(ln_out), .valid(ln_valid)
    );
    
    logic exp_start, exp_valid;
    logic signed [31:0] exp_x, exp_out;
    exp u_exp (
        .clk(clk), .rst(rst), .start(exp_start), .x(exp_x), 
        .y(exp_out), .valid(exp_valid)
    );
    
    logic cdf_start, cdf_valid;
    logic signed [31:0] cdf_x, cdf_out;
    normalCDF u_cdf (
        .clk(clk), .rst(rst), .start(cdf_start), .x(cdf_x), 
        .y(cdf_out), .valid(cdf_valid)
    );
    
    logic signed [31:0] sqrt_T_reg;
    logic signed [31:0] S_div_K_reg;
    logic signed [31:0] ln_val_reg;
    logic signed [31:0] exp_val_reg;
    logic signed [31:0] sigma_sq_reg;
    logic signed [31:0] r_term_reg;
    logic signed [31:0] sigma_sqrt_T_reg;
    logic signed [31:0] d1_reg, d2_reg;
    logic signed [31:0] cdf_d1_reg, cdf_d2_reg;
    logic signed [31:0] k_exp_reg;
    logic signed [31:0] call_reg, put_reg;
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state <= IDLE;
            done <= 1'b0;
            busy <= 1'b0;
            price <= 32'b0;
            
            sqrt_start <= 1'b0;
            div_start <= 1'b0;
            ln_start <= 1'b0;
            exp_start <= 1'b0;
            cdf_start <= 1'b0;
            mul_start <= 1'b0;
            
            mul_a <= 32'b0; mul_b <= 32'b0;
            div_a <= 32'b0; div_b <= 32'b0;
            ln_x <= 32'b0; exp_x <= 32'b0; cdf_x <= 32'b0;
            
            sqrt_T_reg <= 32'b0; S_div_K_reg <= 32'b0;
            ln_val_reg <= 32'b0; exp_val_reg <= 32'b0;
            sigma_sq_reg <= 32'b0; r_term_reg <= 32'b0;
            sigma_sqrt_T_reg <= 32'b0;
            d1_reg <= 32'b0; d2_reg <= 32'b0;
            cdf_d1_reg <= 32'b0; cdf_d2_reg <= 32'b0;
            k_exp_reg <= 32'b0; call_reg <= 32'b0; put_reg <= 32'b0;
            
        end else begin
            sqrt_start <= 1'b0;
            div_start <= 1'b0;
            ln_start <= 1'b0;
            exp_start <= 1'b0;
            cdf_start <= 1'b0;
            mul_start <= 1'b0;
            done <= 1'b0;
            
            case (state)
                IDLE: begin
                    if (start) begin
                        busy <= 1'b1;
                        sqrt_start <= 1'b1;
                        state <= ST_SQRT_WAIT;
                    end else begin
                        busy <= 1'b0;
                    end
                end
                
                ST_SQRT_WAIT: begin
                    if (sqrt_valid) begin
                        sqrt_T_reg <= sqrt_root;
                        div_a <= S; div_b <= K;
                        div_start <= 1'b1;
                        state <= ST_DIV_SK_WAIT;
                    end
                end
                
                ST_DIV_SK_WAIT: begin
                    if (div_valid) begin
                        S_div_K_reg <= div_result;
                        ln_x <= div_result;
                        ln_start <= 1'b1;
                        state <= ST_LN_WAIT;
                    end
                end
                
                ST_LN_WAIT: begin
                    if (ln_valid) begin
                        ln_val_reg <= ln_out;
                        mul_a <= r; mul_b <= T;
                        mul_start <= 1'b1;
                        state <= ST_MUL_RT_WAIT;
                    end
                end
                
                ST_MUL_RT_WAIT: begin
                    if (mul_valid) begin
                        exp_x <= -mul_result;
                        exp_start <= 1'b1;
                        state <= ST_EXP_WAIT;
                    end
                end
                
                ST_EXP_WAIT: begin
                    if (exp_valid) begin
                        exp_val_reg <= exp_out;
                        mul_a <= sigma; mul_b <= sigma;
                        mul_start <= 1'b1;
                        state <= ST_MUL_SIGMA2_WAIT;
                    end
                end
                
                ST_MUL_SIGMA2_WAIT: begin
                    if (mul_valid) begin
                        sigma_sq_reg <= mul_result;
                        mul_a <= r + (mul_result >>> 1);
                        mul_b <= T;
                        mul_start <= 1'b1;
                        state <= ST_MUL_R_TERM_WAIT;
                    end
                end
                
                ST_MUL_R_TERM_WAIT: begin
                    if (mul_valid) begin
                        r_term_reg <= mul_result;
                        mul_a <= sigma; 
                        mul_b <= sqrt_T_reg;
                        mul_start <= 1'b1;
                        state <= ST_MUL_SIGMA_SQRT_WAIT;
                    end
                end
                
                ST_MUL_SIGMA_SQRT_WAIT: begin
                    if (mul_valid) begin
                        sigma_sqrt_T_reg <= mul_result;
                        div_a <= ln_val_reg + r_term_reg;
                        div_b <= (mul_result > denom_min) ? mul_result : denom_min;
                        div_start <= 1'b1;
                        state <= ST_DIV_D1_WAIT;
                    end
                end
                
                ST_DIV_D1_WAIT: begin
                    if (div_valid) begin
                        d1_reg <= div_result;
                        d2_reg <= div_result - sigma_sqrt_T_reg;
                        cdf_x <= div_result;
                        cdf_start <= 1'b1;
                        state <= ST_CDF1_WAIT;
                    end
                end
                
                ST_CDF1_WAIT: begin
                    if (cdf_valid) begin
                        cdf_d1_reg <= cdf_out;
                        cdf_x <= d2_reg;
                        cdf_start <= 1'b1;
                        state <= ST_CDF2_WAIT;
                    end
                end
                
                ST_CDF2_WAIT: begin
                    if (cdf_valid) begin
                        cdf_d2_reg <= cdf_out;
                        mul_a <= K; 
                        mul_b <= exp_val_reg;
                        mul_start <= 1'b1;
                        state <= ST_MUL_K_EXP_WAIT;
                    end
                end
                
                ST_MUL_K_EXP_WAIT: begin
                    if (mul_valid) begin
                        k_exp_reg <= mul_result;
                        mul_a <= S; 
                        mul_b <= cdf_d1_reg;
                        mul_start <= 1'b1;
                        state <= ST_MUL_S_CDF1_WAIT;
                    end
                end
                
                ST_MUL_S_CDF1_WAIT: begin
                    if (mul_valid) begin
                        call_reg <= mul_result;
                        mul_a <= k_exp_reg;
                        mul_b <= cdf_d2_reg;
                        mul_start <= 1'b1;
                        state <= ST_MUL_KEXP_CDF2_WAIT;
                    end
                end
                
                ST_MUL_KEXP_CDF2_WAIT: begin
                    if (mul_valid) begin
                        call_reg <= call_reg - mul_result;
                        mul_a <= 32'sh00010000 - cdf_d2_reg; 
                        mul_b <= k_exp_reg;
                        mul_start <= 1'b1;
                        state <= ST_MUL_INV_CDF2_WAIT;
                    end
                end
                
                ST_MUL_INV_CDF2_WAIT: begin
                    if (mul_valid) begin
                        put_reg <= mul_result;
                        mul_a <= S; 
                        mul_b <= 32'sh00010000 - cdf_d1_reg;
                        mul_start <= 1'b1;
                        state <= ST_MUL_INV_CDF1_WAIT;
                    end
                end
                
                ST_MUL_INV_CDF1_WAIT: begin
                    if (mul_valid) begin
                        put_reg <= put_reg - mul_result;
                        state <= ST_ABS;
                    end
                end
                ST_ABS: begin
                    if (put_reg < 0) begin
                        put_reg <= 0;
                    end
                    if (call_reg < 0) begin
                        call_reg <= 0;
                    end
                    state <= ST_DONE;
            
                ST_DONE: begin
                    price <= opt_type ? put_reg : call_reg;
                    done <= 1'b1;
                    busy <= 1'b0;
                    state <= IDLE;
                end
                
                default: state <= IDLE;
            endcase
        end
    end    
endmodule

// Колбасит на каких-то значениях, скорее всего чувствительные к сигма значения выпадают из диапазонов и нужно сделать нормально на всю ось...
module bisection (
    input  logic                 clk,
    input  logic                 rst,
    input  logic                 start,
    input  logic                 opt_type,
    input  logic signed [31:0]   S,
    input  logic signed [31:0]   K,
    input  logic signed [31:0]   T,
    input  logic signed [31:0]   market_price,
    output logic signed [31:0]   sigma_out,
    output logic                 done,
    output logic                 busy
);
    typedef enum logic [2:0] {
        IDLE, INIT, ITERATE, WAIT_PRICE, CHECK_CONVERGENCE, UPDATE_BOUNDS, DONE_ST
    } state_t;
    
    state_t state = IDLE;
    
    localparam signed [31:0] LOW_INIT   = 32'sh0000028F;
    localparam signed [31:0] HIGH_INIT  = 32'sh00050000;
    localparam signed [31:0] TOLERANCE  = 32'sh00000001;
    localparam logic [7:0]   MAX_ITER   = 100;
    
    logic signed [31:0] low, high;
    logic [5:0]         iter_count;
    logic signed [31:0] mid_reg;
    logic signed [31:0] price_reg;
    logic               price_valid;
    logic bs_price_start, bs_price_done, bs_price_busy;
    logic signed [31:0] bs_price;
    
    bs_price u_bs_price (
        .clk       (clk),
        .rst       (rst),
        .start     (bs_price_start),
        .opt_type  (opt_type),
        .S         (S),
        .K         (K),
        .T         (T),
        .sigma     (mid_reg),
        .price     (bs_price),
        .done      (bs_price_done),
        .busy      (bs_price_busy)
    );
    
    always_ff @(posedge clk or posedge rst) begin
        if (rst) begin
            state        <= IDLE;
            low          <= LOW_INIT;
            high         <= HIGH_INIT;
            iter_count   <= 0;
            mid_reg      <= 0;
            price_reg    <= 0;
            price_valid  <= 1'b0;
            done         <= 1'b0;
            busy         <= 1'b0;
            sigma_out    <= 0;
            bs_price_start <= 1'b0;
        end else begin
            done <= 1'b0;
            bs_price_start <= 1'b0;
            case (state)
                IDLE: begin
                    if (start) begin
                        state <= INIT;
                        busy  <= 1'b1;
                    end else begin
                        busy <= 1'b0;
                    end
                end
                
                INIT: begin
                    low        <= LOW_INIT;
                    high       <= HIGH_INIT;
                    iter_count <= 0;
                    mid_reg    <= (LOW_INIT + HIGH_INIT) >>> 1;
                    state      <= ITERATE;
                end
                
                ITERATE: begin
                    bs_price_start <= 1'b1;
                    price_valid    <= 1'b0;
                    state          <= WAIT_PRICE;
                end
                
                WAIT_PRICE: begin
                    if (bs_price_done) begin
                        price_reg   <= bs_price;
                        price_valid <= 1'b1;
                        state       <= CHECK_CONVERGENCE;
                    end
                end
                
                CHECK_CONVERGENCE: begin
                    if (price_valid) begin
                        logic signed [31:0] diff;
                        logic converged;
                        
                        diff = (price_reg > market_price) ? 
                               (price_reg - market_price) : 
                               (market_price - price_reg);
                        converged = (diff < TOLERANCE) || 
                                   ((high - low) <= 32'h00000001);
                        
                        if (converged || (iter_count >= MAX_ITER - 1)) begin
                            sigma_out <= mid_reg;
                            done      <= 1'b1;
                            busy      <= 1'b0;
                            state     <= DONE_ST;
                        end else begin
                            state <= UPDATE_BOUNDS;
                        end
                    end
                end
                
                UPDATE_BOUNDS: begin
                    if (price_reg > market_price)
                        high <= mid_reg;
                    else
                        low  <= mid_reg;
                    iter_count <= iter_count + 1;
                    mid_reg    <= (low + high) >>> 1;
                    state      <= ITERATE;
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
    input wire logic rst_n,
    input wire logic uart_rx,
    output wire logic uart_tx,
    output reg [2:0] led,
    output reg uart_led
);

    localparam CLK_FREQ   = 27_000_000;
    localparam BAUD_RATE  = 115200;
    localparam RX_BYTES    = 17;
    localparam TX_BYTES    = 4;

    logic rst;
    assign rst = ~rst_n;
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

    typedef enum logic [1:0] { ST_IDLE, ST_RECV, ST_WAIT_BISECTION, ST_SEND } state_t;
    state_t state = ST_IDLE;
    
    assign led = ~(state);
    assign uart_led = ~(uart_rx);

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
                    end else begin
                        state <= ST_RECV;
                    end
                end

                ST_WAIT_BISECTION: begin
                    if (!busy && !start && !done) begin
                        start <= 1;
                    end else if (busy) begin
                        start <= 0;
                    end else if (done) begin
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
                default: state <= ST_IDLE;
            endcase
        end
    end
endmodule