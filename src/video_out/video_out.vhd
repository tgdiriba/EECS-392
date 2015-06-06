library IEEE;
use IEEE.std_logic_1164.all;
use ieee.numeric_std.all;
use work.video_out_constants.all;

entity video_out is
	port(
			clk : in std_logic;
			clk_27 : in std_logic;
			reset : in std_logic;
			
			--VGA 
			red, green, blue : out std_logic_vector(7 downto 0); 
			h_sync, v_sync, blank, vga_clk : out std_logic
			
		);
end entity video_out;

architecture structural of video_out is

signal pixel_clk : std_logic;
signal pixel_row : std_logic_vector(9 downto 0);
signal pixel_col : std_logic_vector(9 downto 0);
signal pixel_row_int, pixel_col_int : natural;

signal ycc_store, ycc_load : std_logic_vector(YCC_WIDTH-1 downto 0);
signal y, y1, y2, cb, cr : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
signal y1_filter, y2_filter, cb_filter, cr_filter : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
signal y_int, cb_int, cr_int : natural;
signal y1_filter_int, y2_filter_int, cb_filter_int, cr_filter_int : natural;
signal filter_result : std_logic;
signal filter_result_first, filter_result_last : std_logic;

signal row, col : natural;
signal read_addr_full : signed(31 downto 0);
signal ycc_write_addr, ycc_read_addr : natural;
signal img_sel : std_logic_vector(1 downto 0);

signal pixel : std_logic_vector(PIXEL_WIDTH-1 downto 0);
signal ycc_pixel : std_logic_vector(PIXEL_WIDTH-1 downto 0);
signal ycc_pixel_sel : std_logic;
signal bw_pixel_full : std_logic_vector(PIXEL_WIDTH-1 downto 0);
signal bw_pixel : std_logic;
signal bw_pixel_sel : natural;

signal bw_store, bw_load : std_logic_vector(BW_BUFFER_WIDTH-1 downto 0);
signal bw_write_addr, bw_read_addr : natural;
signal bw_wr_en : std_logic;

signal camera_load : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
signal camera_store : std_logic_vector(SAMPLE_WIDTH-1 downto 0) := x"00";
signal camera_load_latched : std_logic_vector(SAMPLE_WIDTH-1 downto 0);
signal full, empty : std_logic;
signal fifo_read_en, fifo_write_en : std_logic := '0';

signal center_row, center_col : natural;

signal counter_read_fifo_temp : natural;
signal color_temp : std_logic_vector(31 downto 0);
signal addr_temp : natural;
signal init_temp : natural;

