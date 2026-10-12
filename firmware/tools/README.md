# Firmware bench tools

Standalone diagnostics for the hardware. See [docs/PROJECT_GUIDE.md §14](../../docs/PROJECT_GUIDE.md#14-testing-diagnostics-and-demo-tools) for how to read the results.

| Tool | What it does | Run |
|---|---|---|
| `ecg_diag/` | AD8232 test: raw 250 Hz ECG stream + whether LO+/LO− are driven or floating | `pio run -d firmware/tools/ecg_diag -t upload` |
| `i2c_scan/` | MAX30100 I2C check: pull-up levels, bus scan at 100/10 kHz and with SDA/SCL swapped | `pio run -d firmware/tools/i2c_scan -t upload` |
| `serial_capture.py` | Save serial output to a file (optional reset, timed commands) | `~/.platformio/penv/bin/python firmware/tools/serial_capture.py <port> <seconds> out.raw` |
| `ecg_analyze.py` | Summarise an `ecg_diag` capture: stats, server quality-gate verdict, plot | `python firmware/tools/ecg_analyze.py out.raw out.png` (needs numpy, scipy, matplotlib) |

Flashing a tool replaces the main firmware. Restore it afterwards with `pio run -d firmware -t upload`. Stored WiFi credentials (NVS) are not erased by flashing.
