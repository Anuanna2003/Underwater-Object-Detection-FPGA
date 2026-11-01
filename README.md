# Underwater-Object-Detection-FPGA

# FPGA-Based Underwater Object Detection and Counting Using Verilog HDL

An FPGA-based real-time underwater object detection and counting system implemented using Verilog HDL on the **Terasic DE2-115 FPGA development board** with the **Terasic TRDB-D5M camera**.

## 1. Project Overview

This project implements a real-time underwater object detection and counting system using FPGA-based image processing techniques.

The system captures live images from the Terasic TRDB-D5M camera, processes the incoming image data, identifies objects based on pixel intensity variations, counts the detected objects and displays the results on an LCD.

The design uses classical digital image processing techniques implemented entirely in hardware using Verilog HDL. It does not require a neural network or external computer during operation.

Underwater image enhancement techniques, including white balance correction, brightness stretching and adaptive thresholding, are incorporated to improve object detection under varying illumination conditions.

## 2. Objectives

- Implement real-time underwater object detection using Verilog HDL.
- Interface the Terasic TRDB-D5M camera with the DE2-115 FPGA board.
- Capture and process live camera image data.
- Convert raw Bayer camera data into RGB pixel information.
- Improve underwater image quality using white balance and brightness enhancement.
- Perform grayscale conversion and adaptive thresholding.
- Remove unwanted noise using 3×3 binary median filters.
- Detect and count objects using the Euler number-based blob counting technique.
- Display the detected object count on a 16×2 LCD.
- Display the processed live image through a VGA monitor.

## 3. Hardware and Software Requirements

| Component | Specification |
|---|---|
| FPGA Board | Terasic DE2-115 |
| FPGA Device | Altera Cyclone IV E EP4CE115F29C7 |
| Camera | Terasic TRDB-D5M |
| Image Sensor | MT9P031 (5 MP) |
| HDL | Verilog HDL |
| Development Environment | Intel Quartus Prime Lite 25.1 |
| Simulation | ModelSim |
| Input Clock | 50 MHz |
| Camera Clock | 25 MHz |
| Processing Resolution | 320 × 240 pixels |
| Display Resolution | 640 × 480 VGA |
| Image Processing | Classical digital image processing |

## 4. System Architecture

The complete system follows the processing sequence shown below.

```text
          TRDB-D5M CAMERA
             (Raw Bayer)
                  |
                  v
          D5M CAMERA CAPTURE
                  |
                  v
          RAW TO RGB CONVERSION
                  |
                  v
             PIXEL FRAMER
                  |
                  v
          UNDERWATER ENHANCEMENT
          (White Balance and
           Brightness Stretch)
                  |
             +----+----+
             |         |
             v         v
        FRAME BUFFER   GRAYSCALE
             |         THRESHOLD
             v             |
        VGA DISPLAY        v
             |       BINARY MEDIAN
             v        FILTER 1
        VGA MONITOR        |
                           v
                     BINARY MEDIAN
                       FILTER 2
                           |
                           v
                      BLOB COUNTER
                     (Euler Number)
                           |
                           v
                     COUNT REGISTER
                    (3-Frame Stability)
                           |
                           v
                      BINARY TO BCD
                           |
                           v
                       LCD DISPLAY
```

## 5. Working Principle and Detection Algorithm

The system performs the following operations:

**Step 1 – Camera Image Acquisition**

The TRDB-D5M camera captures live image data and sends raw 12-bit Bayer pixel information to the FPGA.

**Step 2 – RGB Conversion**

The `d5m_capture` module processes the Bayer data and reconstructs RGB colour information using a 2×2 pixel neighbourhood.

**Step 3 – Pixel Framing**

The `pixel_framer` module generates pixel addresses, row and frame markers for the 320×240 image.

**Step 4 – Underwater Image Enhancement**

The `underwater_enhance` module improves image quality using:

- Gray-world white balance correction.
- Brightness stretching using a 64-bin histogram.
- Adaptive threshold calculation based on average image brightness.

These operations help compensate for underwater colour distortion and poor illumination.

**Step 5 – Grayscale Conversion and Thresholding**

The RGB image is converted into grayscale using weighted pixel intensity:

Gray = (77R + 150G + 29B) / 256

The grayscale intensity is compared with the selected threshold to generate a binary image representing objects and background.

**Step 6 – Noise Removal**

Two cascaded 3×3 binary median filters remove unwanted noise and isolated pixels from the binary image.

**Step 7 – Object Detection and Counting**

The `blob_counter` module uses the Euler number-based method to identify and count connected objects in the binary image.

The counting process uses 2×2 pixel neighbourhood analysis.

**Step 8 – Stable Count Generation**

The `count_register` module updates the displayed object count only when the same count is detected in three consecutive frames. This reduces fluctuations in the displayed result.

