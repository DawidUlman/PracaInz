
LIBRARY IEEE;
USE IEEE.STD_LOGIC_1164.ALL;
USE IEEE.numeric_std.ALL;
use IEEE.std_logic_unsigned.all;

ENTITY Codec IS
GENERIC (
clk_freq     : INTEGER := 50000000;
i2c_clk_freq : INTEGER := 20000;
N : INTEGER := 10000
);
PORT
(
clk        : IN    STD_LOGIC;
reset      : IN    STD_LOGIC;
done       : OUT   STD_LOGIC;
iic_scl_io : OUT   STD_LOGIC;
iic_sda_io : INOUT STD_LOGIC;
SAMPLE_CTRL : in STD_LOGIC_VECTOR(15 DOWNTO 0)
);
END Codec;

ARCHITECTURE Init OF Codec IS

SIGNAL i2c_clk, i2c_end, SDO : STD_LOGIC;
SIGNAL go                    : BOOLEAN;
SIGNAL ack                   : STD_LOGIC_VECTOR (1 TO 3);
SIGNAL num                   : unsigned(3 DOWNTO 0);
SIGNAL i2c_out               : STD_LOGIC_VECTOR(15 DOWNTO 0);
SIGNAL cnt : STD_LOGIC_VECTOR(N-1 downto 0);

CONSTANT address : STD_LOGIC_VECTOR (7 DOWNTO 0) := x"34"; -- I2C device address, CSB set to 0 (p. 17)
TYPE codec IS ARRAY (0 TO 11) OF STD_LOGIC_VECTOR (15 DOWNTO 0);
CONSTANT Audio_init : codec :=
                              (
                              x"F000", -- reset
                              x"0C30", -- R6 default (0C9F), power on line in, adc, dac, no out(0C12), out on(0C02) (p. 23)
                              x"001F", -- R0 changed LINVOL, +33 dB(003F) (p. 20), default (0017), +6 dB (001F)
                              x"021F", -- R1 changed RINVOL, +33 dB(023F) (p. 21), default (0297), +6 dB (021F)
                              x"047B", -- R2 changed LHPVOL, +6 dB(047F) (p. 21), default (0479) (047B) (0579)
                              x"067B", -- R3 changed RHPVOL, +6 dB(067F) (p. 22), default (0679) (067B)
                              x"0810", -- R4 changed A audio path, DAC select with bypass(081A/0818) (p. 22), default (080A), only DAC (0810) 0878
                              x"0A06", -- R5 changed D audio path, DAC enabled (0A00), default (0A08) (p. 23)
                              x"0E01", -- R7 16-bit, left justified, slave md (0E01), default (0E0A) (p. 24)
                              x"1002", -- R8 default, ADC and DAC 48kHz (p. 24)
                            --   x"1E01", -- R15
                            --   x"207B", -- R16
                            --   x"2232", -- R17
                            --   x"2400", -- R18
                              x"1201", -- R9 set active (1201), default (1200)
                              x"0C20"  --- R6, power on out and other selected
                              );
TYPE statei2c IS(s1, s2, s3, s4, s5);
SIGNAL AUDIO : statei2c;

BEGIN
iic_sda_io <= '0' WHEN SDO = '0' ELSE 'Z';

--Clock 

Licznik : PROCESS (clk, reset) IS
BEGIN
    IF (reset = '1') THEN
        cnt <= (others => '0');
    ELSIF (clk'event AND clk = '1') THEN
        cnt <= cnt + 1;
    END IF;
END PROCESS;


Clock_gen : PROCESS (clk, reset) IS
variable count : INTEGER RANGE 0 TO clk_freq/i2c_clk_freq;
BEGIN
    IF (reset = '1') THEN
        i2c_clk <= '0';
        count := 0;
    ELSIF (clk'event AND clk = '1') THEN
        IF (count < (clk_freq/i2c_clk_freq) - 1) THEN
            count := count + 1;
        ELSE
            count := 0;
            i2c_clk <= NOT i2c_clk;
        END IF;
    END IF;
END PROCESS;


--Setting the configuration

audio_conf : PROCESS (i2c_clk, reset) IS
BEGIN
    IF (reset = '1') THEN 
        go    <= false;
        num   <= "0000";
        done  <= '1';
        Audio <= s1;
    ELSIF (i2c_clk 'event AND i2c_clk = '1') THEN
CASE AUDIO IS
WHEN s1 =>
    go <= true;
    if(num = 10) then 
        i2c_out <= SAMPLE_CTRL;
    else
        if (num = 11) then 
            if (cnt = std_logic_vector(to_signed(N, cnt'length))) then 
                i2c_out <= Audio_init(to_integer (num));
            else 
                Audio <= s5;   
            end if;
        else
            i2c_out <= Audio_init(to_integer (num));
        end if;
    end if;
    Audio <= s2;
WHEN s2 =>
    IF (i2c_end = '1') THEN
        go    <= false;
        Audio <= s3;
    END IF;
WHEN s3 =>
    IF (ack = "000") THEN
        Audio <= s4;
    ELSE
        Audio <= s1;
    END IF;
WHEN s4 =>
    num   <= num + 1;
    Audio <= s5;
WHEN s5 =>
    IF (num < 12) THEN
        Audio <= s1;
    ELSE
        done <= '0';
    END IF;
WHEN OTHERS =>
    Audio <= s1;
END CASE;
END IF;
END PROCESS;

--Transreciver

I2C_port: PROCESS(i2c_clk,reset) is
    VARIABLE index: INTEGER RANGE 0 to 32;
begin
    if (index <=1 or index >= 31) then iic_scl_io <='1';
        ELSIF (index =2 or index = 30) then iic_scl_io <='0';
            ELSE iic_scl_io <= not i2c_clk;
        end if;
    if (reset = '1') then 
        SDO <='1';
        i2c_end <='0';
        ack <="000";
        index:= 0;
        ELSIF(i2c_clk'event and i2c_clk = '1') then
            if(go) then index := index +1; else index :=0; end if; 
            if(index = 0) then 
                SDO <='1';
                i2c_end <='0';
                ack <= "000";
            elsif(index = 1) then 
                    SDO <='0';
            elsif(index = 2) then 
                null;
            elsif(index >= 3 and index <=10) then 
                SDO <=address(10-index);
            elsif(index =11) then
                SDO <='1';
            elsif(index =12) then
                SDO <=i2c_out(15);
                ack(1)<=iic_sda_io;
            elsif(index >= 13 and index <= 19) then
                SDO <=i2c_out(27-index);
            elsif(index =20) then
                SDO <='1';
            elsif(index =21) then
                SDO <=i2c_out(7);
                ack(2)<=iic_sda_io;
            elsif(index >= 22 and index <=28) then
                SDO <=i2c_out(28-index);
            elsif(index =29) then
                SDO <='1';
            elsif(index =30) then
                SDO <='0';
                ack(3) <=iic_sda_io;
            elsif(index =31) then
                null;
            elsif(index =32) then
                SDO <='1';
                i2c_end <='1';
            end if;
        end if;
    end PROCESS I2C_port;
END Init;
