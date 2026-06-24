`timescale 1ns/1ps


module baud_rate_generator(
  input clk, 
  output tx_en, 
  output rx_en
);
  // Using 4-bit counters
  reg [3:0] rx_counter = 0;
  reg [3:0] tx_counter = 0;

  // rx_en ticks every 16 clk cycles (Oversampling clock)
  always @ (posedge clk) begin
    rx_counter <= rx_counter + 1'b1;
  end
  assign rx_en = (rx_counter == 4'd15);

  // tx_en ticks once every 16 rx_en ticks (Actual Baud Rate)
  always @ (posedge clk) begin
    if (rx_en) begin
      tx_counter <= tx_counter + 1'b1;
    end
  end
  assign tx_en = (rx_en && (tx_counter == 4'd15));
endmodule




module transmitter(
  input        clk,
  input        rst,
  input        wr_enb,
  input        tx_en,
  input  [7:0] data_in,
  output reg   tx,
  output       busy
);

  parameter idle_state  = 2'b00;
  parameter start_state = 2'b01;
  parameter data_state  = 2'b10;
  parameter stop_state  = 2'b11;

  reg [7:0] data;
  reg [2:0] index;
  reg [1:0] state = idle_state;

  // The transmitter is busy if it is not in the idle state
  assign busy = (state != idle_state);

  always @ (posedge clk or posedge rst) begin
    if (rst) begin
      state <= idle_state;
      tx    <= 1'b1;      // UART idle line state is HIGH
      index <= 3'd0;
      data  <= 8'd0;
    end
    else begin
      case (state)
        
        // 1. IDLE STATE: Checked every clock cycle so it never misses 'wr_enb'
        idle_state: begin
          tx    <= 1'b1;
          index <= 3'd0;
          if (wr_enb) begin
            data  <= data_in;    // Capture input data immediately
            state <= start_state;
          end
        end

        // All active transmission states are synchronized to the baud rate clock enable (tx_en)
        default: begin
          if (tx_en) begin
            case (state)

              // 2. START BIT: Pull the line LOW for 1 baud cycle
              start_state: begin
                tx    <= 1'b0;
                state <= data_state;
              end

              // 3. DATA BITS: Transmit 8 bits, LSB first
              data_state: begin
                tx <= data[index];
                if (index == 3'd7) begin
                  index <= 3'd0;
                  state <= stop_state;
                end
                else
                  index <= index + 1'b1;
              end

              // 4. STOP BIT: Pull the line HIGH for 1 baud cycle
              stop_state: begin
                tx    <= 1'b1;
                state <= idle_state;
              end

              // Fallback safety
              default: state <= idle_state;
              
            endcase
          end
        end
        
      endcase
    end
  end
endmodule


module receiver(
  input        clk,
  input        rst,
  input        rx_en,
  input        rx,
  output reg [7:0] data_out,
  output reg   data_ready,
  output reg   frame_error
);

  parameter idle_state  = 2'b00;
  parameter start_state = 2'b01;
  parameter data_state  = 2'b10;
  parameter stop_state  = 2'b11;

  reg [1:0] state = idle_state;
  reg [2:0] index;
  reg [3:0] tick_counter; // Tracks the 16x oversampling ticks

  always @ (posedge clk or posedge rst) begin
    if (rst) begin
      state       <= idle_state;
      data_out    <= 8'd0;
      data_ready  <= 1'b0;
      frame_error <= 1'b0;
      index       <= 3'd0;
      tick_counter<= 4'd0;
    end
    else begin
      // Pulse high for 1 clock cycle only when valid data arrives
      if (data_ready) data_ready <= 1'b0; 

      if (rx_en) begin
        case (state)

          // 1. IDLE: Look for falling edge (start bit)
          idle_state: begin
            index        <= 3'd0;
            tick_counter <= 4'd0;
            frame_error  <= 1'b0;
            if (rx == 1'b0)
              state <= start_state;
          end

          // 2. START: Wait 7 ticks to sample at the middle of the start bit
          start_state: begin
            if (tick_counter == 4'd7) begin
              if (rx == 1'b0) begin
                tick_counter <= 4'd0;
                state        <= data_state; // Valid start bit confirmed
              end
              else begin
                state <= idle_state; // False start glitch
              end
            end
            else begin
              tick_counter <= tick_counter + 1'b1;
            end
          end

          // 3. DATA: Wait 15 ticks between samples to stay in the middle of each bit
          data_state: begin
            if (tick_counter == 4'd15) begin
              tick_counter <= 4'd0;
              data_out[index] <= rx;
              
              if (index == 3'd7) begin
                index <= 3'd0;
                state <= stop_state;
              end
              else begin
                index <= index + 1'b1;
              end
            end
            else begin
              tick_counter <= tick_counter + 1'b1;
            end
          end

          // 4. STOP: Wait 15 ticks and verify the stop bit is HIGH
          stop_state: begin
            if (tick_counter == 4'd15) begin
              tick_counter <= 4'd0;
              state        <= idle_state;
              if (rx == 1'b1) begin
                data_ready  <= 1'b1;  // Success!
                frame_error <= 1'b0;
              end
              else begin
                frame_error <= 1'b1;  // Framing Error!
              end
            end
            else begin
              tick_counter <= tick_counter + 1'b1;
            end
          end

          default: state <= idle_state;
        endcase
      end
    end
  end
endmodule


module uart_top(
  input        clk,
  input        rst,
  input        wr_enb,
  input  [7:0] data_in,
  output [7:0] data_out,
  output       data_ready,
  output       frame_error,
  output       busy
);

  wire tx_en, rx_en;
  wire tx_line;   // Wire connecting TX output to RX input

  // Instantiate baud rate generator
  baud_rate_generator brg (
    .clk   (clk),
    .tx_en (tx_en),
    .rx_en (rx_en)
  );

  // Instantiate transmitter
  transmitter utx (
    .clk     (clk),
    .rst     (rst),
    .wr_enb  (wr_enb),
    .tx_en   (tx_en),
    .data_in (data_in),
    .tx      (tx_line),
    .busy    (busy)
  );

  // Instantiate receiver — rx fed from tx_line
  receiver urx (
    .clk        (clk),
    .rst        (rst),
    .rx_en      (rx_en),
    .rx         (tx_line),
    .data_out   (data_out),
    .data_ready (data_ready),
    .frame_error(frame_error)
  );

endmodule