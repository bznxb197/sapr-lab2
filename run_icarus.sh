#!/bin/sh
# Запуск в Icarus Verilog (iverilog >= 11). Добавьте +monitor для вывода $monitor.
set -e
iverilog -g2012 -o sim.vvp apb_master.sv apb_rect_perimeter.sv tb_top.sv
vvp -n sim.vvp "$@"
