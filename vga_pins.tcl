# VGA DAC (ADV7123) + SW[9] view switch + SIOD pull-up
# Please compare once with the DE2-115 User Manual (VGA table, switch table).

set_location_assignment PIN_E12 -to VGA_R[0]
set_location_assignment PIN_E11 -to VGA_R[1]
set_location_assignment PIN_D10 -to VGA_R[2]
set_location_assignment PIN_F12 -to VGA_R[3]
set_location_assignment PIN_G10 -to VGA_R[4]
set_location_assignment PIN_J12 -to VGA_R[5]
set_location_assignment PIN_H8  -to VGA_R[6]
set_location_assignment PIN_H10 -to VGA_R[7]

set_location_assignment PIN_G8  -to VGA_G[0]
set_location_assignment PIN_G11 -to VGA_G[1]
set_location_assignment PIN_F8  -to VGA_G[2]
set_location_assignment PIN_H12 -to VGA_G[3]
set_location_assignment PIN_C8  -to VGA_G[4]
set_location_assignment PIN_B8  -to VGA_G[5]
set_location_assignment PIN_F10 -to VGA_G[6]
set_location_assignment PIN_C9  -to VGA_G[7]

set_location_assignment PIN_B10 -to VGA_B[0]
set_location_assignment PIN_A10 -to VGA_B[1]
set_location_assignment PIN_C11 -to VGA_B[2]
set_location_assignment PIN_B11 -to VGA_B[3]
set_location_assignment PIN_A11 -to VGA_B[4]
set_location_assignment PIN_C12 -to VGA_B[5]
set_location_assignment PIN_D11 -to VGA_B[6]
set_location_assignment PIN_D12 -to VGA_B[7]

set_location_assignment PIN_A12 -to VGA_CLK
set_location_assignment PIN_F11 -to VGA_BLANK_N
set_location_assignment PIN_G13 -to VGA_HS
set_location_assignment PIN_C13 -to VGA_VS
set_location_assignment PIN_C10 -to VGA_SYNC_N

set_location_assignment PIN_AB25 -to SW_VIEW

foreach p {VGA_CLK VGA_BLANK_N VGA_HS VGA_VS VGA_SYNC_N SW_VIEW} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to $p
}
for {set i 0} {$i < 8} {incr i} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_R[$i]
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_G[$i]
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to VGA_B[$i]
}

# SCCB data line pull-up
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to OV7670_SIOD
