;
; **********************************************
; * CPL ADC Board*
; * Rev 1, May 2014 *
; * 2014 by Matt Einhorn *
; **********************************************
; * ADC crystal is to be run at 6 MHz, microcontroller crystal at
; * 20 MHz. USB clock rate is 1MHz or less.
; * The pins connected to the USB bus are
; * byte aligned. I.e. if bit 0 on the micro 
; * bus is connected to bit 3 on USB bus, then
; * bit 1 on the micro is connected to bit 4
; * on the USB bus etc.
; * Also, on the micro, data is sent on the
; * highest bits, while on the USB bus they
; * are read on the low bits. E.g. if two
; * bits of data is sent at a time, then on
; * the micro they are set at bits 6-7 of the
; * bus, which are connected to bits 0-1 on
; * the USB bus.
; * On the USB bus, the clock bit is the highest
; * bit following data bits. So currently, the
; * # of data bits on the USB bus is 7. On the
; * micro, the clock line is on a separate bus,
; * so 8 bits are availible for data.
;
; The total buffer length availible for saving data
; is 2-8 byte aligned (see collect_adc).
;
; Unused ports are set as inputs with pull-ups enabled.
;
; Upon power up or reset, all USB bus data pins are inputs with pull-up
; enabled. We wait for 40 cycles of the clock going low/high. Then
; for another 10 cycles of the pin 7 on the data bus going low/high.
; Then, the pin 6 on the data bus is configured as an output and the 
; USB starts sending configuration data on pin 7 with each low/high 
; clock cycle on the clock pin. Pin 6 mirrors the configuration data 
; back to the USB on each high clock for confirmation. Subsequently,
; after a single low/high of the clock, all USB data bus pins get 
; configured as outputs.
;
; 
;
; **********************************************
;
.NOLIST
.INCLUDE "m1284Pdef.inc"
.LIST
;
; ============================================
; H A R D W A R E I N F O R M A T I O N
; ============================================
;
; The device runs on a 20MHz full swing crystal. The fuse bits CKSEL3..0 should be set
; to 0110. The crystal is a ABRACON, ABMM2-20.000MHZ-E2-T with load cap = 18pF.
; When the wdr is ON the TO is about 2 Sec.
; Fuse bits BLB12, 11, 02, 01, LB1, LB2 are left unprogrammed (1).
; - Lock bits are all unprogrammed (1).
; - Fuse extended byte is: 0b11111100
; BODLEVEL 2:0 is 100 which enables BOD at 4.5V.
; - Fuse high byte is: 0b11011001
; On chip debug, JTAG, Watchdog always ON, EEsave, boot reset are all disabled (1).
; SPI programming and boot size are set (0).
; - Fuse low byte is: 0b11100110
; CKDIV8, CKOUT, are all disabled (1).
; SUT1..0, CKSEL3..0 are set (0).
;
; ATmega1284P
; Fuse bits: 0b11111100.11011001.11100110, 0xFCD9D7
; Lock bits: 0b11111111, 0xFF
;
; ============================================
; P O R T S A N D P I N S
; ============================================
;
; port definitions
; Unused port and pins are set to inputs with pull-ups ON
.equ usb_sclk_port_reg= PORTA   ; the usb input clock line is on the adc bus (porta)
.equ usb_sclk_pin_reg= PINA
.equ usb_data_port_reg= PORTC   ; The USB data bus are all outputs with 8 lines availible
.equ usb_data_port_dd= DDRC
.equ usb_data_pin_reg= PINC
;
.equ usb_sclk_pin= 7    ; on the adc bus this pin is the clock input from the USB
; Although all the pins on the data bus are outputs. Because a user can select to use from
; 2-8 of the pins to read data. When configuring, we assume there's only 2 pins, one input
; and the other output which are used to read the configuration (see the setup section).
; After configuration we know how many pins the user is connected to on the data bus and
; all are set to outputs.
.equ usb_in_pin= 7  ; the input pin (to micro) during configuration
.equ usb_out_pin= 6 ; the output pin (from micro) during configuration
;
.equ adc_port_reg= PORTA    ; This is the adc port
.equ adc_port_dd= DDRA
.equ adc_pin_reg= PINA
;
.equ adc_reset_pin= 6; ADC reset pin, 0=reset
.equ adc_chip_select_pin= 5; ADC chip select, 0=select
.equ adc_sclk_pin= 4; serial clock to clock data into/out of adc
.equ adc_data_out_pin= 3; line that outputs bits into the ADC
.equ adc_data_in_pin= 2; line that the ADC chip writes new data which we read
; ADC new data ready signal, 0=new data it goes low only when there's new data on all active channels
.equ adc_data_ready_pin= 1
.equ adc_unused1_pin= 0
;
;
.equ led_port_reg = PORTB    ; This is the port with the led
.equ led_port_dd = DDRB
.equ led_pin_reg = PINB
;
.equ led_pin= 4; A pin connected to an LED which goes on and off when there's data collected
;
;
;
.equ unused1_port_reg= PORTD    ; Unused port
.equ unused1_port_dd= DDRD
.equ unused1_pin_reg= PIND
;
;
; ============================================
; C O N S T A N T S T O C H A N G E
; ============================================
;
;
; ============================================
; F I X + D E R I V E D C O N S T A N T S
; ============================================
;
; during configuration the USB sends two bytes. The lowest byte contains many different settings.
; Each of which are indexed by the pins below. We list for each pin how it relates to the adc 
; configuration.
; adc_range 0 and 1 correspond with pins RNG1 and RNG0 in the channel steup register in the ADC
.equ adc_range0= 0
.equ adc_range1= 1
; at least one of the channels must be active. although both can be active
; the other configuration params are all applied to the active channels identically
.equ adc_chan0_enable= 2    ; if 1, channel zero will be active and send data
.equ adc_chan1_enable= 3    ; if 1, channel one will be active and send data
.equ adc_24bits= 4          ; whether the adc data should be 16 bit or 24 bit wide. 1=24, 0=16.
; data_pin_range0-2 is a 3 bit field indicating how many data pins the usb has connected to the micro.
; possible values are 1-7, where 1 means two bits are availible (the min) and 7 means the full port,
; 8 bits are connedted (the max). In all cases, the pins connected must be connected to the highest 
; pins on the micro bus.
.equ data_pin_range0= 5
.equ data_pin_range1= 6
.equ data_pin_range2= 7
; when the micro is sending data to the USB, every byte is sent twice with the second time each
; bit is a ones complement. However, every few bytes (depending on the number of bit sent per 
; transection) the adc_overflow bit is not complemeted, while all the others are. This helps
; with error detection and synchronization.
.equ adc_overflow= 7
;
; ============================================
; M A C R O
; ============================================
;
; provides 10 nop instructions
.MACRO NOP10
NOP
NOP
NOP
NOP
NOP
NOP
NOP
NOP
NOP
NOP
.ENDMACRO
;
;
;
; left shifts a 16 bit number once to the left. @1 is the register holding the high
; byte. @0 is the register holding the low byte. 2 cycles.
.macro LSL_16
lsl @1
rol @0
.endmacro
;
; right shifts a 16 bit number once to the right. @1 is the register holding the high
; byte. @0 is the register holding the low byte. 2 cycles.
.macro LSR_16
lsr @0
ror @1
.endmacro
;
; @0 is a register where each bit is shifted twice left. 2 cycles.
.macro LSL2
lsl @0
lsl @0
.endmacro
;
; @0 is a register where each bit is shifted twice right. 2 cycles.
.macro LSR2
lsr @0
lsr @0
.endmacro
;
; left shifts a 16 bit number twice to the left. @1 is the register holding the high
; byte. @0 is the register holding the low byte. 4 cycles.
.macro LSL2_16
LSL_16 @0, @1
LSL_16 @0, @1
.endmacro
;
; right shifts a 16 bit number twice to the right. @1 is the register holding the high
; byte. @0 is the register holding the low byte. 4 cycles.
.macro LSR2_16
LSR_16 @0, @1
LSR_16 @0, @1
.endmacro
;
; @0 is a register where each bit is shifted 3 times left. 3 cycles.
.macro LSL3
lsl @0
LSL2 @0
.endmacro
;
; @0 is a register where each bit is shifted 3 times right. 3 cycles.
.macro LSR3
lsr @0
LSR2 @0
.endmacro
;
; left shifts a 16 bit number 3 times to the left. @1 is the register holding the high
; byte. @0 is the register holding the low byte. 6 cycles.
.macro LSL3_16
LSL_16 @0, @1
LSL2_16 @0, @1
.endmacro
;
; right shifts a 16 bit number 3 times to the right. @1 is the register holding the high
; byte. @0 is the register holding the low byte. 6 cycles.
.macro LSR3_16
LSR_16 @0, @1
LSR2_16 @0, @1
.endmacro
;
; @0 is a register where each bit is shifted 4 times left. 4 cycles.
.macro LSL4
LSL2 @0
LSL2 @0
.endmacro
;
; left shifts a 16 bit number 4 times to the left. @1 is the register holding the high
; byte. @0 is the register holding the low byte. 8 cycles.
.macro LSR4_16
LSR2_16 @0, @1
LSR2_16 @0, @1
.endmacro
;
; @0 is a register where each bit is shifted 5 times left. 5 cycles.
.macro LSL5
LSL2 @0
LSL3 @0
.endmacro
;
; @0 is a register where each bit is shifted 6 times left. 6 cycles.
.macro LSL6
LSL3 @0
LSL3 @0
.endmacro
;
; @0 is a register where each bit is shifted 7 times left. 7 cycles.
.macro LSL7
LSL4 @0
LSL3 @0
.endmacro
;
;
;
; Used to read the bit of data from the ADC. It pulls the clock low and high and
; then reads the new bit. @0 is the register that will get the bit read. @1 is the
; bit (0-7) where the bit read is stored. It is assumed that that bit in register
; @0 has been cleared before this. 6 cycles
.MACRO READ_ADC_BIT
out adc_port_reg, adc_sclk_low
nop
nop
out adc_port_reg, adc_sclk_high
sbic adc_pin_reg, adc_data_in_pin
sbr @0, @1
.ENDMACRO
;
; used to write a bit to the ADC chip. We write the data at the output pin and then toggle
; the clock low and high which forces the ADC to read the bit. @0 is the register holding
; the bit to be written. @1 is the bit (0-7) in the register @0 holding the bit to be written.
; 39 cycles.
.MACRO WRITE_ADC_BIT
sbrc @0, @1 ; prepare the data
sbi adc_port_reg, adc_data_out_pin
sbrs @0, @1 ; prepare the data
cbi adc_port_reg, adc_data_out_pin
NOP10
cbi adc_port_reg, adc_sclk_pin  ; clock goes low and high
NOP10
sbi adc_port_reg, adc_sclk_pin
NOP10
.ENDMACRO
;
; similar to WRITE_ADC_BIT, except this writes a whole byte to the ADC. The byte is written
; a bit at a time from MSB to LSB. @0 is the register holding the byte to be written.
; After we're done, the data line is pulled low to ensure the ADC is not reset accidently.
; 314 cycles.
.MACRO WRITE_ADC_BYTE
WRITE_ADC_BIT @0, 7
WRITE_ADC_BIT @0, 6
WRITE_ADC_BIT @0, 5
WRITE_ADC_BIT @0, 4
WRITE_ADC_BIT @0, 3
WRITE_ADC_BIT @0, 2
WRITE_ADC_BIT @0, 1
WRITE_ADC_BIT @0, 0
cbi adc_port_reg, adc_data_out_pin  ; make sure data line is low, clock line is high
.ENDMACRO
;
; When sending data to the usb, we have to wait 
;Max 9 cycles from when it changes from L/H to H/L until this is finished executing. That is if we're
;say waiting for a high and no new ADC data is ready it will take a max of 9 cycles from when the
;clock changes to high until we exit this waiting section. If we come in when it's already in the
;correct state, it'll only take 5 cycles.
.MACRO USB_WAIT_CLK
@1 :
sbic adc_pin_reg, adc_data_ready_pin
RJMP @2
LDI ZL,LOW(@0)
LDI ZH,HIGH(@0)
jmp collect_adc
@0 :
SBIS adc_pin_reg, adc_data_ready_pin
jmp collect_adc
@4 usb_sclk_pin_reg, usb_sclk_pin
RJMP @0
@2 :
@3 usb_sclk_pin_reg, usb_sclk_pin
rjmp @1
.ENDMACRO
;
;
.MACRO NEW_DATA_CHECK   ; 5 cycles if data present
cpse YH, XH
rjmp @0
cpse YL, XL
rjmp @0
ldi ZH, HIGH(@1) ; where we return after collecting
ldi ZL, LOW(@1)
rjmp wait_for_new_adc_data2
@2 :
sbis adc_pin_reg, adc_data_ready_pin
jmp collect_adc
@1 :
sbis usb_sclk_pin_reg, usb_sclk_pin
rjmp @2
@0 :
.ENDMACRO
;
.MACRO NEW_DATA_CHECK_H   ; 5 cycles if data present
cpse YH, XH
rjmp @0
cpse YL, XL
rjmp @0
ldi ZH, HIGH(@1) ; where we return after collecting
ldi ZL, LOW(@1)
jmp wait_for_new_adc_data2
@2 :
sbis adc_pin_reg, adc_data_ready_pin
jmp collect_adc
@1 :
sbic usb_sclk_pin_reg, usb_sclk_pin
rjmp @2
@0 :
.ENDMACRO
;
;
.MACRO USB_WRITE
USB_WAIT_CLK @1, @0, @2, sbic, sbis
out usb_data_port_reg, usb_data
mov usb_data_comp, usb_data
com usb_data_comp
.ENDMACRO
;
.MACRO USB_WRITE2
USB_WAIT_CLK @1, @0, @2, sbic, sbis
out usb_data_port_reg, @3
mov usb_data_comp, @3
com usb_data_comp
.ENDMACRO
;
.MACRO USB_WRITE_COMP
USB_WAIT_CLK @1, @0, @2, sbis, sbic	; wait for line to go high
out usb_data_port_reg, usb_data_comp; send complement of first batch
.ENDMACRO
;

