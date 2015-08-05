library IEEE;
use IEEE.STD_LOGIC_1164.all;
use IEEE.NUMERIC_STD.all;
library riscv;
use riscv.components.all;
use riscv.utils.all;

entity riscV is

  generic (
    REGISTER_SIZE        : integer;
    INSTRUCTION_MEM_SIZE : integer;
    DATA_MEMORY_SIZE     : integer);
  port(clk             : in  std_logic;
       reset           : in  std_logic;
       program_counter : out std_logic_vector(REGISTER_SIZE-1 downto 0));

end entity riscV;

architecture rtl of riscV is
  constant REGISTER_NAME_SIZE  : integer := 5;
  constant INSTRUCTION_SIZE    : integer := 32;
  constant SIGN_EXTENSION_SIZE : integer := 20;

  --address is in words, so subtract 2
  constant DATA_ADDR_WIDTH : integer := log2(DATA_MEMORY_SIZE)-2;

  --signals going int fetch
  signal pc_corr_en : std_logic;
  signal pc_corr    : std_logic_vector(REGISTER_SIZE-1 downto 0);

  --signals going into decode
  signal d_instr   : std_logic_vector(INSTRUCTION_SIZE -1 downto 0);
  signal d_pc      : std_logic_vector(REGISTER_SIZE-1 downto 0);
  signal d_next_pc : std_logic_vector(REGISTER_SIZE-1 downto 0);

  signal wb_data : std_logic_vector(REGISTER_SIZE-1 downto 0);
  signal wb_sel  : std_logic_vector(REGISTER_NAME_SIZE-1 downto 0);
  signal wb_en   : std_logic;

  --signals going into execute
  signal e_instr        : std_logic_vector(INSTRUCTION_SIZE -1 downto 0);
  signal e_pc           : std_logic_vector(REGISTER_SIZE-1 downto 0);
  signal e_next_pc      : std_logic_vector(REGISTER_SIZE-1 downto 0);
  signal rs1_data       : std_logic_vector(REGISTER_SIZE-1 downto 0);
  signal rs2_data       : std_logic_vector(REGISTER_SIZE-1 downto 0);
  signal sign_extension : std_logic_vector(REGISTER_SIZE-12-1 downto 0);

  signal pipeline_flush : std_logic;

  signal data_address    : std_logic_vector(REGISTER_SIZE-1 downto 0);
  signal data_byte_en    : std_logic_vector(REGISTER_SIZE/8 -1 downto 0);
  signal data_write_en   : std_logic;
  signal data_read_en    : std_logic;
  signal data_write_data : std_logic_vector(REGISTER_SIZE-1 downto 0);
  signal data_read_data  : std_logic_vector(REGISTER_SIZE-1 downto 0);
  signal data_busy       : std_logic;

  signal data_address_int : integer range 0 to 2 ** DATA_ADDR_WIDTH -1;
begin  -- architecture rtl
  pipeline_flush <= reset or pc_corr_en;
  instr_fetch : component instruction_fetch
    generic map (
      REGISTER_SIZE        => REGISTER_SIZE,
      INSTRUCTION_SIZE     => INSTRUCTION_SIZE,
      INSTRUCTION_MEM_SIZE => INSTRUCTION_MEM_SIZE)
    port map (
      clk        => clk,
      reset      => reset,
      pc_corr    => pc_corr,
      pc_corr_en => pc_corr_en,

      instr_out   => d_instr,
      pc_out      => d_pc,
      next_pc_out => d_next_pc);

  D : component decode
    generic map(
      REGISTER_SIZE       => REGISTER_SIZE,
      REGISTER_NAME_SIZE  => REGISTER_NAME_SIZE,
      INSTRUCTION_SIZE    => INSTRUCTION_SIZE,
      SIGN_EXTENSION_SIZE => SIGN_EXTENSION_SIZE)
    port map(
      clk            => clk,
      reset          => pipeline_flush,
      instruction    => d_instr,
      --writeback ,signals
      wb_sel         => wb_sel,
      wb_data        => wb_data,
      wb_enable      => wb_en,
      --output sig,nals
      rs1_data       => rs1_data,
      rs2_data       => rs2_data,
      sign_extension => sign_extension,
      --inputs jus,t for carrying to next pipeline stage
      pc_next_in     => d_next_pc,
      pc_curr_in     => d_pc,
      instr_in       => d_instr,
      pc_next_out    => e_next_pc,
      pc_curr_out    => e_pc,
      instr_out      => e_instr);
  X : component execute
    generic map (
      REGISTER_SIZE       => REGISTER_SIZE,
      REGISTER_NAME_SIZE  => REGISTER_NAME_SIZE,
      INSTRUCTION_SIZE    => INSTRUCTION_SIZE,
      SIGN_EXTENSION_SIZE => SIGN_EXTENSION_SIZE)
    port map (
      clk             => clk,
      reset           => pipeline_flush,
      pc_next         => e_next_pc,
      pc_current      => e_pc,
      instruction     => e_instr,
      rs1_data        => rs1_data,
      rs2_data        => rs2_data,
      sign_extension  => sign_extension,
      wb_sel          => wb_sel,
      wb_data         => wb_data,
      wb_en           => wb_en,
      predict_corr    => pc_corr,
      predict_corr_en => pc_corr_en,
      address         => data_address,
      byte_en         => data_byte_en,
      write_en        => data_write_en,
      read_en         => data_read_en,
      write_data      => data_write_data,
      read_data       => data_read_data,
      busy            => data_busy);

  --should always be available right away
  data_busy <= '0';
  --NB there is some logic below that accounts for changing
  --addresses from byte addresses to word addresses
  data_address_int <= to_integer(unsigned(data_address(DATA_ADDR_WIDTH+2-1 downto 2)));
  data_memory : component byte_enabled_simple_dual_port_ram
    generic map (
      ADDR_WIDTH => DATA_ADDR_WIDTH,
      BYTE_WIDTH => 8,
      BYTES      => REGISTER_SIZE/8)
    port map (
      clk   => clk,
      we    => data_write_en,
      be    => data_byte_en,
      wdata => data_write_data,
      waddr => data_address_int,
      raddr => data_address_int,
      q     => data_read_data);

    program_counter <= d_pc;
end architecture rtl;
