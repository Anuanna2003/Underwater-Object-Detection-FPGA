# New switches for underwater_enhance (DE2-115)
# SW[10] = adaptive threshold  (PIN_AC24)
# SW[11] = white balance + contrast stretch  (PIN_AB24)

set_location_assignment PIN_AC24 -to SW_ADAPT
set_location_assignment PIN_AB24 -to SW_ENH

set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW_ADAPT
set_instance_assignment -name IO_STANDARD "3.3-V LVTTL" -to SW_ENH