;Used to handshake USB with micro. It waits for a H or L on the USB clock pin
;@0 = rjmp label, @1 = SBIS or SBIC, i.e. wait for H or L. 6 cycles
.MACRO RESTART_USB_PROTOCOL
@2 :
sbic @0, @1
rjmp @2
@3 :
sbis @0, @1
rjmp @3
.ENDMACRO
;
;
.MACRO CONFIGURE_ADC
@0 :
sbic usb_sclk_pin_reg, usb_sclk_pin ; wait for clock to go low
rjmp @0
sbic usb_data_pin_reg, usb_in_pin   ; if bit read is set, update register
sbr @2, 1<<@3
sbrs @2, @3 ; now mirror data back
cbi usb_data_port_reg, usb_out_pin
sbrc @2, @3
sbi usb_data_port_reg, usb_out_pin  ; max 13 cycles until after data is mirrored
@1 :
sbis usb_sclk_pin_reg, usb_sclk_pin ; wait for clock to go low
rjmp @1
.ENDMACRO
;
;
;
; ============================================
; R E G I S T E R D E F I N I T I O N S
; ============================================
;
;only registers >=16 can be loaded with constants or used with CBR. To get data into the first 16 regs you have to copy from other reg.
; The address of one above the uppermost memory location so that we know when we have to circle back
.def ring_ceil_L= R0
.def ring_ceil_H= R1
.def usb_path_L= R2
.def usb_path_H= R3
.def zero_reg= R4
.def adc_sclk_low= R5; Stores the output needed to present at ADC ports; clock low
.def adc_sclk_high= R6; Stores the output needed to present at ADC ports; clock high
;
.def temp = R16; General temp storage
.def temp2= R17
.def adc_conversion_time= R18
.def adc_flags= R19
.def usb_data = R20 ; Stores the data to be sent to USB
.def usb_data2 = R21 ; Stores the data to be sent to USB
.def usb_data3 = R22
.def usb_data_comp = R23; Stores ones complement nibble data to be sent to USB
.def flags_reg= R24 ; holds flags such adc_overflow.
; Stores 1.5 times the number of cycles it took for the USB clock to change. Used to see if clocking rate changed
;.DEF bitTime = R24
;
; ============================================
; S R A M D E F I N I T I O N S
; ============================================
;
; Needs to be divisible by number of bytes in data point set.
; The ring buffer address where the ADC data is saved to. You can store data in 0x0100=0x40A8 inclusive
.EQU ring_floor = 0x0100; First location of the ring buffer where we start saving data
; The value in the address pointer when the buffer has to circle back to the origin
.EQU ring_ceil_2 = 0x40FC
.EQU ring_ceil_3 = 0x40FC
.EQU ring_ceil_4 = 0x40FC
.EQU ring_ceil_5 = 0x40FC
.EQU ring_ceil_6 = 0x40FC
.EQU ring_ceil_7 = 0x40FC
.EQU ring_ceil_8 = 0x40FC
.equ min_buffer_space= 0x10

; ============================================
; R E S E T A N D I N T V E C T O R S
; ============================================
;
;
; ============================================
; I N T E R R U P T S E R V I C E S
; ============================================
;
; [Add all interrupt service routines here]
;
; ============================================
; M A I N P R O G R A M I N I T
; ============================================
;
;
;**************************************************************************************************************
;********************************** This is where we configure everything *************************************
;**************************************************************************************************************
;
;
;*************************************************** Configure the micro *****************************
;After reset start from begining code
.CSEG
.ORG $0000
Main :
ldi temp, (0<<WDRF); turn OFF watchdog reset in case it was left ON
out MCUSR, temp
; Enables WDT changes
ldi temp, (1<<WDCE);
sts WDTCSR, temp
ldi temp, (1<<WDCE) | (0<<WDE); Disable watchdog timer
sts WDTCSR, temp
; Reduces power by shutting OFF un-needed components
ldi temp, 0b11111011; Cut power to unused components, don't turn off SPI, we need it to program micro
sts PRR0, temp
ldi temp, 0b00000001
sts PRR1, temp
ldi temp, 0b10000000; Turn off the comparator
out ACSR, temp

