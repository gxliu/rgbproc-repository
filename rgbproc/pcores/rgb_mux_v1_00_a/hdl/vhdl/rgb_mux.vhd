-- rgb_mux.vhd
-- Jan Viktorin <xvikto03@stud.fit.vutbr.cz>
-- Copyright (C) 2011, 2012 Jan Viktorin

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library utils_v1_00_a;
use utils_v1_00_a.ipif_reg;
use utils_v1_00_a.ipif_reg_logic;

---
-- Multiplexor on RGB bus. Allows to switch between 2 input
-- RGB branches. The switch command is performed over IPIF
-- interface (usually from a processor core).
---
entity rgb_mux is
generic (
	IPIF_AWIDTH : integer := 32;
	IPIF_DWIDTH : integer := 32;
	DEFAULT_SRC : integer := 0
);
port (
	CLK     : in  std_logic;
	CE      : in  std_logic;
	RST     : in  std_logic;

	Bus2IP_Addr  : in  std_logic_vector(IPIF_AWIDTH - 1 downto 0);
	Bus2IP_CS    : in  std_logic_vector(0 downto 0);
	Bus2IP_RNW   : in  std_logic;
	Bus2IP_Data  : in  std_logic_vector(IPIF_DWIDTH - 1 downto 0);
	Bus2IP_BE    : in  std_logic_vector(IPIF_DWIDTH/8 - 1 downto 0);
	IP2Bus_Data  : out std_logic_vector(IPIF_DWIDTH - 1 downto 0);
	IP2Bus_RdAck : out std_logic;
	IP2Bus_WrAck : out std_logic;
	IP2Bus_Error : out std_logic;

	IN0_R   : in  std_logic_vector(7 downto 0);
	IN0_G   : in  std_logic_vector(7 downto 0);
	IN0_B   : in  std_logic_vector(7 downto 0);
	IN0_DE  : in  std_logic;
	IN0_HS  : in  std_logic;
	IN0_VS  : in  std_logic;

	IN1_R   : in  std_logic_vector(7 downto 0);
	IN1_G   : in  std_logic_vector(7 downto 0);
	IN1_B   : in  std_logic_vector(7 downto 0);
	IN1_DE  : in  std_logic;
	IN1_HS  : in  std_logic;
	IN1_VS  : in  std_logic;

	OUT_R   : out std_logic_vector(7 downto 0);
	OUT_G   : out std_logic_vector(7 downto 0);
	OUT_B   : out std_logic_vector(7 downto 0);
	OUT_DE  : out std_logic;
	OUT_HS  : out std_logic;
	OUT_VS  : out std_logic
);
end entity;

---
-- Branch switch is performed only during vertical pulse.
-- It first waits for the pulse of current line and then
-- waits (generating pulse) for a pulse of the target line.
-- Thus the change can drive the output screen black for a while.
--
-- Address space:
--  <address>   <access>  <description>   <width>  <default>
--  0x00000000  RO        device type id  16b      1
--  0x00000004  RW        select of line   1b      generic DEFAULT_SRC
--    * Reading from the register obtains current state.
--      Thus after a write the new value can not usually be
--      read immediately. The delay can be about one frame.
--    * Changing of line can not be cancelled. When another value
--      is written durning the lines change and it is different
--      from the new one another transition will occur.
---
architecture full of rgb_mux is

	type state_t is (s_src0, s_src1, s_sync0_to_1, s_0_to_sync1, s_sync1_to_0, s_1_to_sync0);
	signal state  : state_t;
	signal nstate : state_t;

	signal sync0        : std_logic;
	signal sync1        : std_logic;
	signal pulse_start0 : std_logic;
	signal pulse_start1 : std_logic;

	signal src_sel_be   : std_logic;
	signal src_sel_we   : std_logic;
	signal src_sel_in   : std_logic;
	signal src_sel      : std_logic;
	signal cur_sel      : std_logic;

	signal reg_r  : std_logic_vector(7 downto 0);
	signal reg_g  : std_logic_vector(7 downto 0);
	signal reg_b  : std_logic_vector(7 downto 0);
	signal reg_de : std_logic;
	signal reg_hs : std_logic;
	signal reg_vs : std_logic;

	signal ipif_cs     : std_logic_vector(1 downto 0);
	signal ipif_data   : std_logic_vector(63 downto 0);
	signal ipif_wrack  : std_logic_vector(1 downto 0);
	signal ipif_rdack  : std_logic_vector(1 downto 0);
	signal ipif_error  : std_logic_vector(1 downto 0);
	signal ipif_gerror : std_logic;

	signal ipif_werror : std_logic;
	signal ipif_rerror : std_logic;

