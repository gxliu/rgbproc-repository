-- vga_gen.vhd
-- Jan Viktorin <xvikto03@stud.fit.vutbr.cz>
-- Copyright (C) 2011, 2012 Jan Viktorin

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

entity vga_gen is
port (
	R  : out std_logic_vector(7 downto 0);
	G  : out std_logic_vector(7 downto 0);
	B  : out std_logic_vector(7 downto 0);
	HS : out std_logic;
	VS : out std_logic;

	CLK : out std_logic
);
end entity;

architecture simple of vga_gen is

	-- for constants see any VGA spec
	-- from: Circuit Design and Simulation with VHDL, V. A. Pedroni [p. 428--429]

	constant BASE_MHZ   : time := 1 us;

	constant VGA_FREQ   : real := 25.175; -- pixel rate at 640x480, 60Hz
	constant VGA_PERIOD : time := BASE_MHZ / VGA_FREQ;

	constant HBP        : integer := 48;
	constant HFP        : integer := 16;
	constant HPULSE     : integer := 96;

	constant HPIXELS    : integer := 640; -- pixels per line
	constant VLINES     : integer := 480; -- lines per frame

	constant VBP        : integer := 33; -- 33 lines
	constant VFP        : integer := 10; -- 10 lines
	constant VPULSE     : integer :=  2; --  2 lines

	constant HACTIVE    : integer := HPIXELS;
	constant VACTIVE    : integer := VLINES;

	---------------------------------------------

	component pixel_gen is
	generic (
		WIDTH  : integer;
		HEIGHT : integer
	);
	port (
		CLK    : in  std_logic;
		RST    : in  std_logic;
		R      : out std_logic_vector(7 downto 0);
		G      : out std_logic_vector(7 downto 0);
		B      : out std_logic_vector(7 downto 0);
		PX_REQ : in  std_logic
	);
	end component;

--	for all : pixel_gen
--		use entity work.simple_pixel_gen(full);
	for all : pixel_gen
		use entity work.file_pixel_gen(plain_numbers);

	---------------------------------------------

	signal vga_clk     : std_logic;
	signal vga_rst     : std_logic;

	signal vga_r       : std_logic_vector(7 downto 0);
	signal vga_g       : std_logic_vector(7 downto 0);
	signal vga_b       : std_logic_vector(7 downto 0);

	signal vga_hs      : std_logic;
	signal vga_vs      : std_logic;

	signal vga_hactive : std_logic;
	signal vga_vactive : std_logic;
	signal vga_dena    : std_logic;

	signal new_frame   : std_logic;
	signal vga_gen_rst : std_logic;

begin

	R   <= vga_r;
	G   <= vga_g;
	B   <= vga_b;
	HS  <= vga_hs;
	VS  <= vga_vs;
	CLK <= vga_clk;

	-----------------------------

	pixel_gen_i : pixel_gen
	generic map (
		WIDTH  => HPIXELS,
		HEIGHT => VLINES
	)
	port map (
		CLK    => vga_clk,
		RST    => vga_gen_rst,
		R      => vga_r,
		G      => vga_g,
		B      => vga_b,
		PX_REQ => vga_dena
	);

	vga_dena    <= vga_hactive and vga_vactive;
	vga_gen_rst <= vga_rst or new_frame;

	-----------------------------

	sync_gen_i : process
		-- generates one row time
		-- generates hactive and hpulse (vga_hs)
		procedure one_hsync is
			variable pix : integer;
		begin
			vga_hs <= '1';
			for pix in 1 to HBP loop
				wait until rising_edge(vga_clk);	
			end loop;

			vga_hactive <= '1';
			for pix in 1 to HACTIVE loop
				wait until rising_edge(vga_clk);	
			end loop;

			vga_hactive <= '0';
			for pix in 1 to HFP loop
				wait until rising_edge(vga_clk);	
			end loop;

			vga_hs <= '0';
			for pix in 1 to HPULSE loop
				wait until rising_edge(vga_clk);
			end loop;

			vga_hs <= '1';
		end procedure;

		procedure gen_vbp is
			variable row : integer;
		begin
			report "VBP";
			vga_vs <= '1';
			for row in 1 to VBP loop
				one_hsync;
				report "VBP after " & integer'image(row);
			end loop;
		end procedure;

		procedure gen_vactive is
			variable row : integer;
		begin
			new_frame <= '1', '0' after VGA_PERIOD;

			report "VACTIVE";
			vga_vactive <= '1';
			for row in 1 to VACTIVE loop
				one_hsync;

				if row mod 48 = 0 then
					report "VACTIVE after " & integer'image(row);
				end if;
			end loop;
		end procedure;

		procedure gen_vfp is
			variable row : integer;
		begin
			report "VFP";
			vga_vactive <= '0';
			for row in 1 to VFP loop
				one_hsync;
				report "VFP after " & integer'image(row);
			end loop;

		end procedure;

		procedure gen_vpulse is
			variable row : integer;
		begin
			report "VPULSE";
			vga_vs <= '0';
			for row in 1 to VPULSE loop
				one_hsync;
			end loop;
			vga_vs <= '1';
		end procedure;

		procedure one_frame is
			variable row : integer;
		begin
			gen_vbp;
			gen_vactive;
			gen_vfp;
			gen_vpulse;
		end procedure;

		variable i : integer;
	begin
		vga_vs      <= '1';
		vga_vactive <= '0';
		vga_hs      <= '1';
		vga_hactive <= '0';
		new_frame   <= '0';

		report "VSYNC Reset";
		wait until vga_rst = '0';
		wait for 6 * VGA_PERIOD;
		wait until rising_edge(vga_clk);

		-- generate a malformed frame at the beginning
		gen_vfp;
		gen_vpulse;

		for i in 1 to 60 loop
			one_frame;
		end loop;
		wait;
	end process;

	-----------------------------

	vga_clkgen_i : process
	begin
		vga_clk <= '1';
		wait for VGA_PERIOD / 2;
		vga_clk <= '0';
		wait for VGA_PERIOD / 2;
	end process;

	vga_rstgen_i : process
	begin
		vga_rst <= '1';
		wait for 64 * VGA_PERIOD;
		vga_rst <= '0';

		wait;
	end process;

end architecture;