;*************************************************** Load registers **********************************
; Load constant values into registers
clr zero_reg
clr flags_reg
; prepre the register data pointer for storing the ADC data. See explanation for X,Y at collect_adc
ldi YH, HIGH(ring_floor)
ldi YL, LOW(ring_floor)
ldi XH, HIGH(ring_floor)
ldi XL, LOW(ring_floor)
ldi temp, (0<<usb_sclk_pin)|(1<<adc_unused1_pin)|(0<<adc_chip_select_pin)|(1<<adc_reset_pin)|(0<<adc_data_ready_pin)|(0<<adc_data_in_pin)|(0<<adc_data_out_pin)|(0<<adc_sclk_pin)
mov adc_sclk_low, temp
ldi temp, (0<<usb_sclk_pin)|(1<<adc_unused1_pin)|(0<<adc_chip_select_pin)|(1<<adc_reset_pin)|(0<<adc_data_ready_pin)|(0<<adc_data_in_pin)|(0<<adc_data_out_pin)|(1<<adc_sclk_pin)
mov adc_sclk_high, temp


;*************************************************** Set I/O ports ************************************
; Initialize the ports I/O
ldi temp, 0x00  ; clear unused ports A,C
out unused1_port_dd, temp  ; set to input
out usb_data_port_dd, temp  ; initially, all USB bus pins are inputs with pull up enabled
ldi temp, 1<<led_pin
out led_port_dd, temp  ; set to input, except led pin
nop
nop
ldi temp, 0xFF  ; enable all pull-ups
out unused1_port_reg, temp
out usb_data_port_reg, temp
ldi temp, ~(1<<led_pin)  ; enable all pull-ups except for led, which is set low - to turn ON
out led_port_reg, temp
; Since initial setting of port was input with pullup diasabled - 0b00 and we need to change some to
; output high - 0n11, we need to go through the intermidiate step of input with pullup enabled - 0b01
; usb_sclk pull up is enabled until the device is fully activated.
ldi temp, (1<<usb_sclk_pin)|(1<<adc_unused1_pin)|(0<<adc_chip_select_pin)|(1<<adc_reset_pin)|(0<<adc_data_ready_pin)|(0<<adc_data_in_pin)|(0<<adc_data_out_pin)|(1<<adc_sclk_pin)
out adc_port_reg, temp
nop
nop
ldi temp, (0<<usb_sclk_pin)|(0<<adc_unused1_pin)|(1<<adc_chip_select_pin)|(1<<adc_reset_pin)|(0<<adc_data_ready_pin)|(0<<adc_data_in_pin)|(1<<adc_data_out_pin)|(1<<adc_sclk_pin)
out adc_port_dd, temp
nop
nop
ldi temp, (1<<usb_sclk_pin)|(1<<adc_unused1_pin)|(0<<adc_chip_select_pin)|(1<<adc_reset_pin)|(0<<adc_data_ready_pin)|(0<<adc_data_in_pin)|(0<<adc_data_out_pin)|(1<<adc_sclk_pin)
out adc_port_reg, temp
nop
nop

;*************************************************** Power OFF the ADC ********************************
; reset the ADC
cbi adc_port_reg, adc_reset_pin
NOP10
NOP10
NOP10
sbi adc_port_reg, adc_reset_pin
NOP10
NOP10
NOP10
ldi temp, 0x38  ; write comm register that next will be write to mode
WRITE_ADC_BYTE temp
ldi temp, 0b01110000    ; power down ADC
WRITE_ADC_BYTE temp
sbi adc_port_reg, adc_chip_select_pin ; disable comm with ADC for now
; now reset is high, cs is high, clk is high, data line is low
;*************************************************** Micro - USB handshaking ***************************
; Used to sync to USB communication, clock waits for 40 cycles, of low followed by high. 
; when we come out the clock just went high.
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_0, restart_1
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_2, restart_3
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_4, restart_5
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_6, restart_7
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_8, restart_9
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_10, restart_11
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_12, restart_13
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_14, restart_15
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_16, restart_17
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_18, restart_19
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_20, restart_21
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_22, restart_23
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_24, restart_25
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_26, restart_27
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_28, restart_29
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_30, restart_31
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_32, restart_33
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_34, restart_35
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_36, restart_37
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_38, restart_39
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_40, restart_41
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_42, restart_43
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_44, restart_45
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_46, restart_47
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_48, restart_49
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_50, restart_51
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_52, restart_53
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_54, restart_55
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_56, restart_57
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_58, restart_59
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_60, restart_61
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_62, restart_63
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_64, restart_65
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_66, restart_67
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_68, restart_69
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_70, restart_71
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_72, restart_73
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_74, restart_75
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_76, restart_77
RESTART_USB_PROTOCOL usb_sclk_pin_reg, usb_sclk_pin, restart_78, restart_79
; enable watchdog timer so that if the USB goes away, it has to start again
ldi temp, (0<<WDRF); turn OFF watchdog reset in case it was left ON
out MCUSR, temp
ldi temp, (1<<WDE) | (1<<WDCE)
sts WDTCSR, temp
ldi temp, (1<<WDE) | (1<<WDP0) | (1<<WDP1) | (1<<WDP2)   ; enable watchdog timer with 2 sec TO
sts WDTCSR, temp
; then there are 10 cycles of the data input pin going low and high
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_80, restart_81
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_82, restart_83
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_84, restart_85
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_86, restart_87
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_88, restart_89
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_90, restart_91
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_92, restart_93
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_94, restart_95
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_96, restart_97
RESTART_USB_PROTOCOL usb_data_pin_reg, usb_in_pin, restart_98, restart_99

; now that there's a USB communicating with us, we start the configuration sequence.
; at this point, on the usb the pin connected to usb_out_pin should be configured as input
; we'll configure usb_out_pin as an output pin
ldi temp, 1<<usb_out_pin
out usb_data_port_dd, temp; all other pins are still pull-up enabled.
cbi usb_data_port_reg, usb_out_pin
;*************************************************** Get ADC config params *****************************
; now read the data into the config registers
; each new bits is sent by usb when clock goes low and stays the same when
; clock goes high. the micro reads the data when usb clock (usb_sclk_pin) goes low
; at pin usb_in_pin and mirrors the bit before usb clock goes high at 
; usb_out_pin.
clr adc_conversion_time; clock has been high for max 15 cycles after this.
CONFIGURE_ADC configure_1, configure_2, adc_conversion_time, 7
CONFIGURE_ADC configure_3, configure_4, adc_conversion_time, 6
CONFIGURE_ADC configure_5, configure_6, adc_conversion_time, 5
CONFIGURE_ADC configure_7, configure_8, adc_conversion_time, 4
CONFIGURE_ADC configure_9, configure_10, adc_conversion_time, 3
CONFIGURE_ADC configure_11, configure_12, adc_conversion_time, 2
CONFIGURE_ADC configure_13, configure_14, adc_conversion_time, 1
CONFIGURE_ADC configure_15, configure_16, adc_conversion_time, 0

clr adc_flags
CONFIGURE_ADC configure_17, configure_18, adc_flags, 7
CONFIGURE_ADC configure_19, configure_20, adc_flags, 6
CONFIGURE_ADC configure_21, configure_22, adc_flags, 5
CONFIGURE_ADC configure_23, configure_24, adc_flags, 4
CONFIGURE_ADC configure_25, configure_26, adc_flags, 3
CONFIGURE_ADC configure_27, configure_28, adc_flags, 2
CONFIGURE_ADC configure_29, configure_30, adc_flags, 1
CONFIGURE_ADC configure_31, configure_32, adc_flags, 0

; now wait for a clock low and high so that USB can configure its pins as input
configure_33 :
sbic usb_sclk_pin_reg, usb_sclk_pin ; wait for clock to go low
rjmp configure_33
configure_34 :
sbis usb_sclk_pin_reg, usb_sclk_pin ; wait for clock to go low
rjmp configure_34
; now that we're fully active, disable the clock pull up
cbi adc_port_reg, usb_sclk_pin
ldi temp, 0xFF ; set all usb data pins to outputs
out usb_data_port_dd, temp
nop
nop
out usb_data_port_reg, temp; and set them all high
wdr