**Step 9 – Output Display**

The detected object count is converted into decimal digits using the double-dabble (Binary-to-BCD) algorithm and displayed on the 16×2 LCD.

The processed live image is displayed simultaneously on a VGA monitor.

## 6. Verilog Modules

| Module | Function |
|---|---|
| `d5m_system_top.v` | Top-level module connecting all system components |
| `d5m_i2c_config.v` | Configures the D5M camera through I2C communication |
| `d5m_capture.v` | Captures camera data and converts Bayer pixels into RGB |
| `pixel_framer.v` | Generates pixel addresses and frame synchronization signals |
| `underwater_enhance.v` | Performs white balance, brightness enhancement and adaptive threshold calculation |
| `frame_buffer.v` | Stores processed image data for VGA display |
| `grayscale_threshold.v` | Converts RGB pixels into binary image data |
| `binary_median3x3.v` | Removes noise using a 3×3 binary median filter |
| `blob_counter.v` | Detects and counts objects using the Euler number method |
| `count_register.v` | Maintains a stable object count across consecutive frames |
| `binary_to_bcd.v` | Converts binary count into decimal digits |
| `seq_divider.v` | Performs sequential division for enhancement calculations |
| `lcd_display.v` | Displays the object count on the LCD |
| `vga_display.v` | Generates VGA timing and displays the live image |

## 7. FPGA Input and Output Interface

**Input:**
- Live image data from the TRDB-D5M camera.
- Camera synchronization signals (FVAL, LVAL and PIXCLK).
- FPGA clock and reset signals.
- User-controlled switches for image enhancement and threshold adjustment.

**Output:**
- Live colour image through VGA.
- Black-and-white thresholded image through VGA viewing mode.
- Detected object count on the 16×2 LCD.
- Debug status through FPGA LEDs.

## 8. Switch Configuration

| Switch | Function |
|---|---|
| SW[7:0] | Manual threshold adjustment |
| SW8 | Object polarity selection (dark/bright) |
| SW9 | VGA display mode (colour/binary) |
| SW10 | Adaptive threshold enable |
| SW11 | Underwater image enhancement enable |

KEY0 is used for system reset.

## 9. Camera and Display Interfaces

The project uses the following interfaces:

- **I2C Interface:** Configures the TRDB-D5M camera registers.
- **D5M Camera Interface:** Receives raw image data and synchronization signals.
- **Frame Buffer:** Stores 320×240 RGB565 pixel data.
- **VGA Interface:** Displays the live processed image at 640×480 resolution and 60 Hz.
- **LCD Interface:** Displays the detected object count.

## 10. Pin Assignments and Constraints

The repository includes TCL configuration files for FPGA board pin assignments and peripheral interfaces.

These files are used to configure the FPGA connections for the camera, clock, reset, switches, LEDs, LCD and VGA display.

## 11. Simulation and Hardware Results

The design is intended for implementation and verification using Intel Quartus Prime and ModelSim.

Important signals for simulation include:

- Camera pixel data and synchronization signals.
- RGB pixel outputs.
- Pixel valid and frame synchronization signals.
- Enhanced RGB pixel values.
- Grayscale threshold output.
- Binary median filter output.
- Detected object count.
- Stable count and LCD output signals.

Hardware photographs and simulation waveforms can be added to this section after verification.

## 12. Future Improvements

- Improve detection accuracy under different underwater lighting conditions.
- Extend the system to detect different types of underwater objects.
- Implement more advanced segmentation techniques.
- Improve noise removal and object separation.
- Explore hardware-efficient image processing architectures.
- Extend the system for underwater surveillance and monitoring applications.

## 13. Applications

- Underwater object monitoring.
- Marine environment observation.
- Underwater surveillance systems.
- Aquatic object counting.
- Real-time FPGA-based image processing.

## 14. Repository Structure

```text
Underwater-Object-Detection-FPGA/
│
├── README.md
│
├── d5m_system_top.v
├── d5m_capture.v
├── d5m_i2c_config.v
├── pixel_framer.v
├── underwater_enhance.v
├── frame_buffer.v
├── grayscale_threshold.v
├── binary_median3x3.v
├── blob_counter.v
├── count_register.v
├── binary_to_bcd.v
├── seq_divider.v
├── lcd_display.v
├── vga_display.v
│
├── clock_reset_switches_pins.tcl
├── d5m_pins.tcl
├── debug_leds.tcl
├── enhance_switch_pins.tcl
├── lcd_pins_verified.tcl
└── vga_pins.tcl
```

## 15. Author

**Anu Xavier**

## 16. Repository

FPGA-Based Underwater Object Detection and Counting Using Verilog HDL.

GitHub: https://github.com/Anuanna2003/Underwater-Object-Detection-FPGA
