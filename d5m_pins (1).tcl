# ============================================================
# D5M camera pins for DE2-115  (Terasic TRDB-D5M on the GPIO header)
# Pin numbers are from Terasic's DE2_115_CAMERA.qsf.
# No file path needs to be changed. Just run:   source d5m_pins.tcl
# (D5M_STROBE is not used in this design, so it is not assigned.)
# ============================================================

set_location_assignment PIN_AB22 -to D5M_PIXLCLK
set_location_assignment PIN_AF25 -to D5M_XCLKIN
set_location_assignment PIN_AC22 -to D5M_RESET_N
set_location_assignment PIN_AF21 -to D5M_TRIGGER
set_location_assignment PIN_AD22 -to D5M_LVAL
set_location_assignment PIN_AG25 -to D5M_FVAL
set_location_assignment PIN_AD25 -to D5M_SDATA
set_location_assignment PIN_AH25 -to D5M_SCLK

set_location_assignment PIN_AC15 -to D5M_D[11]
set_location_assignment PIN_Y17  -to D5M_D[10]
set_location_assignment PIN_AC21 -to D5M_D[9]
set_location_assignment PIN_Y16  -to D5M_D[8]
set_location_assignment PIN_AD21 -to D5M_D[7]
set_location_assignment PIN_AE16 -to D5M_D[6]
set_location_assignment PIN_AD15 -to D5M_D[5]
set_location_assignment PIN_AE15 -to D5M_D[4]
set_location_assignment PIN_AC19 -to D5M_D[3]
set_location_assignment PIN_AF16 -to D5M_D[2]
set_location_assignment PIN_AD19 -to D5M_D[1]
set_location_assignment PIN_AF15 -to D5M_D[0]

foreach p {D5M_PIXLCLK D5M_XCLKIN D5M_RESET_N D5M_TRIGGER D5M_LVAL D5M_FVAL D5M_SDATA D5M_SCLK} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to $p
}
for {set i 0} {$i < 12} {incr i} {
    set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to D5M_D[$i]
}

# I2C data line pull-up
set_instance_assignment -name WEAK_PULL_UP_RESISTOR ON -to D5M_SDATA