;************************************** Configure the USB code path ****************************
; there are multiple paths we can take to sending data to the USB. i.e. which of the 8 pins
; are availible. We support from 2 - 8 pins.
mov temp2, adc_flags    ; find which path to use
andi temp2, (1<<data_pin_range0) | (1<<data_pin_range1) | (1<<data_pin_range2)
cpi temp2, (1<<data_pin_range0)                                                  ; 1 - code path 2
breq config_code_path_2
cpi temp2, (1<<data_pin_range1)                                                  ; 2 - code path 3
breq config_code_path_3
cpi temp2, (1<<data_pin_range0) | (1<<data_pin_range1)                           ; 3 - code path 4
breq config_code_path_4
cpi temp2, (1<<data_pin_range2)                                                  ; 4 - code path 5
breq config_code_path_5
cpi temp2, (1<<data_pin_range0) | (1<<data_pin_range2)                           ; 5 - code path 6
breq config_code_path_6
cpi temp2, (1<<data_pin_range1) | (1<<data_pin_range2)                           ; 6 - code path 7
breq config_code_path_7
cpi temp2, (1<<data_pin_range0) | (1<<data_pin_range1) | (1<<data_pin_range2)    ; 7 - code path 8
breq config_code_path_8
; didn't find anything, use default - 2
config_code_path_2 :
ldi temp, LOW(usb_send_2bits)
mov usb_path_L, temp
ldi temp, HIGH(usb_send_2bits)
mov usb_path_H, temp
ldi temp, LOW(ring_ceil_2)
mov ring_ceil_L, temp
ldi temp, HIGH(ring_ceil_2)
mov ring_ceil_H, temp
rjmp end_config_code_path
config_code_path_3 :
ldi temp, LOW(usb_send_3bits)
mov usb_path_L, temp
ldi temp, HIGH(usb_send_3bits)
mov usb_path_H, temp
ldi temp, LOW(ring_ceil_3)
mov ring_ceil_L, temp
ldi temp, HIGH(ring_ceil_3)
mov ring_ceil_H, temp
rjmp end_config_code_path
config_code_path_4 :
ldi temp, LOW(usb_send_4bits)
mov usb_path_L, temp
ldi temp, HIGH(usb_send_4bits)
mov usb_path_H, temp
ldi temp, LOW(ring_ceil_4)
mov ring_ceil_L, temp
ldi temp, HIGH(ring_ceil_4)
mov ring_ceil_H, temp
rjmp end_config_code_path
config_code_path_5 :
ldi temp, LOW(usb_send_5bits)
mov usb_path_L, temp
ldi temp, HIGH(usb_send_5bits)
mov usb_path_H, temp
ldi temp, LOW(ring_ceil_5)
mov ring_ceil_L, temp
ldi temp, HIGH(ring_ceil_5)
mov ring_ceil_H, temp
rjmp end_config_code_path
config_code_path_6 :
ldi temp, LOW(usb_send_6bits)
mov usb_path_L, temp
ldi temp, HIGH(usb_send_6bits)
mov usb_path_H, temp
ldi temp, LOW(ring_ceil_6)
mov ring_ceil_L, temp
ldi temp, HIGH(ring_ceil_6)
mov ring_ceil_H, temp
rjmp end_config_code_path
config_code_path_7 :
ldi temp, LOW(usb_send_7bits)
mov usb_path_L, temp
ldi temp, HIGH(usb_send_7bits)
mov usb_path_H, temp
ldi temp, LOW(ring_ceil_7)
mov ring_ceil_L, temp
ldi temp, HIGH(ring_ceil_7)
mov ring_ceil_H, temp
rjmp end_config_code_path
config_code_path_8 :
ldi temp, LOW(usb_send_8bits)
mov usb_path_L, temp
ldi temp, HIGH(usb_send_8bits)
mov usb_path_H, temp
ldi temp, LOW(ring_ceil_8)
mov ring_ceil_L, temp
ldi temp, HIGH(ring_ceil_8)
mov ring_ceil_H, temp
end_config_code_path :
;********************************************** reset adc **************************************
; now we will configure the ADC registers
cbi adc_port_reg, adc_chip_select_pin   ; enable comm with ADC
cbi adc_port_reg, adc_reset_pin         ; reset the ADC
NOP10
NOP10
NOP10
sbi adc_port_reg, adc_reset_pin
NOP10
NOP10
NOP10
; now reset is high, cs is low, clk is high, data line is low and we're ready to 
; start configuring the ADC
;********************************************** I/O port register ******************************
ldi temp, 0x01
ldi temp2, 0b00110000   ; only go low when there's data on all channels
WRITE_ADC_BYTE temp
WRITE_ADC_BYTE temp2
;********************************************** channel setup register *************************
clr temp2
sbr temp2, 1<<3             ; enable the channel
sbrc adc_flags, adc_range0  ; now set the channel input range based on configuration
sbr temp2, 1<<0
sbrc adc_flags, adc_range1
sbr temp2, 1<<1
sbrs adc_flags, adc_chan0_enable    ; enable channel zero
rjmp chan0_setup_enable_end
ldi temp, 0x28          ; write to comm register that next is setup
WRITE_ADC_BYTE temp
WRITE_ADC_BYTE temp2    ; write setup data
chan0_setup_enable_end :
sbrs adc_flags, adc_chan1_enable    ; enable channel one
rjmp chan1_setup_enable_end
ldi temp, 0x2A
WRITE_ADC_BYTE temp
WRITE_ADC_BYTE temp2
chan1_setup_enable_end :
NOP10
NOP10
;********************************************** channel conversion times register **************
sbrs adc_flags, adc_chan0_enable    ; enable channel zero
rjmp chan0_conversion_enable_end
ldi temp, 0x30                      ; write to comm register that next is conversion times
WRITE_ADC_BYTE temp
WRITE_ADC_BYTE adc_conversion_time  ; 1kHz should be 0b10101101
chan0_conversion_enable_end :
sbrs adc_flags, adc_chan1_enable    ; enable channel one
rjmp chan1_conversion_enable_end
ldi temp, 0x32
WRITE_ADC_BYTE temp
WRITE_ADC_BYTE adc_conversion_time
chan1_conversion_enable_end :
NOP10
NOP10
;********************************************** channel mode register **************************
sbrs adc_flags, adc_chan0_enable    ; is channel 0 enabled?
rjmp chan1_mode_write
ldi temp, 0x38                      ; then we start converting with channel 0
rjmp mode_reg_write
chan1_mode_write :                  ; otherwise, conversion starts at channel 1
ldi temp, 0x3A
mode_reg_write :
ldi temp2, 0b00101101               ; set it into continuos conversion mode
sbrc adc_flags, adc_24bits          ; if data point is 24 bits wide, update register
sbr temp2, 1<<1
WRITE_ADC_BYTE temp
WRITE_ADC_BYTE temp2
NOP10
NOP10
;********************************************** start converting *******************************
ldi temp, 0x48          ; this starts the conversions
WRITE_ADC_BYTE temp
WDR; Reset watchdog timer
RJMP wait_for_new_adc_data  ; go wait for new data
;==============================================================================================================
;************************************************* End configuration ******************************************
;==============================================================================================================













;**************************************************************************************************************
;********************************** This is where we collect new ADC data *************************************
;**************************************************************************************************************
; If there is noise try toggling CS on ADC when not reading data
; Bits and bytes are sent by ADC from MSB --> LSB, so when reading, we first read the 
; MSBit of the MSByte. In the buffer, however, the MSByte is stored first (lowest)
; followed by second MSbytes etc.
;
; Either channel 0, 1 or both can be active. In addition, both channels can be simultanously
; either 16 bits or 24 bits wide. In all cases, the status byte is also read. So a single data
; point can be either 3 or 4 bytes. A data point set is the number of bytes for a data point
; from channels 0 _and_ 1 (if active) e.g. 3, 4, 6, or 8 bytes.
;
; The data read, is saved to SRAM. In SRAM we have a circular buffer. The start and end locations
; are defined in the .equ definitions and depend on the data point set value.
; The total length of the SRAM circular data buffer must be byte aligned to a data point set. This ensures
; we only have to check if we reached the end of the buffer _after_ collecting the full data point set.
; The max total # of cycles the following takes is (# channels)*((# of bytes)*(6*8+3)+5)+31. 
; There's an additional 20 cycle penatly on average each time we collect ADC data. For example:
; (1)*((4)*(6*8+3)+5)+31= 240 cycles
; (1)*((3)*(6*8+3)+5)+31= 189 cycles
; (2)*((4)*(6*8+3)+5)+31= 449 cycles
; (2)*((3)*(6*8+3)+5)+31= 347 cycles
collect_adc :
; we check to see that there is enough room for twice the ADC data, 2*(3,4,6 or 8) bytes (depending if one 
; or both channels are active, and if 16/24 bits). X holds the position where the next adc data point 
; will be saved to. Y hold the position of the next data point to be sent to the USB. If X==Y then the 
; buffer is empty.
mov temp, YL
mov temp2, YH
cp XL, YL
cpc XH, YH
brlo adc_find_empty_space; which is lower in the circular buffer, adc or usb (x, or y respectivly)
breq adc_chan_0_start   ; if they are equal there's enough room
; here, adc (X) is larger or equal to usb. We need to find if there is enough room after the ADC, circling back
; to the start until Y for the min bytes. We'll find the difference between start of buffer and Y, and 
; add that to the end of the buffer so we can then find the direct difference between adc to usb (Y-X)
subi temp, LOW(ring_floor)
sbci temp2, HIGH(ring_floor)
add temp, ring_ceil_L
adc temp2, ring_ceil_H
; now we just subtract adc from usb, to find if there's room for a data point between adc and usb
adc_find_empty_space :
sub temp, XL; distance between adc-usb
sbc temp2, XH
cpi temp, min_buffer_space; now compare the min bytes to distance between usb and adc.
cpc temp2, zero_reg
brsh adc_chan_0_start; the distance was larger or equal then the required min, so get new data
; not enough room.
sbr flags_reg, 1<<adc_overflow; set flag
READ_ADC_BIT temp, 0x80; do a single read so ready line goes low
ijmp    ; go back to where we were

;************************************************** channel 0 *************************************************
adc_chan_0_start :
;sbrs adc_flags, adc_chan0_enable; if channel 0 is disabled, skip to channel 1 collection
;rjmp adc_data_point_0_end

READ_ADC_BIT temp, 0x80	; we don't save the highest bit because that's where the overflow flag goes in the status byte
clr temp; Highest byte (status byte)
sbrc flags_reg, adc_overflow
sbr temp, 1<<adc_overflow
READ_ADC_BIT temp, 0x40
READ_ADC_BIT temp, 0x20
READ_ADC_BIT temp, 0x10
READ_ADC_BIT temp, 0x08
READ_ADC_BIT temp, 0x04
READ_ADC_BIT temp, 0x02
READ_ADC_BIT temp, 0x01
st X+, temp ;Store data in SRAM

clr temp
READ_ADC_BIT temp, 0x80	; Byte 2 (or 1)
READ_ADC_BIT temp, 0x40
READ_ADC_BIT temp, 0x20
READ_ADC_BIT temp, 0x10
READ_ADC_BIT temp, 0x08
READ_ADC_BIT temp, 0x04
READ_ADC_BIT temp, 0x02
READ_ADC_BIT temp, 0x01
st X+, temp

