-- buff_strategy.vhd
-- Jan Viktorin <xvikto03@stud.fit.vutbr.cz>

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_arith.all;
use ieee.std_logic_unsigned.all;

library proc_common_v3_00_a;
use proc_common_v3_00_a.proc_common_pkg.log2;

---
-- Buffering strategy. Holds a number of buffers (depends on implementation).
-- Provides 3 interfaces. Only or more of them can be active at the same time.
-- 
-- * FIFO In
-- Provides FIFO-like interface for writing. Can write one pixel per CLK.
-- The input unit writes using this interface data into the buffer when
-- IN_RDY is asserted. After all data are written the unit asserts IN_DONE.
-- Internal logic then deasserts IN_RDY signal until another buffer is
-- available for writing.
--
-- If FRAME_CHECK is set the internal logic can check frames written through
-- this interface (can check e.g. whether EOL/EOF signals are asserted at the
-- right pixel). If invalid frame is detected it asserts (for one CLK) signal
-- IN_AGAIN. The frame is not stored in the buffer and it is expected to write
-- it again or to write another one.
-- If IN_DONE is asserted at the same time as IN_AGAIN, the frame is accepted.
-- In that case the signal IN_AGAIN can be used to take care of another frame
-- to be correct.
-- The signal IN_AGAIN is valid only when IN_RDY is asserted.
--
-- * FIFO out
-- If a buffer is filled by FIFO In it can be read bu FIFO out interface.
-- The interface provides the same amount data that were written and generates
-- EOL and EOF signals for that.
-- When the signal OUT_EMPTY is asserted the buffer is empty.
--
-- * MEMORY (Random Access)
-- Provides random access to a buffer. A unit can read or write (modify) the buffer
-- when MEM_RDY is asserted. After its work is done it notifies by MEM_DONE to
-- move to another buffer.
---
entity buff_strategy is
generic (
	WIDTH  : integer := 640; -- pixels
	HEIGHT : integer := 480; -- lines
	FRAME_CHECK : boolean := false
);
port (
	---
	-- Global clock domain
	---
	CLK       : in  std_logic;
	RST       : in  std_logic;

	---
	-- Control
	--
	-- Only one of IN_RDY, OUT_RDY and MEM_RDY can be asserted at the same time.
	-- *_DONE signalizes that the action in that mode was finished.
	-- IN_AGAIN asserted means that the input data are ignored and a new data
	-- are expected (fifo pointer is cleared to zero).
	---
	IN_DONE   : in  std_logic;
	IN_RDY    : out std_logic;
	IN_AGAIN  : out std_logic;
	
	OUT_DONE  : in  std_logic;
	OUT_RDY   : out std_logic;

	MEM_DONE  : in  std_logic;
	MEM_RDY   : out std_logic;
	MEM_SIZE  : out std_logic_vector(log2(WIDTH * HEIGHT) - 1 downto 0);

	---
	-- FIFO in
	--
	-- When IN_RDY is not asserted, IN_WE must be '0'.
	-- FIFO-like input interface. IN_R, IN_G, IN_B and IN_EOF, IN_EOL
	-- are data inputs that are written to the buffer on IN_WE.
	-- Writing when IN_FULL is asserted leads to undefined behaviour.
	---
	IN_R      : in  std_logic_vector(7 downto 0);
	IN_G      : in  std_logic_vector(7 downto 0);
	IN_B      : in  std_logic_vector(7 downto 0);
	IN_EOL    : in  std_logic;
	IN_EOF    : in  std_logic;

	IN_WE     : in  std_logic;
	IN_FULL   : out std_logic;

	---
	-- FIFO out
	--
	-- When OUT_RDY is not asserted OUT_RE must be '0'.
	-- Reading when OUT_EMPTY is asserted leads to undefined behaviour.
	---
	OUT_R     : out std_logic_vector(7 downto 0);
	OUT_G     : out std_logic_vector(7 downto 0);
	OUT_B     : out std_logic_vector(7 downto 0);
	OUT_EOL   : out std_logic;
	OUT_EOF   : out std_logic;

	OUT_RE    : in  std_logic;
	OUT_EMPTY : out std_logic;

	---
	-- Random Access port 0
	--
	-- When MEM_RDY is not asserted M0_WE and M0_RE must be '0'.
	-- M0_DRDY marks valid data on outputs M0_RO, M0_GO, M0_BO.
	---
	M0_A      : in  std_logic_vector(log2(WIDTH * HEIGHT) - 1 downto 0);
	M0_RO     : out std_logic_vector(7 downto 0);
	M0_GO     : out std_logic_vector(7 downto 0);
	M0_BO     : out std_logic_vector(7 downto 0);
	M0_WE     : in  std_logic;

	M0_RI     : in  std_logic_vector(7 downto 0);
	M0_GI     : in  std_logic_vector(7 downto 0);
	M0_BI     : in  std_logic_vector(7 downto 0);
	M0_RE     : in  std_logic;

	M0_DRDY   : out std_logic;

	---
	-- Random Access port 1
	--
	-- When MEM_RDY is not asserted M1_WE and M1_RE must be '0'.
	-- M1_DRDY marks valid data on outputs M1_RO, M1_GO, M1_BO.
	---
	M1_A      : in  std_logic_vector(log2(WIDTH * HEIGHT) - 1 downto 0);
	M1_RO     : out std_logic_vector(7 downto 0);
	M1_GO     : out std_logic_vector(7 downto 0);
	M1_BO     : out std_logic_vector(7 downto 0);
	M1_WE     : in  std_logic;

	M1_RI     : in  std_logic_vector(7 downto 0);
	M1_GI     : in  std_logic_vector(7 downto 0);
	M1_BI     : in  std_logic_vector(7 downto 0);
	M1_RE     : in  std_logic;

	M1_DRDY   : out std_logic
);
end entity;

