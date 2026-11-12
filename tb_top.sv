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

    localparam logic [31:0] ST_OK    = 32'h0;
    localparam logic [31:0] ST_OVF   = 32'h1;   // bit0: переполнение
    localparam logic [31:0] ST_DEGEN = 32'h2;   // bit1: сторона равна 0

    localparam int N_RANDOM = 40;
    localparam int SEED     = 2026;

    logic [31:0] rdata;
    int          seed;
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

    // Запись, которая должна завершиться ошибкой
    task automatic write_expect_error(input string what, input logic [31:0] addr, input logic [31:0] data);
        master.apb_write(addr, data);
        check({what, ": pslverr"}, {31'd0, master.last_slverr}, 32'd1);
    endtask

    // Чтение, которое должно завершиться ошибкой (prdata = 0)
    task automatic read_expect_error(input string what, input logic [31:0] addr);
        master.apb_read(addr, rdata);
        check({what, ": pslverr"}, {31'd0, master.last_slverr}, 32'd1);
        check({what, ": prdata"}, rdata, 32'd0);
    endtask

    // Эталонная модель: что должно получиться для сторон a и b
    function automatic logic [31:0] ref_perimeter(input logic [31:0] a, input logic [31:0] b);
        logic [33:0] full;
        full = ({2'b00, a} + {2'b00, b}) << 1;
        return full[31:0];
    endfunction

    function automatic logic [31:0] ref_status(input logic [31:0] a, input logic [31:0] b);
        logic [33:0] full;
        full = ({2'b00, a} + {2'b00, b}) << 1;
        return {30'd0, (a == 32'd0) || (b == 32'd0), |full[33:32]};
    endfunction

    // Случайные стороны: половина тестов в малом диапазоне (без переполнения),
    // половина - во всём 32-битном диапазоне
    task automatic test_random(input int i);
        logic [31:0] a, b;
        a = $urandom();
        b = $urandom();
        if (i % 2 == 0)
        begin
            a = a & 32'h00FF_FFFF;
            b = b & 32'h00FF_FFFF;
        end
        test_rect(a, b, ref_perimeter(a, b), ref_status(a, b));
    endtask

    task automatic check_reset_values();
        master.apb_read(ADDR_SIDE_A, rdata);
        check("reset: side A", rdata, 32'd0);
        master.apb_read(ADDR_SIDE_B, rdata);
        check("reset: side B", rdata, 32'd0);
        master.apb_read(ADDR_PERIMETER, rdata);
        check("reset: perimeter", rdata, 32'd0);
        master.apb_read(ADDR_STATUS, rdata);
        check("reset: status", rdata, ST_DEGEN);
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

        seed = SEED;
        void'($urandom(seed));  // фиксированное зерно - тест воспроизводим

        presetn = 1'b1;
        repeat (5) @(posedge pclk);
        do_reset();

        $display("\n=== 1. Reset values ===");
        check_reset_values();

        $display("\n=== 2. Basic tests ===");
        test_rect(32'd3,  32'd5,  32'd16, ST_OK);
        test_rect(32'd10, 32'd20, 32'd60, ST_OK);
        test_rect(32'd1,  32'd1,  32'd4,  ST_OK);

        $display("\n=== 3. Side registers read back ===");
        master.apb_write(ADDR_SIDE_A, 32'hDEAD_BEEF);
        master.apb_write(ADDR_SIDE_B, 32'h0BAD_F00D);
        master.apb_read(ADDR_SIDE_A, rdata);
        check("side A", rdata, 32'hDEAD_BEEF);
        master.apb_read(ADDR_SIDE_B, rdata);
        check("side B", rdata, 32'h0BAD_F00D);

        $display("\n=== 4. Degenerate rectangle (side = 0) ===");
        test_rect(32'd0, 32'd7, 32'd14, ST_DEGEN);
        test_rect(32'd9, 32'd0, 32'd18, ST_DEGEN);
        test_rect(32'd0, 32'd0, 32'd0,  ST_DEGEN);

        $display("\n=== 5. Boundary values and overflow ===");
        // максимальный периметр без переполнения: 2 * 0x7FFF_FFFF = 0xFFFF_FFFE
        test_rect(32'h7FFF_FFFF, 32'd0,         32'hFFFF_FFFE, ST_DEGEN);
        test_rect(32'h7FFF_FFFE, 32'd1,         32'hFFFF_FFFE, ST_OK);
        // на единицу больше: 2 * 0x8000_0000 = 0x1_0000_0000 -> переполнение
        test_rect(32'h7FFF_FFFF, 32'd1,         32'h0000_0000, ST_OVF);
        // максимальные стороны: 2 * 0x1_FFFF_FFFE = 0x3_FFFF_FFFC
        test_rect(32'hFFFF_FFFF, 32'hFFFF_FFFF, 32'hFFFF_FFFC, ST_OVF);
        // переполнение и вырожденность одновременно
        test_rect(32'hFFFF_FFFF, 32'd0,         32'hFFFF_FFFE, ST_OVF | ST_DEGEN);

        $display("\n=== 6. Write to read-only registers ===");
        test_rect(32'd100, 32'd200, 32'd600, ST_OK);
        write_expect_error("write PERIMETER", ADDR_PERIMETER, 32'h1234_5678);
        write_expect_error("write STATUS",    ADDR_STATUS,    32'hFFFF_FFFF);
        master.apb_read(ADDR_PERIMETER, rdata);
        check("perimeter unchanged", rdata, 32'd600);
        master.apb_read(ADDR_STATUS, rdata);
        check("status unchanged", rdata, ST_OK);

        $display("\n=== 7. Invalid offsets ===");
        write_expect_error("write 0x10", P_DEVICE_OFFSET + 32'h10, 32'h1);
        write_expect_error("write 0x02", P_DEVICE_OFFSET + 32'h02, 32'h1);
        read_expect_error ("read  0x10", P_DEVICE_OFFSET + 32'h10);
        read_expect_error ("read  0xFC", P_DEVICE_OFFSET + 32'hFC);
        master.apb_read(ADDR_SIDE_A, rdata);
        check("side A unchanged", rdata, 32'd100);
        master.apb_read(ADDR_SIDE_B, rdata);
        check("side B unchanged", rdata, 32'd200);
        // после ошибки следующая корректная транзакция проходит без pslverr
        master.apb_read(ADDR_PERIMETER, rdata);
        check("pslverr cleared", {31'd0, master.last_slverr}, 32'd0);

        $display("\n=== 8. Random tests (%0d) ===", N_RANDOM);
        for (int i = 0; i < N_RANDOM; i++)
            test_random(i);

        $display("\n=== 9. Address decoding: only paddr[7:0] is used ===");
        // Устройство декодирует только смещение paddr[7:0]; выбор устройства
        // по старшим битам делает интерконнект через psel. Проверяем, что
        // старшие биты адреса не влияют на работу, а нечётное смещение - ошибка.
        master.apb_write(32'h8FFF_FF00, 32'd11);                 // = смещение 0x0
        master.apb_write(32'h0000_0004, 32'd22);                 // = смещение 0x4
        master.apb_read (ADDR_PERIMETER, rdata);
        check("perimeter via aliased addresses", rdata, 32'd66);
        read_expect_error("read  0x01", P_DEVICE_OFFSET + 32'h01);
        read_expect_error("read  0x0B", P_DEVICE_OFFSET + 32'h0B);

        $display("\n=== 10. Reset during operation ===");
        master.apb_write(ADDR_SIDE_A, 32'd123);
        master.apb_write(ADDR_SIDE_B, 32'd456);
        do_reset();
        check_reset_values();
        $display("\n=== Result: %0d checks, %0d errors ===\n", checks, errors);
        repeat (10) @(posedge pclk);
`ifdef VERILATOR
        $finish;
`else
        $stop();
`endif
    end

endmodule