clr temp
READ_ADC_BIT temp, 0x80	; Byte 1 (or 0)
READ_ADC_BIT temp, 0x40
READ_ADC_BIT temp, 0x20
READ_ADC_BIT temp, 0x10
READ_ADC_BIT temp, 0x08
READ_ADC_BIT temp, 0x04
READ_ADC_BIT temp, 0x02
READ_ADC_BIT temp, 0x01
st X+, temp
sbrs adc_flags, adc_24bits; if only 16 bit, then skip next byte
rjmp adc_data_point_0_end

clr temp
READ_ADC_BIT temp, 0x80	; Byte 0 (skipped if data is 16 bit wide)
READ_ADC_BIT temp, 0x40
READ_ADC_BIT temp, 0x20
READ_ADC_BIT temp, 0x10
READ_ADC_BIT temp, 0x08
READ_ADC_BIT temp, 0x04
READ_ADC_BIT temp, 0x02
READ_ADC_BIT temp, 0x01
st X+, temp
adc_data_point_0_end :

;************************************************** channel 1 *************************************************
;sbrs adc_flags, adc_chan1_enable; if channel 1 is disabled, skip to end of collection
rjmp adc_data_point_1_end

READ_ADC_BIT temp, 0x80	; we don't save the highest bit because that's where the overflow flag goes in the status byte
clr temp; Highest byte (status byte)
sbrc flags_reg, adc_overflow
sbr temp, 1<<adc_overflow
READ_ADC_BIT temp, 0x40
READ_ADC_BIT temp, 0x20
READ_ADC_BIT temp, 0x10
READ_ADC_BIT temp, 0x08
READ_ADC_BIT temp, 0x04
READ_ADC_BIT temp, 0x02
READ_ADC_BIT temp, 0x01
st X+, temp

clr temp
READ_ADC_BIT temp, 0x80
READ_ADC_BIT temp, 0x40
READ_ADC_BIT temp, 0x20
READ_ADC_BIT temp, 0x10
READ_ADC_BIT temp, 0x08
READ_ADC_BIT temp, 0x04
READ_ADC_BIT temp, 0x02
READ_ADC_BIT temp, 0x01
st X+, temp

clr temp
READ_ADC_BIT temp, 0x80
READ_ADC_BIT temp, 0x40
READ_ADC_BIT temp, 0x20
READ_ADC_BIT temp, 0x10
READ_ADC_BIT temp, 0x08
READ_ADC_BIT temp, 0x04
READ_ADC_BIT temp, 0x02
READ_ADC_BIT temp, 0x01
st X+, temp
sbrs adc_flags, adc_24bits; if only 16 bit, then skip next byte
rjmp adc_data_point_1_end

clr temp
READ_ADC_BIT temp, 0x80
READ_ADC_BIT temp, 0x40
READ_ADC_BIT temp, 0x20
READ_ADC_BIT temp, 0x10
READ_ADC_BIT temp, 0x08
READ_ADC_BIT temp, 0x04
READ_ADC_BIT temp, 0x02
READ_ADC_BIT temp, 0x01
st X+, temp
adc_data_point_1_end :

cbr flags_reg, 1<<adc_overflow; clear flag
; now we need to decide if we reached end of buffer and pointer needs to be moved to start
cpse XH, ring_ceil_H
rjmp adc_end
cpse XL, ring_ceil_L
rjmp adc_end
ldi XH, HIGH(ring_floor)
ldi XL, LOW(ring_floor)
adc_end:
ijmp
;==============================================================================================================
;******************************************** End collect new ADC data ****************************************
;==============================================================================================================











;**************************************************************************************************************
;******************************* This is where we wait for new ADC data to appear *****************************
;**************************************************************************************************************
wait_for_new_adc_data :
; where we return after collecting (only if no previous data is in buffer), otherwise we go right back to usb
ldi ZH, HIGH(after_collection_wait)
ldi ZL, LOW(after_collection_wait)
wait_for_new_adc_data2 :
SBIS adc_pin_reg, adc_data_ready_pin    ; high means no new data yet
RJMP collect_adc                        ; get the data
RJMP wait_for_new_adc_data2             ; try again

; we return here after collection to make sure we enter the correct USB code path on a high clock
; note, we only come here if there was no data in buffer before, otherwise we go directly back to usb
after_collection_wait :
mov ZL, usb_path_L  ; the USB code path we take to send the data
mov ZH, usb_path_H
wait_for_high_clock :   ; wait for high clock to return. 
sbis usb_sclk_pin_reg, usb_sclk_pin
rjmp wait_for_high_clock
ijmp
;==============================================================================================================
;************************************************* End waiting ************************************************
;==============================================================================================================











;**************************************************************************************************************
;************************************** From here we send USB data ********************************************
;**************************************************************************************************************
; There's 7 paths for sending the data to the USB bus depending on the number of pins on the USB bus
; availible to read data. The minimum is 2 data pins, while the max is 8.







;**********************************************************************************************************
;*****************************************                          ***************************************
;***************************************    2 bits per transection    *************************************
;*****************************************                          ***************************************
;**********************************************************************************************************
; At this point there's a whole data point data to be sent (3, or 4 bytes depending if adc is 16/24 bit 
; wide). A transaction with uncomplemented bit 7 is sent every 3 or 4 bytes, or 12, or 16 transections.
; Since the buffer is 3 and 4 byte aligned, we don't have to check until end if we need to return to origin.
;**************************************************** Byte 3 (2) ******************************************
usb_send_2bits :
LD usb_data, Y+; read next byte
USB_WRITE usb_L_2_3_12, usb_2_1, usb_2_2;******** Byte 3 bits 6-7 *****************************************
cbr usb_data_comp,1<<adc_overflow ; for the first byte, the overflow bit is not complemented so set it back
sbrc usb_data, adc_overflow
sbr usb_data_comp, 1<<adc_overflow
LSL2 usb_data	; prepare for next send, we're sending 2 bits at a time
USB_WRITE_COMP usb_H_2_3_12, usb_2_3, usb_2_4
USB_WRITE usb_L_2_3_34, usb_2_5, usb_2_6;******** Byte 3 bits 4-5 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_3_34, usb_2_7, usb_2_8
USB_WRITE usb_L_2_3_56, usb_2_9, usb_2_10;******* Byte 3 bits 2-3 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_3_56, usb_2_11, usb_2_12
USB_WRITE usb_L_2_3_78, usb_2_13, usb_2_14;****** Byte 3 bits 0-1 *****************************************
USB_WRITE_COMP usb_H_2_3_78, usb_2_15, usb_2_16


;**************************************************** Byte 2 (1) ******************************************
wdr
LD usb_data, Y+; read next byte
USB_WRITE usb_L_2_2_12, usb_2_17, usb_2_18;****** Byte 2 bits 6-7 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_2_12, usb_2_19, usb_2_20
USB_WRITE usb_L_2_2_34, usb_2_21, usb_2_22;****** Byte 2 bits 4-5 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_2_34, usb_2_23, usb_2_24
USB_WRITE usb_L_2_2_56, usb_2_25, usb_2_26;****** Byte 2 bits 2-3 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_2_56, usb_2_27, usb_2_28
USB_WRITE usb_L_2_2_78, usb_2_29, usb_2_30;****** Byte 2 bits 0-1 *****************************************
USB_WRITE_COMP usb_H_2_2_78, usb_2_31, usb_2_32


;**************************************************** Byte 1 (0) ******************************************
LD usb_data, Y+; read next byte
USB_WRITE usb_L_2_1_12, usb_2_33, usb_2_34;****** Byte 1 bits 6-7 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_1_12, usb_2_35, usb_2_36
USB_WRITE usb_L_2_1_34, usb_2_37, usb_2_38;****** Byte 1 bits 4-5 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_1_34, usb_2_39, usb_2_40
USB_WRITE usb_L_2_1_56, usb_2_41, usb_2_42;****** Byte 1 bits 2-3 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_1_56, usb_2_43, usb_2_44
USB_WRITE usb_L_2_1_78, usb_2_45, usb_2_46;****** Byte 1 bits 0-1 *****************************************
USB_WRITE_COMP usb_H_2_1_78, usb_2_47, usb_2_48

sbrs adc_flags, adc_24bits	; if data is 16 bits wide, finish here, otherwise send 4th byte
rjmp usb_end_2bits

;**************************************************** Byte 0 **********************************************
LD usb_data, Y+; read next byte
USB_WRITE usb_L_2_0_12, usb_2_49, usb_2_50;****** Byte 0 bits 6-7 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_0_12, usb_2_51, usb_2_52
USB_WRITE usb_L_2_0_34, usb_2_53, usb_2_54;****** Byte 0 bits 4-5 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_0_34, usb_2_55, usb_2_56
USB_WRITE usb_L_2_0_56, usb_2_57, usb_2_58;****** Byte 0 bits 2-3 *****************************************
LSL2 usb_data
USB_WRITE_COMP usb_H_2_0_56, usb_2_59, usb_2_60
USB_WRITE usb_L_2_0_78, usb_2_61, usb_2_62;****** Byte 0 bits 0-1 *****************************************
USB_WRITE_COMP usb_H_2_0_78, usb_2_63, usb_2_64

