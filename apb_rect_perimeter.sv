`timescale 1ns/1ps

// APB slave: вычисление периметра прямоугольника по известным сторонам.
// Вариант 20.
//
// Карта регистров (смещение от базового адреса устройства):
//   0x0  SIDE_A     RW  длина стороны A (беззнаковое 32-битное)
//   0x4  SIDE_B     RW  длина стороны B (беззнаковое 32-битное)
//   0x8  PERIMETER  RO  периметр P = 2 * (A + B), младшие 32 бита
//   0xC  STATUS     RO  bit0 OVF  - периметр не помещается в 32 бита
//                       bit1 DEGEN - одна из сторон равна 0
//                       (вырожденный прямоугольник)
//                       остальные биты - 0
// Запись в регистры только для чтения и любое обращение по другому
// смещению завершаются с pslverr = 1, содержимое регистров не меняется.
module apb_rect_perimeter
(
    input  logic        pclk,     // синхросигнал
    input  logic        presetn,  // сигнал сброса (инверсный)
    input  logic [31:0] paddr,    // адрес обращения
    input  logic [31:0] pwdata,   // данные для записи
    input  logic        psel,     // признак выбора устройства
    input  logic        penable,  // признак активной транзакции
    input  logic        pwrite,   // признак операции записи
    output logic        pready,   // признак готовности от устройства
    output logic        pslverr,  // признак ошибки при обращении
    output logic [31:0] prdata    // прочитанные данные
);

    localparam logic [7:0] ADDR_SIDE_A    = 8'h0;
    localparam logic [7:0] ADDR_SIDE_B    = 8'h4;
    localparam logic [7:0] ADDR_PERIMETER = 8'h8;
    localparam logic [7:0] ADDR_STATUS    = 8'hC;

    logic [31:0] side_a;      // регистр стороны A
    logic [31:0] side_b;      // регистр стороны B

    // Вычислительная часть (комбинационная логика).
    // A + B занимает до 33 бит, умножение на 2 - сдвиг влево ещё на 1 бит,
    // поэтому полный результат 34-битный.
    logic [33:0] perimeter_full;
    logic [31:0] perimeter;
    logic        overflow;
    logic        degenerate;
    logic [31:0] status;

    assign perimeter_full = ({2'b00, side_a} + {2'b00, side_b}) << 1;
    assign perimeter      = perimeter_full[31:0];
    assign overflow       = |perimeter_full[33:32];
    assign degenerate     = (side_a == 32'd0) || (side_b == 32'd0);
    assign status         = {30'd0, degenerate, overflow};

    // Состояния автомата APB
    typedef enum logic [1:0] {
        APB_SETUP,
        APB_W_ENABLE,
        APB_R_ENABLE
    } apb_state_t;

    apb_state_t apb_st;

    always @(posedge pclk)
        if (!presetn)
        begin
            prdata  <= '0;
            pslverr <= 1'b0;
            pready  <= 1'b0;
            side_a  <= '0;
            side_b  <= '0;
            apb_st  <= APB_SETUP;
        end
        else
        begin
            case (apb_st)
                APB_SETUP:
                begin: apb_setup_st
                    // Очистка результатов предыдущей транзакции
                    prdata  <= '0;
                    pready  <= 1'b0;
                    pslverr <= 1'b0;

                    // Фаза SETUP: psel = 1, penable = 0
                    if (psel && !penable)
                    begin
                        if (pwrite)
                            apb_st <= APB_W_ENABLE;
                        else
                            apb_st <= APB_R_ENABLE;
                    end
                end: apb_setup_st

                APB_W_ENABLE:
                begin: apb_w_en_st
                    if (psel && penable && pwrite)
                    begin
                        pready <= 1'b1;
                        case (paddr[7:0])
                            ADDR_SIDE_A: begin
                                side_a <= pwdata;
                                $display("[%0t] RECT: WRITE side A = %0d (0x%h)", $time, pwdata, pwdata);
                            end
                            ADDR_SIDE_B: begin
                                side_b <= pwdata;
                                $display("[%0t] RECT: WRITE side B = %0d (0x%h)", $time, pwdata, pwdata);
                            end
                            ADDR_PERIMETER, ADDR_STATUS: begin
                                pslverr <= 1'b1;
                                $display("[%0t] RECT: WRITE 0x%h -> ERROR: register is read-only", $time, paddr);
                            end
                            default: begin
                                pslverr <= 1'b1;
                                $display("[%0t] RECT: WRITE 0x%h -> ERROR: no register at this offset", $time, paddr);
                            end
                        endcase
                        apb_st <= APB_SETUP;
                    end
                end: apb_w_en_st

                APB_R_ENABLE:
                begin: apb_r_en_st
                    if (psel && penable && !pwrite)
                    begin
                        pready <= 1'b1;
                        case (paddr[7:0])
                            ADDR_SIDE_A: begin
                                prdata <= side_a;
                                $display("[%0t] RECT: READ  side A = %0d", $time, side_a);
                            end
                            ADDR_SIDE_B: begin
                                prdata <= side_b;
                                $display("[%0t] RECT: READ  side B = %0d", $time, side_b);
                            end
                            ADDR_PERIMETER: begin
                                prdata <= perimeter;
                                $display("[%0t] RECT: READ  perimeter = %0d (0x%h), ovf = %b",
                                         $time, perimeter, perimeter, overflow);
                            end
                            ADDR_STATUS: begin
                                prdata <= status;
                                $display("[%0t] RECT: READ  status = 0x%h (ovf = %b, degenerate = %b)",
                                         $time, status, overflow, degenerate);
                            end
                            default: begin
                                pslverr <= 1'b1;
                                $display("[%0t] RECT: READ  0x%h -> ERROR: no register at this offset", $time, paddr);
                            end
                        endcase
                        apb_st <= APB_SETUP;
                    end
                end: apb_r_en_st

                default:
                begin
                    pslverr <= 1'b1;
                    apb_st  <= APB_SETUP;
                end
            endcase
        end

endmodule
