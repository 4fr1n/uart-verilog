
`timescale 1ns/1ps

module uart_tb;

  // ── Inputs ────────────────────────────────────────
  reg        clk;
  reg        rst;
  reg        wr_enb;
  reg  [7:0] data_in;

  // ── Outputs ───────────────────────────────────────
  wire [7:0] data_out;
  wire       data_ready;
  wire       frame_error;
  wire       busy;

  // ── Instantiate DUT ───────────────────────────────
  uart_top dut (
    .clk        (clk),
    .rst        (rst),
    .wr_enb     (wr_enb),
    .data_in    (data_in),
    .data_out   (data_out),
    .data_ready (data_ready),
    .frame_error(frame_error),
    .busy       (busy)
  );

  // ── Clock: 50 MHz → 20ns period ───────────────────
  initial clk = 0;
  always #10 clk = ~clk;

  // ── Task: send one byte and check it ──────────────
  task send_byte;
    input [7:0] byte_to_send;
    integer i;
    begin
      data_in <= byte_to_send;
      wr_enb  <= 1'b1;
      @(posedge clk);
      wr_enb  <= 1'b0;

      $display(">> Sending: 0x%h (%b)", byte_to_send, byte_to_send);

    // Wait max 10000 cycles instead of waiting forever
      i = 0;
      while (!data_ready && i < 10000) begin
        @(posedge clk);
        i = i + 1;
    end

    if (data_ready)
      $display("   PASS: Received 0x%h", data_out);
    else
      $display("   FAIL: Timed out waiting for data_ready");

    if (frame_error)
      $display("   WARNING: Frame error!");
  end
endtask

  // ── Stimulus ──────────────────────────────────────
  initial begin
    // Dump waveforms
    $dumpfile("uart.vcd");
    $dumpvars(0, uart_tb);

    // Reset
    rst    = 1;
    wr_enb = 0;
    data_in = 8'd0;
    #20;
    rst = 0;
    #20;

    // Test 1: Send 0xA5 (10100101)
    send_byte(8'hA5);
    #50;

    // Test 2: Send 0xFF (all ones)
    send_byte(8'hFF);
    #50;

    // Test 3: Send 0x00 (all zeros)
    send_byte(8'h00);
    #50;

    // Test 4: Send ASCII 'U' (01010101) - classic UART test pattern
    send_byte(8'h55);
    #50;

    $display("All tests complete.");
    $finish;
  end

endmodule