usb_end_2bits : ; now check whether we need to circle pointer back to start
cpse YH, ring_ceil_H
rjmp usb_again_2bits
cpse YL, ring_ceil_L
rjmp usb_again_2bits
ldi YH, HIGH(ring_floor)
ldi YL, LOW(ring_floor)

usb_again_2bits :   ; If there's more data to send, send immediatly.
cpse YH, XH
rjmp usb_send_2bits
cpse YL, XL
rjmp usb_send_2bits; clock is low again for 4 cycles max after this jump
rjmp wait_for_new_adc_data
;==============================================================================================================
;************************************************* End 2 bits *************************************************
;==============================================================================================================







;**********************************************************************************************************
;*****************************************                          ***************************************
;***************************************    3 bits per transection    *************************************
;*****************************************                          ***************************************
;**********************************************************************************************************
; At this point there's at least one byte to be sent. At each step, when we load a new byte we have to make
; sure there is data in buffer. We send 3 bytes, no matter the number of bytes per data point. So a new
; transaction with uncomplemented bit 7 is sent every 3 bytes, or 8 transections (3 bytes). We work on
; the 0-23 bits in the 3 bytes. Since the buffer is 3 byte aligned, we don't have to check until end
; if we need to return to origin.
usb_send_3bits :;************************************* Bits 21-23 *****************************************
LD usb_data, Y+; read next byte
USB_WRITE usb_L_3_21_23, usb_3_1, usb_3_2
; clock has been low 14 cycles max after out (from after_collection_wait)
cbr usb_data_comp,1<<adc_overflow ; for the first byte, the overflow bit is not complemented so set it back
sbrc usb_data, adc_overflow
sbr usb_data_comp, 1<<adc_overflow
USB_WRITE_COMP usb_H_3_21_23, usb_3_3, usb_3_4
LSL3 usb_data
NEW_DATA_CHECK usb_3_5, usb_3_35, usb_3_check1; make sure there more bytes to send
USB_WRITE usb_L_3_18_20, usb_3_6, usb_3_7;************* Bits 18-20 *****************************************
LSL3 usb_data               ; bits 16-17 are now in bits 6-7, we need to refil bits 0-5 with bits 10-15
LD usb_data2, Y+            ; read next byte
mov usb_data3, usb_data2
LSR2 usb_data3              ; align MSBits into 0-5 position, discarding bits 0-1 (8-9)
or usb_data, usb_data3      ; and add bits 10-15 to bits 0-5, so usb_data holds now bits 10-17
USB_WRITE_COMP usb_H_3_18_20, usb_3_8, usb_3_9
andi usb_data2, 0x03        ; keep only lowset two bits (8-9) that were removed above
wdr
USB_WRITE usb_L_3_15_17, usb_3_10, usb_3_11;************* Bits 15-17 ***************************************
LSL2 usb_data   ; add the lowest two bits (8-9) that were shifted out above back
or usb_data, usb_data2
lsl usb_data    ; usb_data now holds bits 8-14, and one zero bit
USB_WRITE_COMP usb_H_3_15_17, usb_3_12, usb_3_13
USB_WRITE usb_L_3_12_14, usb_3_14, usb_3_15;************* Bits 12-14 ***************************************
LSL3 usb_data   ; usb_data now holds bits 8-11, and 4 zero bits
USB_WRITE_COMP usb_H_3_12_14, usb_3_16, usb_3_17
NEW_DATA_CHECK usb_3_18, usb_3_36, usb_3_check2
USB_WRITE usb_L_3_9_11, usb_3_19, usb_3_20;************* Bits 9-11 *****************************************
LSL3 usb_data   ; usb_data now holds bit 8, and 7 zero bits
LD usb_data2, Y+    ; next byte
mov usb_data3, usb_data2
lsr usb_data3               ; align MSBits into 0-6 position, discarding bit 0 (0)
or usb_data, usb_data3      ; and add bits 1-7 to bits 0-6, so usb_data holds now bits 1-8
USB_WRITE_COMP usb_H_3_9_11, usb_3_21, usb_3_22
andi usb_data2, 0x01        ; keep only lowset bit (0) that was removed above
USB_WRITE usb_L_3_6_8, usb_3_23, usb_3_24;************** Bits 6-8 ******************************************
lsl usb_data   ; add the lowest bit that was shifted out above back
or usb_data, usb_data2
LSL2 usb_data   ; usb_data now holds bits 0-5, and 2 zero bits
USB_WRITE_COMP usb_H_3_6_8, usb_3_25, usb_3_26
USB_WRITE usb_L_3_3_5, usb_3_27, usb_3_28;************** Bits 3-5 ******************************************
LSL3 usb_data
USB_WRITE_COMP usb_H_3_3_5, usb_3_29, usb_3_30
USB_WRITE usb_L_3_0_2, usb_3_31, usb_3_32;************** Bits 0-2 ******************************************
USB_WRITE_COMP usb_H_3_0_2, usb_3_33, usb_3_34

usb_end_3bits : ; now check whether we need to circle pointer back to start
cpse YH, ring_ceil_H
rjmp usb_again_3bits
cpse YL, ring_ceil_L
rjmp usb_again_3bits
ldi YH, HIGH(ring_floor)
ldi YL, LOW(ring_floor)

usb_again_3bits :   ; If there's more data to send, send immediatly.
cpse YH, XH
rjmp usb_send_3bits
cpse YL, XL
rjmp usb_send_3bits; clock is low again for 4 cycles max after this jump
rjmp wait_for_new_adc_data
;==============================================================================================================
;************************************************* End 3 bits *************************************************
;==============================================================================================================







;**********************************************************************************************************
;*****************************************                          ***************************************
;***************************************    4 bits per transection    *************************************
;*****************************************                          ***************************************
;**********************************************************************************************************
; At this point there's a whole data point data to be sent (3, or 4 bytes depending if adc is 16/24 bit 
; wide). A transaction with uncomplemented bit 7 is sent every 3 or 4 bytes, or 6, or 8 transections.
; Since the buffer is 3 and 4 byte aligned, we don't have to check until end if we need to return to origin.
;**************************************************** Byte 3 (2) ******************************************
usb_send_4bits :
LD usb_data, Y+; read next byte
USB_WRITE usb_L_4_3_14, usb_4_1, usb_4_2;******** Byte 3 bits 4-7 *****************************************
cbr usb_data_comp,1<<adc_overflow ; for the first byte, the overflow bit is not complemented so set it back
sbrc usb_data, adc_overflow
sbr usb_data_comp, 1<<adc_overflow
LSL4 usb_data	; prepare for next send, we're sending 4 bits at a time
USB_WRITE_COMP usb_H_4_3_14, usb_4_3, usb_4_4
USB_WRITE usb_L_4_3_58, usb_4_5, usb_4_6;********* Byte 3 bits 0-3 *****************************************
USB_WRITE_COMP usb_H_4_3_58, usb_4_7, usb_4_8
;**************************************************** Byte 2 (1) *******************************************
wdr
LD usb_data, Y+; read next byte
USB_WRITE usb_L_4_2_14, usb_4_9, usb_4_10;******* Byte 2 bits 4-7 ******************************************
LSL4 usb_data
USB_WRITE_COMP usb_H_4_2_14, usb_4_11, usb_4_12
USB_WRITE usb_L_4_2_58, usb_4_13, usb_4_14;******* Byte 2 bits 0-3 *****************************************
USB_WRITE_COMP usb_H_4_2_58, usb_4_15, usb_4_16


;**************************************************** Byte 1 (0) *******************************************
LD usb_data, Y+; read next byte
USB_WRITE usb_L_4_1_14, usb_4_17, usb_4_18;******* Byte 1 bits 4-7 *****************************************
LSL4 usb_data
USB_WRITE_COMP usb_H_4_1_14, usb_4_19, usb_4_20
USB_WRITE usb_L_4_1_58, usb_4_21, usb_4_22;******* Byte 1 bits 0-3 *****************************************
USB_WRITE_COMP usb_H_4_1_58, usb_4_23, usb_4_24

sbrs adc_flags, adc_24bits	; if data is 16 bits wide, finish here, otherwise send 4th byte
rjmp usb_end_4bits

;**************************************************** Byte 0 ***********************************************
LD usb_data, Y+; read next byte
USB_WRITE uusb_L_4_0_14, sb_4_25, usb_4_26;******* Byte 0 bits 4-7 *****************************************
LSL4 usb_data
USB_WRITE_COMP usb_H_4_0_14, usb_4_27, usb_4_28
USB_WRITE usb_L_4_0_58, usb_4_29, usb_4_30;******* Byte 0 bits 0-3 *****************************************
USB_WRITE_COMP usb_H_4_0_58, usb_4_31, usb_4_32

usb_end_4bits : ; now check whether we need to circle pointer back to start
cpse YH, ring_ceil_H
rjmp usb_again_4bits
cpse YL, ring_ceil_L
rjmp usb_again_4bits
ldi YH, HIGH(ring_floor)
ldi YL, LOW(ring_floor)

usb_again_4bits :   ; If there's more data to send, send immediatly.
cpse YH, XH
rjmp usb_send_4bits
cpse YL, XL
rjmp usb_send_4bits; clock is low again for 4 cycles max after this jump
rjmp wait_for_new_adc_data
;==============================================================================================================
;************************************************* End 4 bits *************************************************
;==============================================================================================================







