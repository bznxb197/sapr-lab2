# Запуск в ModelSim / QuestaSim (без покрытия): в консоли симулятора выполнить
#   do run_modelsim.do
vlib work
vlog -sv apb_master.sv apb_rect_perimeter.sv tb_top.sv
vsim -voptargs=+acc work.tb_top
add wave -radix hex /tb_top/pclk /tb_top/presetn /tb_top/psel /tb_top/penable /tb_top/pwrite \
                    /tb_top/pready /tb_top/pslverr /tb_top/paddr /tb_top/pwdata /tb_top/prdata
add wave -radix unsigned /tb_top/DUT/side_a /tb_top/DUT/side_b /tb_top/DUT/perimeter
add wave /tb_top/DUT/overflow /tb_top/DUT/degenerate /tb_top/DUT/apb_st
run -all
