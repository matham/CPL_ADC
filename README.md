
This is the assembly code required to run the CPL ADC board.

The CPL ADC board is primarily composed of an AD7732 that samples from 2
channels at above 10Khz with upto 24-bit precision. The AD7732 is controlled
and interfaced with a ATMEGA1284P microcontroller. The microcontroller
can be read by 3 - 9 pins, allowing variable data rates. The Barst software
package comes with software that can communicate with the microcontroller's
data interface.
