library IEEE;

use IEEE.std_logic_1164.all;
use WORK.tracker_constants.all;

entity fifo_tb is
	generic(
		constant DATA_WIDTH : integer := 8
	);
	port(
		signal tb : in std_logic
	);
end entity fifo_tb;

architecture behavioral of fifo_tb is
	
	component fifo is
  generic(
    constant BUFFER_SIZE : integer := 100;
    constant DATA_WIDTH : integer := 8
  );
  
  port(
    signal read_clk : in std_logic;
    signal write_clk : in std_logic;
    signal reset : in std_logic;
    signal read_en : in std_logic;
    signal write_en : in std_logic;
    signal data_in : in std_logic_vector((DATA_WIDTH-1) downto 0);
    signal data_out : out std_logic_vector((DATA_WIDTH-1) downto 0);
    signal full : out std_logic;
    signal empty : out std_logic
  );
end component fifo;


	signal read_clk : std_logic;
	signal write_clk : std_logic;
	signal reset : std_logic;
	signal read_en : std_logic;
	signal write_en : std_logic;
	signal data_in : std_logic_vector((DATA_WIDTH-1) downto 0);
	signal data_out : std_logic_vector((DATA_WIDTH-1) downto 0);
	signal full : std_logic;
	signal empty : std_logic;
	begin
	fum: fifo generic map(3,8)
	port map (read_clk, write_clk, reset, read_en, write_en, data_in, data_out, full, empty);

	test: process begin
	read_clk <= '0';
	write_clk <= '0';
	reset <= '1';
	read_en <= '0';
	write_en <= '1';
	data_in <= "00000001";
	wait for 5 ns;
	write_clk <= '1';
	wait for 5 ns;
	reset <= '0';
	write_clk <= '0';
	wait for 5 ns;
	write_clk <= '1';
	wait for 5 ns;
	write_clk <= '0';
	data_in <= "00000010";
	wait for 5 ns;
	write_clk <= '1';
	wait for 5 ns;
	write_clk <= '0';
	data_in <= "00000100";
	wait for 5 ns;
	write_clk <= '1';
	wait for 5 ns;
	write_clk <= '0';
	wait for 5 ns;
	write_clk <= '1';
	wait for 5 ns;
	write_clk <= '0';
	write_en <= '0';
	read_en <= '1';
	wait for 5 ns;
	read_clk <= '1';
	wait for 5 ns;
	read_clk <= '0';
	wait for 5 ns;
	read_clk <= '1';
	wait for 5 ns;
	read_clk <= '0';
	wait for 5 ns;
	read_clk <= '1';
	wait for 5 ns;
	read_clk <= '0';
	wait for 5 ns;
	read_clk <= '1';
	wait for 5 ns;
	read_clk <= '0';
	write_en <= '1';
	wait for 5 ns;
	data_in <= "00001000";
	wait for 5 ns;
	write_clk <= '1';
	wait for 5 ns;
	read_clk <= '1';
	wait for 5 ns;
	read_clk <= '0';
	wait for 5 ns;
	read_clk <= '1';
	wait for 5 ns;
	wait;
	end process;
end architecture;