;**********************************************************************************************************
;*****************************************                          ***************************************
;***************************************    5 bits per transection    *************************************
;*****************************************                          ***************************************
;**********************************************************************************************************
; At this point there's at least one byte to be sent. At each step, when we load a new byte we have to make
; sure there is data in buffer. We send 5 bytes, no matter the number of bytes per data point. So a new
; transaction with uncomplemented bit 7 is sent every 5 bytes, or 8 transections (5 bytes). We work on
; the 0-39 bits in the 5 bytes. Since the buffer is 5 byte aligned, we don't have to check until end
; if we need to return to origin.
usb_send_5bits :;************************************* Bits 35-39 *****************************************
LD usb_data, Y+; read next byte
USB_WRITE usb_L_5_1, usb_5_1, usb_5_2
; clock has been low 14 cycles max after out (from after_collection_wait)
cbr usb_data_comp,1<<adc_overflow ; for the first byte, the overflow bit is not complemented so set it back
sbrc usb_data, adc_overflow
sbr usb_data_comp, 1<<adc_overflow
USB_WRITE_COMP usb_H_5_1, usb_5_3, usb_5_4
NEW_DATA_CHECK usb_5_5, usb_5_37, usb_5_check1; make sure there more bytes to send
LD usb_data2, Y+            ; read next byte, bits 24-31 in usb_data2
mov usb_data3, usb_data2
LSR3_16 usb_data, usb_data3 ; bits 30-34 are now in usb_data3 bits 3-7.
USB_WRITE2 usb_L_5_2, usb_5_6, usb_5_7, usb_data3;******** Bits 30-34 *********************************
mov usb_data3, usb_data2
USB_WRITE_COMP usb_H_5_2, usb_5_8, usb_5_9
LSL2 usb_data3              ; bits 25-29 are now in usb_data3 bits 3-7. bit 24 is in bit 0 in usb_data2
NEW_DATA_CHECK usb_5_10, usb_5_38, usb_5_check2
USB_WRITE2 usb_L_5_3, usb_5_11, usb_5_12, usb_data3;****** Bits 25-29 **********************************
LD usb_data, Y+             ; read next byte, bits 16-23 in usb_data
wdr
USB_WRITE_COMP usb_H_5_3, usb_5_13, usb_5_14
mov usb_data3, usb_data
LSR_16 usb_data2, usb_data3 ; bits 20-24 are now in usb_data3 bits 3-7. bits 16-23 are in usb_data
NEW_DATA_CHECK usb_5_15, usb_5_39, usb_5_check3
USB_WRITE2 usb_L_5_4, usb_5_16, usb_5_17, usb_data3;****** Bits 20-24 **********************************
LD usb_data2, Y+             ; read next byte, bits 8-15 in usb_data2
USB_WRITE_COMP usb_H_5_4, usb_5_18, usb_5_19
mov usb_data3, usb_data2
LSR4_16 usb_data, usb_data3 ; bits 15-19 are now in usb_data3 bits 3-7. bits 8-14 are in usb_data2 bits 0-6
USB_WRITE2 usb_L_5_5, usb_5_20, usb_5_21, usb_data3;******* Bits 15-19 **********************************
mov usb_data, usb_data2
lsl usb_data2               ; bits 10-14 are now in usb_data2 bits 3-7. bits 8-9 are in usb_data bits 0-1
USB_WRITE_COMP usb_H_5_5, usb_5_22, usb_5_23
NEW_DATA_CHECK usb_5_24, usb_5_40, usb_5_check4
USB_WRITE2 usb_L_5_6, usb_5_25, usb_5_26, usb_data2;******** Bits 10-14 **********************************
LD usb_data3, Y+            ; read next byte, bits 0-7 in usb_data3
USB_WRITE_COMP usb_H_5_6, usb_5_27, usb_5_28
mov usb_data2, usb_data3
LSR2_16 usb_data, usb_data3 ; bits 5-9 are now in usb_data3 bits 3-7. bits 0-4 are in usb_data2 bits 0-4
USB_WRITE2 usb_L_5_7, usb_5_29, usb_5_30, usb_data3;******** Bits 5-9 ************************************
USB_WRITE_COMP usb_H_5_7, usb_5_31, usb_5_32
LSL3 usb_data2              ; bits 0-4 are now in usb_data2 bits 3-7.
USB_WRITE2 usb_L_5_8, usb_5_33, usb_5_34, usb_data2;******** Bits 0-4 ************************************
USB_WRITE_COMP usb_H_5_8, usb_5_35, usb_5_36

usb_end_5bits : ; now check whether we need to circle pointer back to start
cpse YH, ring_ceil_H
rjmp usb_again_5bits
cpse YL, ring_ceil_L
rjmp usb_again_5bits
ldi YH, HIGH(ring_floor)
ldi YL, LOW(ring_floor)

usb_again_5bits :   ; If there's more data to send, send immediatly.
cpse YH, XH
rjmp usb_send_5bits
cpse YL, XL
rjmp usb_send_5bits; clock is low again for 4 cycles max after this jump
rjmp wait_for_new_adc_data
;==============================================================================================================
;************************************************* End 5 bits *************************************************
;==============================================================================================================







;**********************************************************************************************************
;*****************************************                          ***************************************
;***************************************    6 bits per transection    *************************************
;*****************************************                          ***************************************
;**********************************************************************************************************
; At this point there's at least one byte to be sent. At each step, when we load a new byte we have to make
; sure there is data in buffer. We send 6 bytes, no matter the number of bytes per data point. So a new
; transaction with uncomplemented bit 7 is sent every 6 bytes, or 8 transections (6 bytes). We work on
; the 0-47 bits in the 6 bytes. Since the buffer is 6 byte aligned, we don't have to check until end
; if we need to return to origin.
usb_send_6bits :;************************************* Bits 42-47 *****************************************
LD usb_data, Y+; read next byte, bits 40-47 are in usb_data
USB_WRITE usb_L_6_1, usb_6_1, usb_6_2
; clock has been low 14 cycles max after out (from after_collection_wait)
cbr usb_data_comp,1<<adc_overflow ; for the first byte, the overflow bit is not complemented so set it back
sbrc usb_data, adc_overflow
sbr usb_data_comp, 1<<adc_overflow
USB_WRITE_COMP usb_H_6_1, usb_6_3, usb_6_4
NEW_DATA_CHECK usb_6_5, usb_6_6, usb_6_check1; make sure there more bytes to send
LD usb_data2, Y+            ; read next byte, bits 32-39 in usb_data2, bits 40-41 in usb_data
mov usb_data3, usb_data2
LSR2_16 usb_data, usb_data3 ; bits 36-41 are now in usb_data3 bits 2-7. bits 32-35 in usb_data2 bit 0-3
USB_WRITE2 usb_L_6_2, usb_6_7, usb_6_8, usb_data3;******** Bits 36-41 ************************************
NEW_DATA_CHECK_H usb_6_9, usb_6_10, usb_6_check2
LD usb_data3, Y+            ; read next byte, bits 24-31 in usb_data3, bits 32-35 in usb_data2
mov usb_data, usb_data3
USB_WRITE_COMP usb_H_6_2, usb_6_11, usb_6_12
LSR4_16 usb_data2, usb_data3; bits 30-35 are now in usb_data3 bits 2-7. bits 24-29 in usb_data bit 0-5
USB_WRITE2 usb_L_6_3, usb_6_13, usb_6_14, usb_data3;****** Bits 30-35 ************************************
NEW_DATA_CHECK_H usb_6_15, usb_6_16, usb_6_check3
USB_WRITE_COMP usb_H_6_3, usb_6_17, usb_6_18
LD usb_data2, Y+             ; read next byte, bits 16-23 in usb_data
LSL2 usb_data                ; bits 24-29 are now in usb_data bits 2-7. bits 16-23 in usb_data2
wdr
USB_WRITE2 usb_L_6_4, usb_6_19, usb_6_20, usb_data;****** Bits 24-29 *************************************
mov usb_data3, usb_data2
NEW_DATA_CHECK_H usb_6_21, usb_6_22, usb_6_check4
USB_WRITE_COMP usb_H_6_4, usb_6_23, usb_6_24
LD usb_data, Y+             ; read next byte, bits 8-15 in usb_data. bits 16-23 in usb_data2
USB_WRITE2 usb_L_6_5, usb_6_25, usb_6_26, usb_data3;******* Bits 18-23 ***********************************
mov usb_data3, usb_data
USB_WRITE_COMP usb_H_6_5, usb_6_27, usb_6_28
LSR2_16 usb_data2, usb_data3; bits 12-17 in usb_data3. bits 8-11 in usb_data bits 0-3
USB_WRITE2 usb_L_6_6, usb_6_29, usb_6_30, usb_data3;******** Bits 12-17 **********************************
NEW_DATA_CHECK_H usb_6_31, usb_6_32, usb_6_check5
LD usb_data2, Y+            ; read next byte, bits 0-7 in usb_data2
mov usb_data3, usb_data2
USB_WRITE_COMP usb_H_6_6, usb_6_33, usb_6_34
LSR4_16 usb_data, usb_data3 ; bits 6-11 in usb_data3. bits 0-5 in usb_data2 bits 0-5
USB_WRITE2 usb_L_6_7, usb_6_35, usb_6_36, usb_data3;******** Bits 6-11 ***********************************
USB_WRITE_COMP usb_H_6_7, usb_6_37, usb_6_38
LSL2 usb_data2              ; bits 0-5 are now in usb_data2 bits 2-7.
USB_WRITE2 usb_L_6_8, usb_6_39, usb_6_40, usb_data2;******** Bits 0-5 ************************************
USB_WRITE_COMP usb_H_6_8, usb_6_41, usb_6_42

