#!/bin/sh
# Кодовое покрытие в Verilator (>= 5.0): покрытие строк/ветвей и переключений.
# Результат: coverage/summary.txt (сводка) и coverage/annotated/ (исходники
# с числом срабатываний каждой строки; непокрытые строки помечены %).
set -e
rm -rf obj_dir coverage
mkdir -p coverage
verilator --binary --timing -j 0 -Wno-fatal \
    --coverage-line --coverage-toggle \
    --top-module tb_top \
    apb_master.sv apb_rect_perimeter.sv tb_top.sv
./obj_dir/Vtb_top
verilator_coverage --annotate coverage/annotated --annotate-min 1 coverage.dat \
    | tee coverage/summary.txt
mv coverage.dat coverage/
