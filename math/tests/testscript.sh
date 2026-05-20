#!/bin/bash

iverilog -g2012 -o sqrt_test /home/kniv/BS-model/src/main.sv /home/kniv/BS-model/src/sqrt_tb.sv 

iverilog -g2012 -o ln_test /home/kniv/BS-model/src/main.sv /home/kniv/BS-model/src/log_tb.sv

iverilog -g2012 -o exp_test /home/kniv/BS-model/src/main.sv /home/kniv/BS-model/src/exp_tb.sv 

iverilog -g2012 -o CDF_test /home/kniv/BS-model/src/main.sv /home/kniv/BS-model/src/normalCDF_tb.sv 

iverilog -g2012 -o bs_test /home/kniv/BS-model/src/main.sv /home/kniv/BS-model/src/bs_tb.sv 

iverilog -g2012 -o bisec_test /home/kniv/BS-model/src/main.sv /home/kniv/BS-model/src/bisec_tb.sv
