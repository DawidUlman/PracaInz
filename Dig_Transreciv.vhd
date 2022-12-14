library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
USE IEEE.numeric_std.ALL;

entity D_Transreciv is
        generic(
            Sample_Rate : natural := 48;
            clk_freq : natural := 50000000;
            div : natural := 7;
            mult : natural := 19
        );
        port( 
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
                Rin, Lin : out signed (15 DOWNTO 0);
                Rout, Lout : in signed (15 DOWNTO 0);
                Rdone, Ldone : out STD_LOGIC
            );
end D_Transreciv;

architecture SSM of D_Transreciv is
    type state is (wait1, wait2, left1, left2, left3, left4, left5, right1, right2, right3, right4, right5);
    SIGNAL RCV : state;

    CONSTANT word_count : natural :=18432/(2*Sample_Rate);
    CONSTANT bit_count : natural := word_count/(2*16);
    SIGNAL Sample_CTRL : STD_LOGIC_VECTOR(15 DOWNTO 0);
    SIGNAL word_range : natural;
    SIGNAL bit_range : natural;
    SIGNAL done : STD_LOGIC;
    SIGNAL lrck : STD_LOGIC;
    -- Signal Rin, Lin : signed (15 DOWNTO 0);
    -- Signal Rout, Lout : signed (15 DOWNTO 0);
    -- signal Rdone, Ldone : STD_LOGIC;

begin
    assert(Sample_Rate = 8 or Sample_Rate = 32 or Sample_Rate = 48 or Sample_Rate = 96)
    REPORT "The selected sample rate was not supported." severity error;

    Sample_CTRL <= x"100E" when Sample_Rate = 8 else x"101A" when Sample_Rate =32 else x"101E" when Sample_Rate =96 else x"1002";

    word_range <= word_count*2 when Sample_Rate =96 else word_count;

    bit_range <= bit_count*2 when Sample_Rate = 96 else bit_count;

I2C_controller:entity work.Codec port map(
    clk => clk,
    reset => reset,
    done => done,
    iic_scl_io => iic_scl_io,
    iic_sda_io => iic_sda_io,
    Sample_CTRL => Sample_CTRL
);

-- Sin_wave:entity work.sinewave port map(
--     clk => clk,
--     dout => Lin
-- );


ac_pblrc <= lrck;
ac_reclrc <= lrck;

-- MCLK

Clock_gen : PROCESS (clk, done) IS
    VARIABLE count : INTEGER RANGE 0 TO (clk_freq/div)*mult;
    BEGIN
        IF (done = '1') THEN
            ac_mclk <= '0';
            count := 0;
        ELSIF (clk'event AND clk = '1') THEN
            IF (count < ((clk_freq/div)*mult)- 1) THEN
                count := count + 1;
            ELSE
                count := 0;
                ac_mclk <= NOT ac_mclk;
            END IF;
        END IF;
    END PROCESS;

-- BCLK and LRCK init 

Bclock: PROCESS(ac_mclk, reset) is 
    variable bcount : integer RANGE 0 to bit_count*2;
    variable wcount : integer RANGE 0 to word_count*2;
    begin
        if(reset='1') then 
            ac_bclk <='0';
            lrck <='1';
            bcount :=0;
            wcount :=0;
        elsif(ac_mclk'event and ac_mclk='1') then 
            if (bcount >= bit_range - 1) then 
                bcount :=0;
                ac_bclk <= not ac_bclk;
            else
                bcount :=0;
            end if;
            if (wcount >= word_range - 1) then
                wcount :=0;
                lrck <= not lrck;
            else
                wcount := wcount + 1;
            end if;
        end if;
    end PROCESS;

--Send and recive audio data

Send_Recive: PROCESS(ac_mclk, reset)
    variable k: integer RANGE 0 to 15;
begin
    if(reset='1') then 
        k :=0;
        RCV <= wait1;
        Rdone <='0';
        Ldone <='0';
    elsif(ac_mclk'event and ac_mclk = '1') then 
        CASE RCV is
        when wait1 =>
            if (lrck='0') then RCV <= wait2; 
            end if;
        when wait2 =>
            Rdone <='0';
            if (lrck='1') then RCV <= left1;
            end if;
        when left1 => 
            if(ac_bclk='0') then 
                RCV <= left2;
            end if;
            ac_recdat <= Lout(15-k); 
        when left2 => 
            if(ac_bclk='1') then 
                RCV <= left3;
                Lin(15-k) <= ac_pbdat;
            end if;
        when left3 =>  
                k := k+1;
                RCV <= left4;
        when left4 => 
            if(k = 0) then 
                RCV <= left5;
            else
                RCV <=left1;
            end if;
        when left5 =>
            Ldone <= '1';
            RCV <= right1;
        when right1 => 
            if(ac_bclk='0') then 
                RCV <= right2;
            end if;
            ac_recdat <= Rout(15-k); 
        when right2 => 
            if(ac_bclk='1') then 
                RCV <= right3;
                Rin(15-k) <= ac_pbdat;
            end if;
        when right3 =>  
                k := k+1;
                RCV <= right4;
        when right4 => 
            if(k = 0) then 
                RCV <= right5;
            else
                RCV <=right1;
            end if;
        when right5 =>
            Rdone <= '1';
            RCV <= wait2;
        when OTHERS =>
            RCV <=wait1;
        end CASE;
    end if;
end PROCESS;
end SSM;