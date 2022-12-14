library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.NUMERIC_STD.ALL;


entity Overdrive is
    port( 
        led3 : out STD_LOGIC;
        sw0 : in STD_LOGIC;
        led1 : out STD_LOGIC;
        sw1 : in STD_LOGIC;
        led2 : out STD_LOGIC;
        clk : in STD_LOGIC;
        reset : in STD_LOGIC;
        ac_mclk : buffer STD_LOGIC;
        iic_scl_io : OUT   STD_LOGIC;
        iic_sda_io : INOUT STD_LOGIC;
        ac_bclk : buffer STD_LOGIC;
        ac_pbdat : in STD_LOGIC;
        ac_pblrc : out STD_LOGIC;
        ac_recdat : out STD_LOGIC;
        ac_reclrc : out STD_LOGIC;
        ac_muten : out STD_LOGIC 
    );
end Overdrive;

architecture Behavioral of Overdrive is

SIGNAL Lin, Rin, Lout, Rout : signed(15 downto 0);
SIGNAL Ldone, Rdone : STD_LOGIC;
signal temp_vec_64 : STD_LOGIC_VECTOR(31 downto 0);
signal count_int2: integer;
signal direction_s2: std_logic := '0';
signal clk_cntr : std_logic_vector(25 downto 0) := (others => '0');
signal clk_48, clk_190 : STD_LOGIC;

begin
ac_muten <= '1';
interface: entity work.D_Transreciv GENERIC map (Sample_Rate => 48)
port map (
    clk => clk,
    reset => reset,
    ac_mclk => ac_mclk, 
    iic_scl_io => iic_scl_io,
    iic_sda_io => iic_sda_io,
    ac_bclk => ac_bclk,
    ac_pbdat => ac_pbdat,
    ac_pblrc => ac_pblrc,
    ac_recdat => ac_recdat,
    ac_reclrc => ac_reclrc,
    Rin => Rin,
    Lin => Lin,
    Rout => Rout,
    Lout => Lout,
    Rdone => Rdone,
    Ldone => Ldone
);

count: process(clk)
begin
    if rising_edge(clk) then
        clk_cntr <= std_logic_vector(unsigned(clk_cntr)+1);       
    end if;
end process;

clk_48 <= clk_cntr(19);
clk_190 <= clk_cntr(17);

led3 <= std_logic(Lin(10));

process(count_int2) --tremolo frequency - 3.2 hz
begin
    if (count_int2=30) then
        direction_s2 <= '1';
    end if;
    if (count_int2=1) then
        direction_s2 <= '0';
    end if;
end process;
dir2:process(direction_s2, clk_190)
begin
if rising_edge(clk_190) then 
    if (direction_s2='0') then
    count_int2 <= count_int2+1;
    end if;
    if (direction_s2='1') then
    count_int2 <= count_int2-1;
end if;
end if;
end process;


process(ac_mclk)
begin
if rising_edge(ac_mclk) then 
  if (sw1 = '1') then 
    led2 <= '1';
    temp_vec_64 <= std_logic_vector((signed(Lin)) * count_int2); 
    Lout <= "00000" & shift_right(signed(temp_vec_64(10 downto 0)),4);
  else 
    led2 <= '0';
    Lout<=Lin;
  end if;
  if (sw0 = '1') then 
    led1 <= '1';
    if (Lin(10 downto 0)) >= 70000 then
        Lout<=to_signed(90000,16);    
      elsif (Lin(10 downto 0)) <= -75000 then
        Lout<=to_signed(-90000,16);
      end if;
  else 
    led1 <= '0';
    Lout<=Lin;
  end if; 
end if;
end process;


end Behavioral;