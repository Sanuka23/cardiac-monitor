"""Capture ESP32 serial output to a file: optional reset, read for N seconds, optionally send commands.

Usage (pyserial is bundled with PlatformIO):
  ~/.platformio/penv/bin/python firmware/tools/serial_capture.py /dev/cu.usbserial-0001 30 out.raw
  ... --no-reset            keep the board running (opening the port may still reset some boards)
  ... --send=5:p            at t=5 s send 'p' (plotter mode); 't' = text mode, 'b' = BLE provisioning
"""
import sys
import time

import serial

port, seconds, out_path = sys.argv[1], float(sys.argv[2]), sys.argv[3]
reset = "--no-reset" not in sys.argv
send = [a.split("=", 1)[1] for a in sys.argv if a.startswith("--send=")]

ser = serial.Serial()
ser.port, ser.baudrate, ser.timeout = port, 115200, 0.2
ser.dtr = False
ser.rts = False
ser.open()
if reset:
    ser.rts = True   # EN low -> reset
    time.sleep(0.1)
    ser.rts = False  # release
start = time.time()
pending = sorted((float(t), c) for t, c in (s.split(":", 1) for s in send))
with open(out_path, "wb") as f:
    while time.time() - start < seconds:
        if pending and time.time() - start >= pending[0][0]:
            ser.write(pending.pop(0)[1].encode())
        chunk = ser.read(4096)
        if chunk:
            f.write(chunk)
            f.flush()
ser.close()