begin

  input_stream : fifo
  generic map(
    BUFFER_SIZE => 8,
    DATA_WIDTH => SAMPLE_WIDTH 
  )
  port map(
    read_clk => clk,
    write_clk => clk_27,
    reset => reset,
    read_en => fifo_read_en,
    write_en => '1',
    data_in => camera_store,
    data_out => camera_load,
    full => full,
    empty => empty
  );

  video : vga 
  port map(
    clk => clk, 
    reset => reset, 
    pixel => pixel, 
    pixel_clock_out => pixel_clk, 
    pixel_row => pixel_row, 
    pixel_col => pixel_col, 
    horiz_sync_out => h_sync, 
    vert_sync_out => v_sync, 
    vga_blank => blank, 
    red => red, 
    green => green, 
    blue => blue 
  );
  
  vga_clk <= pixel_clk;
  
  ycc_mem : sram
  generic map(
    RAM_SIZE => YCC_RAM_SIZE,
    DATA_WIDTH => YCC_WIDTH
  )
  port map(
    clk => clk,
    we => '1',
    write_addr => ycc_write_addr,
    data_in => ycc_store,
    read_addr => ycc_read_addr,
    data_out => ycc_load
  );

  get_addr : pixel_address
  port map(
    pixel_row => pixel_row_int,
    pixel_col => pixel_col_int,
    ycc_read_addr => ycc_read_addr,
    ycc_pixel_sel => ycc_pixel_sel,
    bw_read_addr => bw_read_addr,
    bw_pixel_sel => bw_pixel_sel
  );
	
  pixel_row_int <= to_integer(unsigned(pixel_row));
  pixel_col_int <= to_integer(unsigned(pixel_col));
	
  -- map loaded word to ycc data
  y1 <= ycc_load(YCC_WIDTH-1 downto YCC_WIDTH-SAMPLE_WIDTH);
  cb <= ycc_load(YCC_WIDTH-SAMPLE_WIDTH-1 downto YCC_WIDTH-SAMPLE_WIDTH*2);
  y2 <= ycc_load(YCC_WIDTH-SAMPLE_WIDTH*2-1 downto YCC_WIDTH-SAMPLE_WIDTH*3);
  cr <= ycc_load(YCC_WIDTH-SAMPLE_WIDTH*3-1 downto 0);
  
  y1_filter <= ycc_store(YCC_WIDTH-1 downto YCC_WIDTH-SAMPLE_WIDTH);
  cb_filter <= ycc_store(YCC_WIDTH-SAMPLE_WIDTH-1 downto YCC_WIDTH-SAMPLE_WIDTH*2);
  y2_filter <= ycc_store(YCC_WIDTH-SAMPLE_WIDTH*2-1 downto YCC_WIDTH-SAMPLE_WIDTH*3);
  cr_filter <= ycc_store(YCC_WIDTH-SAMPLE_WIDTH*3-1 downto 0);
   
  -- select which y component to convert
  with ycc_pixel_sel select y <=
    y1 when '0',
    y2 when '1',
    (others => '0') when others;
    
  y_int <= to_integer(unsigned(y));
  cb_int <= to_integer(unsigned(cb));
  cr_int <= to_integer(unsigned(cr));
  
  -- convert current ycc to rgb for vga output
  get_colors : ycc2rgb
  port map(
    clk => clk, 
    y => y, 
    cb => cb, 
    cr => cr, 
    r => ycc_pixel(PIXEL_WIDTH-1 downto PIXEL_WIDTH-SAMPLE_WIDTH), 
    g => ycc_pixel(PIXEL_WIDTH-SAMPLE_WIDTH-1 downto PIXEL_WIDTH-SAMPLE_WIDTH*2), 
    b => ycc_pixel(PIXEL_WIDTH-SAMPLE_WIDTH*2-1 downto 0)
  );
  
  -- output depends on current quadrant of screen
  select_img : process(pixel_col_int, pixel_row_int)
  begin
    if (pixel_col_int < 320) then
      img_sel(0) <= '0';
    else
      img_sel(0) <= '1';
    end if;
    
    if (pixel_row_int < 240) then
      img_sel(1) <= '0';
    else
      img_sel(1) <= '1';
    end if;
  end process;
  
  with img_sel select pixel <=
    ycc_pixel when "00",
    bw_pixel_full when "01",
    x"AAAAAA" when others;
  
  get_center : centroid
  port map(
    clk => clk, 
    reset => reset, 
    pixel_buffer => bw_store, 
    center_row => center_row,
    center_col => center_col
  );
  
  get_bw_pixel : process(row, col)
  begin
    if (row >= center_row-1 and row <= center_row+1 and col >= center_col-1 and col <= center_col+1) then
      bw_pixel_full <= x"00FF00";
    else
      bw_pixel_full <= (others => bw_pixel);
    end if;
  end process;  
    
  -- fill ycc RAM with test data
  fill_ram : process(clk, reset)
    constant RED_PIXEL : std_logic_vector(YCC_WIDTH-1 downto 0) := x"515A51F0"; -- 81 90 240
    constant GREEN_PIXEL : std_logic_vector(YCC_WIDTH-1 downto 0) := x"91369122"; -- 145 54 34
    constant BLUE_PIXEL : std_logic_vector(YCC_WIDTH-1 downto 0) := x"29F0296E"; -- 41 240 110
	  variable addr : natural := 0;
    variable color : std_logic_vector(YCC_WIDTH-1 downto 0) := RED_PIXEL;
  begin
    if rising_edge(clk) then
      addr := addr + 1;
		  if (addr >= YCC_RAM_SIZE) then
		  	addr := 0;
		  end if; 
      if (addr < YCC_RAM_SIZE / 3) then
        color := RED_PIXEL;
      elsif (addr < YCC_RAM_SIZE * 2/3) then
        color := GREEN_PIXEL;
      elsif (addr < YCC_RAM_SIZE) then
        color := BLUE_PIXEL;
      end if;
      
      if (reset = '0') then
        addr := 0;
        color := RED_PIXEL;
      end if;
      
      ycc_write_addr <= addr;
      ycc_store <= color;
    end if;
  end process;
  
    -- fill fifo with ycc test data
  write_fifo : process(clk_27, reset)
    constant RED_PIXEL : std_logic_vector(YCC_WIDTH-1 downto 0) := x"515A51F0"; -- 81 90 240
    constant GREEN_PIXEL : std_logic_vector(YCC_WIDTH-1 downto 0) := x"91369122"; -- 145 54 34
    constant BLUE_PIXEL : std_logic_vector(YCC_WIDTH-1 downto 0) := x"29F0296E"; -- 41 240 110
	  variable addr : natural := 0;
    variable color : std_logic_vector(YCC_WIDTH-1 downto 0) := RED_PIXEL;
    variable byte : natural := 3;
  begin		
    if rising_edge(clk_27) then
      
      fifo_write_en <= '1';
      camera_store <= color((byte+1)*8-1 downto byte*8);
      if (byte = 0) then
        byte := 3;
      else
        byte := byte - 1;
      end if;
      
      addr := addr + 1;
		  if (addr >= YCC_RAM_SIZE) then
		  	addr := 0;
		  end if;
        
      if (addr < YCC_RAM_SIZE / 3) then
        color := RED_PIXEL;
      elsif (addr < YCC_RAM_SIZE * 2/3) then
        color := GREEN_PIXEL;
      elsif (addr < YCC_RAM_SIZE) then
        color := BLUE_PIXEL;
      end if;
      
      if (reset = '0') then
        byte := 3;
        addr := 0;
       	color := RED_PIXEL;
      end if;
		
      --ycc_write_addr <= addr;
      color_temp <= color;
      addr_temp <= addr;
		
    end if;
  end process;
  
  read_fifo : process(clk, reset)    
    variable fifo_pixel : std_logic_vector(YCC_WIDTH-1 downto 0) := (others => '0');
    variable addr : natural := 0;
    variable counter : natural := 0;
  begin
		
    if rising_edge(clk) then
      if (fifo_read_en = '1' and reset = '1') then
        fifo_read_en <= '0';
        camera_load_latched <= camera_load;
        --fifo_pixel := fifo_pixel(YCC_WIDTH-SAMPLE_WIDTH-1 downto 0) & camera_load;
        --ycc_store <= ycc_store(YCC_WIDTH-SAMPLE_WIDTH-1 downto 0) & camera_load;
        counter := counter + 1;
        counter_read_fifo_temp <= counter;
		  end if;
		  
		  if (empty = '0') then
		    fifo_read_en <= '1';
		  end if;
      
      if (counter >= 4) then
        counter := 0;
        addr := addr + 1;
        if (addr >= YCC_RAM_SIZE) then
          addr := 0;
        end if;
      end if;
      
      if (reset = '0') then
        fifo_pixel := (others => '0');
        addr := 0;
        counter := 0;
        fifo_read_en <= '0';
      end if;
      
      --ycc_write_addr <= addr;
    end if;
  
  end process; 
  
  
  y1_filter_int <= to_integer(unsigned(y1_filter));
  y2_filter_int <= to_integer(unsigned(y2_filter));
  cb_filter_int <= to_integer(unsigned(cb_filter));
  cr_filter_int <= to_integer(unsigned(cr_filter));
  
  
  filter_first : ycc_filter
  port map(
    clk => clk,
    y => y1_filter_int,
    cb => cb_filter_int,
    cr => cr_filter_int,
    y_key => 81,
    cb_key => 90,
    cr_key => 240,
    result => filter_result_first
  );
  
  filter_last : ycc_filter
  port map(
    clk => clk,
    y => y2_filter_int,
    cb => cb_filter_int,
    cr => cr_filter_int,
    y_key => 81,
    cb_key => 90,
    cr_key => 240,
    result => filter_result_last
  );
  
  bw_mem : sram
  generic map(
    RAM_SIZE => BW_RAM_SIZE,
    DATA_WIDTH => SAMPLE_WIDTH
  )
  port map(
    clk => clk,
    we => '1',
    write_addr => bw_write_addr,
    data_in => bw_store,
    read_addr => bw_read_addr,
    data_out => bw_load
  );
  
  bw_pixel <= bw_load(bw_pixel_sel);
  
  fill_bw_buffer : process(clk, reset)
    variable counter : natural := 0;
    variable addr : natural := 0;
    variable bw_buffer : std_logic_vector(BW_BUFFER_WIDTH-1 downto 0);
  begin  
    if rising_edge(clk) then
      bw_buffer := bw_buffer(SAMPLE_WIDTH-3 downto 0) & filter_result_first & filter_result_last;
      counter := counter + 1;
      if (counter >= SAMPLE_WIDTH/2) then
        counter := 0;
        addr := addr + 1;
        if (addr >= BW_RAM_SIZE) then
          addr := 0;
          bw_wr_en <= '0';
        end if;
      end if;
      
      if (reset = '0') then
        counter := 0;
        addr := 0;
        bw_buffer := (others => '0');
        bw_wr_en <= '1';
      end if;
      
      bw_write_addr <= addr;
      bw_store <= bw_buffer;
      
    end if;
  end process;
    
end architecture structural;