architecture single of buff_strategy is

	signal in_d  : std_logic_vector(23 downto 0);
	signal out_d : std_logic_vector(23 downto 0);
	
	signal m0_di : std_logic_vector(23 downto 0);
	signal m0_do : std_logic_vector(23 downto 0);

	signal m1_di : std_logic_vector(23 downto 0);
	signal m1_do : std_logic_vector(23 downto 0);

	signal infifo_rdy : std_logic;

	signal frame_invalid : std_logic;
	signal frame_clear   : std_logic;
	signal pixel_valid   : std_logic;

begin

	buff0_i : entity work.buffer_if
	generic map (
		WIDTH  => WIDTH,
		HEIGHT => HEIGHT
	)
	port map (
		CLK       => CLK,
		RST       => RST,

		IN_DONE   => IN_DONE,
		IN_RDY    => infifo_rdy,
		IN_CLEAR  => frame_clear,
		OUT_DONE  => OUT_DONE,
		OUT_RDY   => OUT_RDY,
		MEM_DONE  => MEM_DONE,
		MEM_RDY   => MEM_RDY,
		MEM_SIZE  => MEM_SIZE,

		IN_D      => in_d,
		IN_WE     => IN_WE,
		IN_FULL   => IN_FULL,

		OUT_D     => out_d,
		OUT_RE    => OUT_RE,
		OUT_EMPTY => OUT_EMPTY,
		OUT_EOL   => OUT_EOL,
		OUT_EOF   => OUT_EOF,

		M0_A      => M0_A,
		M0_DO     => m0_do,
		M0_WE     => M0_WE,
		M0_DI     => m0_di,
		M0_RE     => M0_RE,
		M0_DRDY   => M0_DRDY,

		M1_A      => M1_A,
		M1_DO     => m1_do,
		M1_WE     => M1_WE,
		M1_DI     => m1_di,
		M1_RE     => M1_RE,
		M1_DRDY   => M1_DRDY
	);
	
	IN_RDY <= infifo_rdy;

	-----------------------------

gen_frame_check: if FRAME_CHECK = true
generate

	end_check_i : entity work.end_check
	generic map (
		WIDTH  => WIDTH,
		HEIGHT => HEIGHT
	)
	port map (
		CLK => CLK,
		RST => RST,
		PX_VLD => pixel_valid,
		IN_EOL => IN_EOL,
		IN_EOF => IN_EOF,
		CLEAR  => frame_clear,
		INVALID => frame_invalid
	);

	pixel_valid <= infifo_rdy and IN_WE;
	frame_clear <= frame_invalid or IN_DONE;
	IN_AGAIN    <= frame_invalid;

end generate;

gen_no_frame_check: if FRAME_CHECK = false
generate

	IN_AGAIN    <= '0';
	frame_clear <= '0';

end generate;

	-----------------------------

	in_d( 7 downto  0) <= IN_R;
	in_d(15 downto  8) <= IN_G;
	in_d(23 downto 16) <= IN_B;

	OUT_R <= out_d( 7 downto  0);
	OUT_G <= out_d(15 downto  8);
	OUT_B <= out_d(23 downto 16);

	m0_di( 7 downto  0) <= M0_RI;
	m0_di(15 downto  8) <= M0_GI;
	m0_di(23 downto 16) <= M0_BI;

	M0_RO <= m0_do( 7 downto  0);
	M0_GO <= m0_do(15 downto  8);
	M0_BO <= m0_do(23 downto 16);

	m1_di( 7 downto  0) <= M1_RI;
	m1_di(15 downto  8) <= M1_GI;
	m1_di(23 downto 16) <= M1_BI;

	M1_RO <= m1_do( 7 downto  0);
	M1_GO <= m1_do(15 downto  8);
	M1_BO <= m1_do(23 downto 16);

end architecture;
