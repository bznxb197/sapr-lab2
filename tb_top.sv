`timescale 1ns/1ps

// Модуль верхнего уровня: тактовый генератор, сброс,
// APB master (из ЛР1) + устройство вычисления периметра и тест.
module tb_top;

    parameter logic [31:0] P_DEVICE_OFFSET = 32'h7000_0000;

    localparam logic [31:0] ADDR_SIDE_A    = P_DEVICE_OFFSET + 32'h0;
    localparam logic [31:0] ADDR_SIDE_B    = P_DEVICE_OFFSET + 32'h4;
    localparam logic [31:0] ADDR_PERIMETER = P_DEVICE_OFFSET + 32'h8;
    localparam logic [31:0] ADDR_STATUS    = P_DEVICE_OFFSET + 32'hC;

    logic        pclk;
    logic        presetn;
    logic        psel;
    logic        penable;
    logic        pwrite;
    logic [31:0] paddr;
    logic [31:0] pwdata;
    logic [31:0] prdata;
    logic        pready;
    logic        pslverr;

    logic [31:0] rdata;
    int          errors = 0;
    int          checks = 0;

    apb_master master
    (
        .pclk(pclk), .presetn(presetn),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    apb_rect_perimeter DUT
    (
        .pclk(pclk), .presetn(presetn),
        .psel(psel), .penable(penable), .pwrite(pwrite),
        .paddr(paddr), .pwdata(pwdata),
        .prdata(prdata), .pready(pready), .pslverr(pslverr)
    );

    // Тактовый сигнал: период 20 нс (50 МГц)
    initial pclk = 1'b0;
    always #10ns pclk = ~pclk;

    task automatic check(input string what, input logic [31:0] got, input logic [31:0] expected);
        checks++;
        if (got === expected)
            $display("    PASS  %s: 0x%h", what, got);
        else
        begin
            $display("    FAIL  %s: got 0x%h, expected 0x%h", what, got, expected);
            errors++;
        end
    endtask

    // Записать стороны, прочитать периметр и статус, сравнить с ожидаемыми
    task automatic test_rect(input logic [31:0] a, input logic [31:0] b,
                             input logic [31:0] exp_p, input logic [31:0] exp_status);
        $display("\n--- A = %0d, B = %0d ---", a, b);
        master.apb_write(ADDR_SIDE_A, a);
        master.apb_write(ADDR_SIDE_B, b);
        master.apb_read(ADDR_PERIMETER, rdata);
        check("perimeter", rdata, exp_p);
        master.apb_read(ADDR_STATUS, rdata);
        check("status", rdata, exp_status);
    endtask

    task automatic do_reset();
        presetn = 1'b0;
        repeat (5) @(posedge pclk);
        presetn = 1'b1;
        repeat (5) @(posedge pclk);
    endtask

    initial
    begin
        $timeformat(-9, 0, " ns", 8);
        if ($test$plusargs("monitor"))
            $monitor("APB IF: PSEL=%b PENABLE=%b PWRITE=%b PREADY=%b PSLVERR=%b PADDR=0x%h PWDATA=0x%h PRDATA=0x%h",
                     psel, penable, pwrite, pready, pslverr, paddr, pwdata, prdata);

        presetn = 1'b1;
        repeat (5) @(posedge pclk);
        do_reset();

        $display("\n=== Basic tests ===");
        test_rect(32'd3,  32'd5,  32'd16, 32'h0);
        test_rect(32'd10, 32'd20, 32'd60, 32'h0);

        $display("\n=== Result: %0d checks, %0d errors ===\n", checks, errors);
        repeat (10) @(posedge pclk);
`ifdef VERILATOR
        $finish;
`else
        $stop();
`endif
    end

endmodule
