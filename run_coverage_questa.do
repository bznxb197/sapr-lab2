# Кодовое покрытие в QuestaSim / Questa - Intel FPGA Edition.
# (В ModelSim-Altera Starter Edition покрытие недоступно.)
#   do run_coverage_questa.do
# Покрытие собирается только для устройства (apb_rect_perimeter):
#   s - операторы, b - ветви, c - условия, e - выражения, f - конечный автомат, t - переключения
vlib work
vlog -sv apb_master.sv tb_top.sv
vlog -sv +cover=sbcneft apb_rect_perimeter.sv
vsim -coverage -voptargs=+acc work.tb_top
run -all
coverage save coverage.ucdb
coverage report -file coverage_summary.txt -byinstance
coverage report -file coverage_details.txt -details -assert -directive -cvg -codeAll
