# UART Core in Verilog

A robust, hardware-synthesizable Universal Asynchronous Receiver-Transmitter (UART) core implemented in Verilog. This repository features a fully modular layout including a Transmitter, a Receiver with 16x oversampling validation, and a configurable Baud Rate Generator.

---

## Technical Overview: How UART Works

**Universal Asynchronous Receiver-Transmitter (UART)** is a serial communication protocol that transmits data sequentially (bit-by-bit) over a single physical line without requiring a shared clock signal. 

Because it is **asynchronous**, the transmitter and receiver must agree on a timing configuration (the **Baud Rate**) beforehand. 

### Data Frame Structure
When the line is idle, it rests at a continuous **HIGH (1)** state. A standard data frame consists of:
1. **Start Bit (1 bit):** The transmitter pulls the line **LOW (0)** to signal the start of a transmission.
2. **Data Bits (8 bits):** The core character/payload data, transmitted Least Significant Bit (LSB) first.
3. **Stop Bit (1 bit):** The transmitter pulls the line **HIGH (1)** to signal the end of the frame and return the bus to idle.

---

## Block Interface & Pin Descriptions

### 1. Top-Level Module (`uart_top`)
Maps out the collective interface managing internal serial routing.

| Pin Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `clk` | Input | 1 | Global System Clock (e.g., 50 MHz) |
| `rst` | Input | 1 | Active-High Synchronous Reset |
| `wr_enb` | Input | 1 | Write Enable pulse to latch data and initiate transmission |
| `data_in` | Input | 8 | 8-bit parallel byte data to be transmitted |
| `data_out` | Output | 8 | 8-bit parallel byte data successfully received |
| `data_ready`| Output | 1 | Asserted for 1 clock cycle when a valid byte is completely received |
| `frame_error`| Output | 1 | High if the received stop bit is missing/invalid |
| `busy` | Output | 1 | High while the transmitter is actively shifting out a frame |

### 2. Transmitter Sub-module (`transmitter`)
| Pin Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `tx_en` | Input | 1 | Baud rate strobe indicating when to shift out the next data bit |
| `tx` | Output | 1 | Serial data output line |

### 3. Receiver Sub-module (`receiver`)
| Pin Name | Direction | Width | Description |
| :--- | :---: | :---: | :--- |
| `rx_en` | Input | 1 | 16x oversampling clock strobe |
| `rx` | Input | 1 | Serial data input line |

---

## Baud Rate & Oversampling Mechanics

The `baud_rate_generator` block splits the system clock into two crucial processing enables:
* **`rx_en` (16x Oversampling Enable):** Fires 16 times faster than the actual baud rate. This allows the receiver to sense the incoming serial wire at a high resolution.
* **`tx_en` (Baud Rate Enable):** Fires exactly once every 16 `rx_en` pulses, specifying the actual transmission step speed.

### Mid-Bit Sampling Verification
To protect against signal noise and line glitches, the receiver tracks individual oversampling counts via `tick_counter`:
* Upon detecting a falling edge (`rx == 0`), the module waits **7 oversampling ticks** to find the absolute center of the start bit.
* For all subsequent data and stop bits, the module counts out exactly **15 ticks** to sample perfectly in the middle of each bit width window.

---

## Finite State Machine (FSM) State Tables

### Transmitter FSM

| Current State | Condition | Next State | Outputs / Actions |
| :--- | :--- | :--- | :--- |
| **`idle_state (00)`** | `wr_enb == 1` <br> `wr_enb == 0` | `start_state` <br> `idle_state` | `tx = 1`, `busy = 0`, Latch `data_in` <br> `tx = 1`, `busy = 0` |
| **`start_state (01)`**| `tx_en == 1` <br> `tx_en == 0` | `data_state` <br> `start_state` | `tx = 0`, `busy = 1` |
| **`data_state (10)`** | `tx_en == 1` && `index == 7` <br> `tx_en == 1` && `index < 7` <br> `tx_en == 0` | `stop_state` <br> `data_state` <br> `data_state` | `tx = data[index]`, Increment `index` |
| **`stop_state (11)`** | `tx_en == 1` <br> `tx_en == 0` | `idle_state` <br> `stop_state` | `tx = 1`, `busy = 1` |

### Receiver FSM

| Current State | Condition | Next State | Outputs / Actions |
| :--- | :--- | :--- | :--- |
| **`idle_state (00)`** | `rx_en == 1` && `rx == 0` <br> Otherwise | `start_state` <br> `idle_state` | Clear index and tick counters |
| **`start_state (01)`**| `rx_en == 1` && `tick_counter == 7` && `rx == 0`<br> `rx_en == 1` && `tick_counter == 7` && `rx == 1`<br> Otherwise | `data_state` <br> `idle_state` <br> `start_state` | Confirmed valid start bit <br> False start glitch <br> Increment `tick_counter` |
| **`data_state (10)`** | `rx_en == 1` && `tick_counter == 15` && `index == 7`<br> `rx_en == 1` && `tick_counter == 15` && `index < 7`<br> Otherwise | `stop_state` <br> `data_state` <br> `data_state` | Sample `data_out[index]`, reset tick counter <br> Sample bit, increment `index` <br> Increment `tick_counter` |
| **`stop_state (11)`** | `rx_en == 1` && `tick_counter == 15` && `rx == 1`<br> `rx_en == 1` && `tick_counter == 15` && `rx == 0`<br> Otherwise | `idle_state` <br> `idle_state` <br> `stop_state` | Assert `data_ready = 1` (Success) <br> Assert `frame_error = 1` (Failure) <br> Increment `tick_counter` |

---

## Simulation & Testbench Results

### Compilation Command
This project is compiled and simulated using **Iverilog** and executed via **vvp**:
```bash
iverilog -Wall -g2012 -o uart_sim design.v testbench.v
vvp uart_sim