begin

	---
	-- Device ID register
	---
	reg_id : entity utils_v1_00_a.ipif_reg
	generic map (
		REG_DWIDTH  => 16,
		REG_DEFAULT => X"0001",
		IPIF_DWIDTH => IPIF_DWIDTH,
		IPIF_MODE   => 0
	)
	port map (
		CLK          => CLK,
		RST          => RST,

		IP2Bus_Data  => ipif_data(31 downto 0),
		IP2Bus_WrAck => ipif_wrack(0),
		IP2Bus_RdAck => ipif_rdack(0),
		IP2Bus_Error => ipif_error(0),		
		Bus2IP_Data  => Bus2IP_Data,
		Bus2IP_BE    => Bus2IP_BE,
		Bus2IP_RNW   => Bus2IP_RNW,
		Bus2IP_CS    => ipif_cs(0),

		REG_DI       => (15 downto 0 => 'X'),
		REG_WE       => '0'
	);

	---
	-- MUX select register
	---
	cfg_sel : entity utils_v1_00_a.ipif_reg_logic
	generic map (
		REG_DWIDTH  => 1,
		IPIF_DWIDTH => IPIF_DWIDTH,
		IPIF_MODE   => 2
	)
	port map (
		CLK          => CLK,
		RST          => RST,

		IP2Bus_Data  => ipif_data(63 downto 32),
		IP2Bus_WrAck => ipif_wrack(1),
		IP2Bus_RdAck => ipif_rdack(1),
		IP2Bus_Error => ipif_error(1),		
		Bus2IP_Data  => Bus2IP_Data,
		Bus2IP_BE    => Bus2IP_BE,
		Bus2IP_RNW   => Bus2IP_RNW,
		Bus2IP_CS    => ipif_cs(1),

		REG_DO(0)    => cur_sel,
		REG_BE(0)    => src_sel_be,
		REG_DI(0)    => src_sel_in,
		REG_WE       => src_sel_we
	);

	src_selp : process(CLK, RST, src_sel_we, src_sel_be, src_sel_in)
	begin
		if rising_edge(CLK) then
			if RST = '1' then
				if DEFAULT_SRC = 0 then
					src_sel <= '0';
				else
					src_sel <= '1';
				end if;
			elsif src_sel_we = '1' and src_sel_be = '1' then
				src_sel <= src_sel_in;
			end if;
		end if;
	end process;

	---
	-- IPIF address logic
	---

	ipif_cs(0)  <= Bus2IP_CS(0) when Bus2IP_Addr = X"00000000" else '0';
	ipif_cs(1)  <= Bus2IP_CS(0) when Bus2IP_Addr = X"00000004" else '0';
	
	-- invalid address request
	ipif_gerror <= Bus2IP_CS(0) when ipif_cs = "00" else '0';

	IP2Bus_Data <= ipif_data(63 downto 32) when ipif_cs = "10" else
                  ipif_data(31 downto  0);

	ipif_werror <= ipif_gerror when Bus2IP_CS(0) = '1' and Bus2IP_RNW = '0' else '0';
	ipif_rerror <= ipif_gerror when Bus2IP_CS(0) = '1' and Bus2IP_RNW = '1' else '0';

	IP2Bus_WrAck <= ipif_wrack(0) or ipif_wrack(1) or ipif_werror;
	IP2Bus_RdAck <= ipif_rdack(0) or ipif_rdack(1) or ipif_rerror;
	IP2Bus_Error <= ipif_error(0) or ipif_error(1) or ipif_gerror;

	----------------------------------

	sync0 <= IN0_HS or IN0_VS;
	sync1 <= IN1_HS or IN1_VS;

	----------------------------------

	detect_start_of_pulse0 : entity work.detect_start_of_pulse
	port map (
		CLK  => CLK,
		RST  => RST,
		SYNC => sync0,
		SOP  => pulse_start0
	);

	detect_start_of_pulse1 : entity work.detect_start_of_pulse
	port map (
		CLK  => CLK,
		RST  => RST,
		SYNC => sync1,
		SOP  => pulse_start1
	);

	----------------------------------

	fsm_state : process(CLK, RST, nstate)
	begin
		if rising_edge(CLK) then
			if RST = '1' then
				if DEFAULT_SRC = 0 then
					state <= s_src0;
				else
					state <= s_src1;
				end if;
			else
				state <= nstate;
			end if;
		end if;
	end process;

	fsm_next : process(CLK, state, src_sel, IN0_HS, IN0_VS, IN1_HS, IN1_VS)
	begin
		nstate <= state;

		case state is
		when s_src0 =>
			if src_sel = '1' and IN0_HS = '0' and IN0_VS = '0' and pulse_start1 = '1' then
				nstate <= s_src1;
			elsif src_sel = '1' and IN0_HS = '0' and IN0_VS = '0' then
				nstate <= s_0_to_sync1;
			elsif src_sel = '1' then
				nstate <= s_sync0_to_1;
			end if;

		when s_sync0_to_1 =>
			if IN0_HS = '0' and IN0_VS = '0' then
				nstate <= s_0_to_sync1;
			end if;

		when s_0_to_sync1 =>
			if pulse_start1 = '1' then
				nstate <= s_src1;
			end if;

		when s_src1 =>
			if src_sel = '0' and IN1_HS = '0' and IN1_VS = '0' and pulse_start0 = '1' then
				nstate <= s_src0;
			elsif src_sel = '0' and IN1_HS = '0' and IN1_VS = '0' then
				nstate <= s_1_to_sync0;
			elsif src_sel = '0' then
				nstate <= s_sync1_to_0;
			end if;

		when s_sync1_to_0 =>
			if IN1_HS = '0' and IN1_VS = '0' then
				nstate <= s_1_to_sync0;
			end if;

		when s_1_to_sync0 =>
			if pulse_start0 = '1' then
				nstate <= s_src0;
			end if;

		end case;
	end process;

	fsm_output : process(CLK, state)
	begin
		case state is
		when s_src0 | s_sync0_to_1 =>
			cur_sel <= '0';

		when s_0_to_sync1 =>
			cur_sel <= '0';

		when s_src1 | s_sync1_to_0 =>
			cur_sel <= '1';

		when s_1_to_sync0 =>
			cur_sel <= '1';
			
		end case;
	end process;

	---------------------------------

	reg_r  <= IN0_R  when cur_sel = '0' else
	          IN1_R;
	reg_g  <= IN0_G  when cur_sel = '0' else
	          IN1_G;
	reg_b  <= IN0_B  when cur_sel = '0' else
	          IN1_B;
	reg_de <= IN0_DE when cur_sel = '0' else
	          IN1_DE;
	reg_hs <= IN0_HS when cur_sel = '0' else
	          IN1_HS;
	reg_vs <= IN0_VS when cur_sel = '0' else
	          IN1_VS;

	regp : process(CLK, CE, reg_r, reg_g, reg_b, reg_de, reg_hs, reg_vs)
	begin
		if rising_edge(CLK) then
			if CE = '1' then
				OUT_R  <= reg_r;
				OUT_G  <= reg_g;
				OUT_B  <= reg_b;
				OUT_DE <= reg_de;
				OUT_HS <= reg_hs;
				OUT_VS <= reg_vs;
			end if;
		end if;
	end process;

end architecture;
