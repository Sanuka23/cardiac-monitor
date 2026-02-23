/*
Arduino-MAX30100 oximetry / heart rate integrated sensor library
Copyright (C) 2016  OXullo Intersecans <x@brainrapers.org>

This program is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

This program is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with this program.  If not, see <http://www.gnu.org/licenses/>.
*/

#include <Wire.h>

#include "MAX30100.h"

MAX30100::MAX30100()
{
}

bool MAX30100::begin()
{
    // Don't call Wire.begin() or Wire.setClock() here —
    // let the caller control I2C init and clock speed.
    // This fixes ESP32 compatibility issues with cheap MAX30100 modules.

    if (getPartId() != EXPECTED_PART_ID) {
        return false;
    }

    setMode(DEFAULT_MODE);
    setLedsPulseWidth(DEFAULT_PULSE_WIDTH);
    setSamplingRate(DEFAULT_SAMPLING_RATE);
    setLedsCurrent(DEFAULT_IR_LED_CURRENT, DEFAULT_RED_LED_CURRENT);
    setHighresModeEnabled(true);

    return true;
}

void MAX30100::setMode(Mode mode)
{
    writeRegister(MAX30100_REG_MODE_CONFIGURATION, mode);
}

void MAX30100::setLedsPulseWidth(LEDPulseWidth ledPulseWidth)
{
    uint8_t previous = readRegister(MAX30100_REG_SPO2_CONFIGURATION);
    writeRegister(MAX30100_REG_SPO2_CONFIGURATION, (previous & 0xfc) | ledPulseWidth);
}

void MAX30100::setSamplingRate(SamplingRate samplingRate)
{
    uint8_t previous = readRegister(MAX30100_REG_SPO2_CONFIGURATION);
    writeRegister(MAX30100_REG_SPO2_CONFIGURATION, (previous & 0xe3) | (samplingRate << 2));
}

void MAX30100::setLedsCurrent(LEDCurrent irLedCurrent, LEDCurrent redLedCurrent)
{
    writeRegister(MAX30100_REG_LED_CONFIGURATION, redLedCurrent << 4 | irLedCurrent);
}

void MAX30100::setHighresModeEnabled(bool enabled)
{
    uint8_t previous = readRegister(MAX30100_REG_SPO2_CONFIGURATION);
    if (enabled) {
        writeRegister(MAX30100_REG_SPO2_CONFIGURATION, previous | MAX30100_SPC_SPO2_HI_RES_EN);
    } else {
        writeRegister(MAX30100_REG_SPO2_CONFIGURATION, previous & ~MAX30100_SPC_SPO2_HI_RES_EN);
    }
}

void MAX30100::update()
{
    readFifoData();
}

bool MAX30100::getRawValues(uint16_t *ir, uint16_t *red)
{
    if (!readoutsBuffer.isEmpty()) {
        SensorReadout readout = readoutsBuffer.pop();

        *ir = readout.ir;
        *red = readout.red;

        return true;
    } else {
        return false;
    }
}

void MAX30100::resetFifo()
{
    writeRegister(MAX30100_REG_FIFO_WRITE_POINTER, 0);
    writeRegister(MAX30100_REG_FIFO_READ_POINTER, 0);
    writeRegister(MAX30100_REG_FIFO_OVERFLOW_COUNTER, 0);
}

uint8_t MAX30100::readRegister(uint8_t address)
{
    Wire.beginTransmission(MAX30100_I2C_ADDRESS);
    Wire.write(address);
    Wire.endTransmission(false);
    Wire.requestFrom(MAX30100_I2C_ADDRESS, 1);

    return Wire.read();
}

void MAX30100::writeRegister(uint8_t address, uint8_t data)
{
    Wire.beginTransmission(MAX30100_I2C_ADDRESS);
    Wire.write(address);
    Wire.write(data);
    Wire.endTransmission();
}

void MAX30100::burstRead(uint8_t baseAddress, uint8_t *buffer, uint8_t length)
{
    Wire.beginTransmission(MAX30100_I2C_ADDRESS);
    Wire.write(baseAddress);
    Wire.endTransmission(false);
    Wire.requestFrom((uint8_t)MAX30100_I2C_ADDRESS, length);

    uint8_t idx = 0;
    while (Wire.available()) {
        buffer[idx++] = Wire.read();
    }
}

void MAX30100::readFifoData()
{
    uint8_t toRead;

    toRead = (readRegister(MAX30100_REG_FIFO_WRITE_POINTER) - readRegister(MAX30100_REG_FIFO_READ_POINTER)) & (MAX30100_FIFO_DEPTH-1);

    if (toRead) {
        // Read one sample (4 bytes) at a time instead of burst reading all
        // samples at once. This fixes I2C failures on ESP32 with many
        // MAX30100 modules that have weak/incorrect pull-up resistors.
        for (uint8_t i = 0; i < toRead; ++i) {
            uint8_t buffer[4];
            Wire.beginTransmission(MAX30100_I2C_ADDRESS);
            Wire.write(MAX30100_REG_FIFO_DATA);
            Wire.endTransmission(false);
            uint8_t got = Wire.requestFrom((uint8_t)MAX30100_I2C_ADDRESS, (uint8_t)4);
            if (got == 4) {
                buffer[0] = Wire.read();
                buffer[1] = Wire.read();
                buffer[2] = Wire.read();
                buffer[3] = Wire.read();
                readoutsBuffer.push({
                    .ir=(uint16_t)((buffer[0] << 8) | buffer[1]),
                    .red=(uint16_t)((buffer[2] << 8) | buffer[3])});
            } else {
                // Drain any partial data
                while (Wire.available()) Wire.read();
            }
        }
    }
}

void MAX30100::startTemperatureSampling()
{
    uint8_t modeConfig = readRegister(MAX30100_REG_MODE_CONFIGURATION);
    modeConfig |= MAX30100_MC_TEMP_EN;

    writeRegister(MAX30100_REG_MODE_CONFIGURATION, modeConfig);
}

bool MAX30100::isTemperatureReady()
{
    return !(readRegister(MAX30100_REG_MODE_CONFIGURATION) & MAX30100_MC_TEMP_EN);
}

float MAX30100::retrieveTemperature()
{
    int8_t tempInteger = readRegister(MAX30100_REG_TEMPERATURE_DATA_INT);
    float tempFrac = readRegister(MAX30100_REG_TEMPERATURE_DATA_FRAC);

    return tempFrac * 0.0625 + tempInteger;
}

void MAX30100::shutdown()
{
    uint8_t modeConfig = readRegister(MAX30100_REG_MODE_CONFIGURATION);
    modeConfig |= MAX30100_MC_SHDN;

    writeRegister(MAX30100_REG_MODE_CONFIGURATION, modeConfig);
}

void MAX30100::resume()
{
    uint8_t modeConfig = readRegister(MAX30100_REG_MODE_CONFIGURATION);
    modeConfig &= ~MAX30100_MC_SHDN;

    writeRegister(MAX30100_REG_MODE_CONFIGURATION, modeConfig);
}

uint8_t MAX30100::getPartId()
{
    return readRegister(0xff);
}
