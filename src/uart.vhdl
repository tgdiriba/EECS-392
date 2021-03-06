library IEEE;

use IEEE.std_logic_1164.all;
use IEEE.numeric_std.all;
use WORK.tracker_constants.all;
--use WORK.fifo.all;

entity uart is
  port (
    -- internal clock and reset signals
    clock_50 : in std_logic;
    reset : in std_logic;
    
    -- uart communication dependent
    baud_rate : in natural := DEFAULT_BAUD_RATE;
    rx : in std_logic;
    tx : inout std_logic;
    
    -- tx fifo 
    read : in std_logic;
    empty : in std_logic;
    idata : in std_logic_vector(7 downto 0);
    -- rx fifo
    write : out std_logic;
    full : in std_logic;
    odata : out std_logic_vector(7 downto 0)
    
    
  );
end entity uart;

architecture uart of uart is
  -- clock control
  signal serial_clk : std_logic;
  signal counter_clk : integer;
  
  -- uart control
  signal uart_rx_state : uart_state;
  signal uart_rx_next : uart_state;
  --signal uart_rx_fifo : fifo;
  signal uart_tx_state : uart_state;
  signal uart_tx_next : uart_state;
  --signal uart_tx_fifo : fifo;
  
  -- fifos
  signal tx_read : std_logic;
  signal tx_empty : std_logic;
  signal tx_data : std_logic_vector(7 downto 0);
  signal rx_write : std_logic;
  signal rx_full : std_logic;
  signal rx_data : std_logic_vector(7 downto 0);
signal t_clock_count : natural;
begin
	tx_read <= read;
	tx_empty <= empty;
	tx_data <= idata;
	write <= rx_write;	
	rx_full <= full;
	odata <= rx_data;
  uart_rx_manager: process(clock_50, reset, baud_rate, rx, rx_write, rx_full, rx_data) is
    variable clock_count : natural := 0;
    variable uart_baud_count : natural := 0;
    variable uart_mid_baud_count : natural := 0;
    variable data_count : natural := 0;
    variable data_buffer : std_logic_vector(7 downto 0);
    variable counter : natural := 0;
  begin
	
    if(falling_edge(clock_50)) then
	uart_rx_state <= uart_rx_next;
	uart_tx_state <= uart_tx_next;
    elsif(rising_edge(clock_50)) then
      
      case(uart_rx_state) is
        -- check for a start bit
        when TRIGGER =>
          rx_write <= '0';
          clock_count := 0;
          if(rx = '0') then
            uart_rx_next <= INIT;
            
            -- TODO: Deal with clock drift due to small discrepancies?
            --       Ask the Professor about this.
            uart_baud_count := CLOCK_FREQUENCY / baud_rate;
            uart_mid_baud_count := CLOCK_FREQUENCY / (natural(2)*baud_rate);
          end if;
        when INIT =>
          -- wait until the midpoint of the pulse
          if(clock_count = uart_mid_baud_count-1) then
            -- reset the counter and proceed to the next state
            clock_count := 0;
            if(rx = '0') then
              uart_rx_next <= ACTIVE;
            else
              uart_rx_next <= TRIGGER;
            end if;
          else
            clock_count := clock_count + 1;
          end if;
        when ACTIVE =>
          -- load the next 8 bits into a temporary buffer
          if(clock_count = uart_baud_count -1) then
            data_buffer(data_count) := rx;
	    clock_count := 0;
            if(data_count = 7) then
              data_count := 0;
              clock_count := 0;
              uart_rx_next <= STOP;
            else
              data_count := data_count + 1;
            end if;
          else
            clock_count := clock_count + 1;
          end if;
        when STOP =>
          -- check if the next bit is low
          --  if it is then write the buffer to the fifo
          if(clock_count = uart_baud_count-1 and rx = '0') then            
            -- hold the signal for half the baud rate period
            uart_rx_next <= HOLD;
	  elsif(clock_count = uart_baud_count-1 and rx = '1') then 
	    uart_rx_next <= TRIGGER;
          else
            clock_count := clock_count + 1;
          end if;
        when HOLD =>
          -- wait half a clock cycle for the signal to remain high before retriggering
          if(clock_count = uart_mid_baud_count) then
	      if(rx = '0') then
              	if(rx_full = '0') then
                -- make sure that the fifo is not full and load data
                rx_write <= '1';
                rx_data <= data_buffer;
                end if;
              end if;
            uart_rx_next <= TRIGGER;
          else
            clock_count := clock_count + 1;
          end if;
	end case;
    end if;
  end process uart_rx_manager;
 
 
  uart_tx_manager: process(clock_50) is --, tx, tx_read, tx_empty, tx_data) is
    -- Data
    variable clock_count : natural := 0;
    variable data_count : natural := 0;
    variable data_buffer : std_logic_vector(7 downto 0);
    variable uart_baud_count : natural := 0;
    variable uart_mid_baud_count : natural := 0;
  begin
	t_clock_count <= clock_count;
    -- Write out the tx fifo until empty
    -- Check if data in fifo, read data into temporary storage, write each bit 
    if(rising_edge(clock_50)) then
      case(uart_tx_state) is
        when TRIGGER =>
          clock_count := 0;
          if(tx_read = '1' and tx_empty = '0') then
            -- enable start bit
            data_count := 0;
            data_buffer := tx_data;
            uart_tx_next <= INIT;
            tx <= '0';
            
            -- TODO: Deal with clock drift due to small discrepancies?
            --       Ask the Professor about this.
            uart_baud_count := CLOCK_FREQUENCY / baud_rate;
	    uart_mid_baud_count := CLOCK_FREQUENCY / (natural(2)*baud_rate);
	  else
	    tx <= '1';
          end if;
        when INIT =>
          if(clock_count = uart_baud_count-1) then
            clock_count := 0;
            tx <= data_buffer(data_count);
            --data_count := data_count + 1;
            uart_tx_next <= ACTIVE;
          else
            clock_count := clock_count + 1;
          end if;
        when ACTIVE =>
          if(clock_count = uart_baud_count-1) then
            if(data_count = 7) then
              data_count := 0;
              clock_count := 0;
              tx <= '0'; --stop bit
              uart_tx_next <= STOP;
            else
              data_count := data_count + 1;
	      tx <= data_buffer(data_count);
              clock_count := 0;
            end if;
          else
            clock_count := clock_count + 1;
          end if;
        when STOP =>
          if(clock_count = uart_baud_count-1) then
            clock_count := 0;
            uart_tx_next <= TRIGGER;
	    tx <= '1';
	  else
	    clock_count := clock_count +1;
          end if;
        when HOLD =>
	  if(clock_count = uart_mid_baud_count-1) then
            uart_tx_next <= TRIGGER;
	    
          else
            clock_count := clock_count + 1;
          end if;
	end case;
    end if;
  end process uart_tx_manager;



end architecture uart; 