usb_end_6bits : ; now check whether we need to circle pointer back to start
cpse YH, ring_ceil_H
rjmp usb_again_6bits
cpse YL, ring_ceil_L
rjmp usb_again_6bits
ldi YH, HIGH(ring_floor)
ldi YL, LOW(ring_floor)

usb_again_6bits :   ; If there's more data to send, send immediatly.
cpse YH, XH
rjmp usb_send_6bits
cpse YL, XL
rjmp usb_send_6bits; clock is low again for 4 cycles max after this jump
rjmp wait_for_new_adc_data
;==============================================================================================================
;************************************************* End 6 bits *************************************************
;==============================================================================================================







;**********************************************************************************************************
;*****************************************                          ***************************************
;***************************************    7 bits per transection    *************************************
;*****************************************                          ***************************************
;**********************************************************************************************************
; At this point there's at least one byte to be sent. At each step, when we load a new byte we have to make
; sure there is data in buffer. We send 7 bytes, no matter the number of bytes per data point. So a new
; transaction with uncomplemented bit 7 is sent every 7 bytes, or 8 transections (7 bytes). We work on
; the 0-55 bits in the 7 bytes. Since the buffer is 7 byte aligned, we don't have to check until end
; if we need to return to origin.
usb_send_7bits :;************************************* Bits 49-55 *****************************************
LD usb_data, Y+; read next byte, bits 48-55 are in usb_data
USB_WRITE usb_L_7_1, usb_7_1, usb_7_2
; clock has been low 14 cycles max after out (from after_collection_wait)
cbr usb_data_comp,1<<adc_overflow ; for the first byte, the overflow bit is not complemented so set it back
sbrc usb_data, adc_overflow
sbr usb_data_comp, 1<<adc_overflow
USB_WRITE_COMP usb_H_7_1, usb_7_3, usb_7_4
NEW_DATA_CHECK usb_7_5, usb_7_6, usb_7_check1; make sure there more bytes to send
LD usb_data2, Y+            ; read next byte, bits 40-47 in usb_data2, bit 48 in usb_data bit 0
mov usb_data3, usb_data2
LSR_16 usb_data, usb_data3 ; bits 42-48 are now in usb_data3 bits 1-7. bits 40-41 in usb_data2 bit 0-1
USB_WRITE2 usb_L_7_2, usb_7_7, usb_7_8, usb_data3;******** Bits 42-48 *************************************
NEW_DATA_CHECK_H usb_7_9, usb_7_10, usb_7_check2
LD usb_data3, Y+            ; read next byte, bits 32-39 in usb_data3, bits 40-41 in usb_data2 bit 0-1
mov usb_data, usb_data3
USB_WRITE_COMP usb_H_7_2, usb_7_11, usb_7_12
LSR2_16 usb_data2, usb_data3; bits 35-41 are now in usb_data3 bits 1-7. bits 32-34 in usb_data bit 0-2
USB_WRITE2 usb_L_7_3, usb_7_13, usb_7_14, usb_data3;****** Bits 35-41 *************************************
NEW_DATA_CHECK_H usb_7_15, usb_7_16, usb_7_check3
LD usb_data2, Y+            ; read next byte, bits 24-31 in usb_data2
mov usb_data3, usb_data2
USB_WRITE_COMP usb_H_7_3, usb_7_17, usb_7_18
LSR3_16 usb_data, usb_data3 ; bits 28-34 are now in usb_data3 bits 1-7. bits 24-27 in usb_data2 bits 0-3
wdr
USB_WRITE2 usb_L_7_4, usb_7_19, usb_7_20, usb_data3;****** Bits 28-34 *************************************
NEW_DATA_CHECK_H usb_7_21, usb_7_22, usb_7_check4
LD usb_data, Y+             ; read next byte, bits 16-23 in usb_data. bits 24-27 in usb_data2 bits 0-3
mov usb_data3, usb_data
USB_WRITE_COMP usb_H_7_4, usb_7_23, usb_7_24
LSR4_16 usb_data2, usb_data3; bits 21-27 in usb_data3. bits 16-20 in usb_data bits 0-4
USB_WRITE2 usb_L_7_5, usb_7_25, usb_7_26, usb_data3;******* Bits 21-27 ************************************
NEW_DATA_CHECK_H usb_7_43, usb_7_44, usb_7_check5
LD usb_data2, Y+            ; read next byte, bits 8-15 in usb_data2. bits 16-20 in usb_data bits 0-4
mov usb_data3, usb_data2
USB_WRITE_COMP usb_H_7_5, usb_7_27, usb_7_28
LSL3_16 usb_data, usb_data3; bits 14-20 in usb_data. bits 8-13 in usb_data2 bits 0-5
USB_WRITE2 usb_L_7_6, usb_7_29, usb_7_30, usb_data;********* Bits 14-20 ***********************************
NEW_DATA_CHECK_H usb_7_31, usb_7_32, usb_7_check6
LD usb_data, Y+            ; read next byte, bits 0-7 in usb_data
mov usb_data3, usb_data
USB_WRITE_COMP usb_H_7_6, usb_7_33, usb_7_34
LSL2_16 usb_data2, usb_data3 ; bits 7-13 in usb_data2. bits 0-6 in usb_data bits 0-6
USB_WRITE2 usb_L_7_7, usb_7_35, usb_7_36, usb_data2;******** Bits 7-13 ************************************
USB_WRITE_COMP usb_H_7_7, usb_7_37, usb_7_38
lsl usb_data                ; bits 0-6 are now in usb_data bits 1-7.
USB_WRITE2 usb_L_7_8, usb_7_39, usb_7_40, usb_data;********* Bits 0-6 *************************************
USB_WRITE_COMP usb_H_7_8, usb_7_41, usb_7_42

usb_end_7bits : ; now check whether we need to circle pointer back to start
cpse YH, ring_ceil_H
rjmp usb_again_7bits
cpse YL, ring_ceil_L
rjmp usb_again_7bits
ldi YH, HIGH(ring_floor)
ldi YL, LOW(ring_floor)

usb_again_7bits :   ; If there's more data to send, send immediatly.
cpse YH, XH
rjmp usb_send_7bits
cpse YL, XL
rjmp usb_send_7bits; clock is low again for 4 cycles max after this jump
jmp wait_for_new_adc_data
;==============================================================================================================
;************************************************* End 7 bits *************************************************
;==============================================================================================================







;**********************************************************************************************************
;*****************************************                          ***************************************
;***************************************    8 bits per transection    *************************************
;*****************************************                          ***************************************
;**********************************************************************************************************
; At this point there's a whole data point data to be sent (3, or 4 bytes depending if adc is 16/24 bit 
; wide). A transaction with uncomplemented bit 7 is sent every 3 or 4 bytes, or 3, or 4 transections.
; Since the buffer is 3 and 4 byte aligned, we don't have to check until end if we need to return to origin.
;**************************************************** Byte 3 (2) ******************************************
usb_send_8bits :
LD usb_data, Y+; read next byte
USB_WRITE usb_L_8_3_18, usb_8_1, usb_8_2;********* Byte 3 bits 0-7 *****************************************
cbr usb_data_comp,1<<adc_overflow ; for the first byte, the overflow bit is not complemented so set it back
sbrc usb_data, adc_overflow
sbr usb_data_comp, 1<<adc_overflow
USB_WRITE_COMP usb_H_8_3_18, usb_8_3, usb_8_4


;**************************************************** Byte 2 (1) *******************************************
wdr
LD usb_data, Y+; read next byte
USB_WRITE usb_L_8_2_18, usb_8_5, usb_8_6;********* Byte 2 bits 0-7 *****************************************
USB_WRITE_COMP usb_H_8_2_18, usb_8_7, usb_8_8


;**************************************************** Byte 1 (0) *******************************************
LD usb_data, Y+; read next byte
USB_WRITE usb_L_8_1_18, usb_8_9, usb_8_10;******** Byte 1 bits 0-7 *****************************************
USB_WRITE_COMP usb_H_8_1_18, usb_8_11, usb_8_12

sbrs adc_flags, adc_24bits	; if data is 16 bits wide, finish here, otherwise send 4th byte
rjmp usb_end_8bits

;**************************************************** Byte 0 ***********************************************
LD usb_data, Y+; read next byte
USB_WRITE usb_L_8_0_18, usb_8_13, usb_8_14;******* Byte 0 bits 0-7 *****************************************
USB_WRITE_COMP usb_H_8_0_18, usb_8_15, usb_8_16

usb_end_8bits : ; now check whether we need to circle pointer back to start
cpse YH, ring_ceil_H
rjmp usb_again_8bits
cpse YL, ring_ceil_L
rjmp usb_again_8bits
ldi YH, HIGH(ring_floor)
ldi YL, LOW(ring_floor)

usb_again_8bits :   ; If there's more data to send, send immediatly.
cpse YH, XH
rjmp usb_send_8bits
cpse YL, XL
rjmp usb_send_8bits; clock is low again for 4 cycles max after this jump
jmp wait_for_new_adc_data
;==============================================================================================================
;************************************************* End 8 bits *************************************************
;==============================================================================================================






;==============================================================================================================
;********************************************** End sending USB data ******************************************
;==============================================================================================================


; End of source code
