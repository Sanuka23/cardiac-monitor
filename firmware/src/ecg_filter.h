#ifndef ECG_FILTER_H
#define ECG_FILTER_H

// 2nd order IIR Notch Filter at 50Hz
// Fs=250Hz, f0=50Hz, Q=25 (BW≈2Hz)
// Removes powerline interference
class EcgNotch50 {
public:
    EcgNotch50() : _x1(0), _x2(0), _y1(0), _y2(0) {}

    float step(float x) {
        float y = _b0 * x + _b1 * _x1 + _b2 * _x2 - _a1 * _y1 - _a2 * _y2;
        _x2 = _x1; _x1 = x;
        _y2 = _y1; _y1 = y;
        return y;
    }

    void reset() { _x1 = _x2 = _y1 = _y2 = 0; }

private:
    float _x1, _x2, _y1, _y2;
    static constexpr float _b0 =  0.981334f;
    static constexpr float _b1 = -0.606498f;
    static constexpr float _b2 =  0.981334f;
    static constexpr float _a1 = -0.606498f;
    static constexpr float _a2 =  0.962668f;
};

// 2nd order Butterworth Low-Pass Filter
// Fs=250Hz, Fc=40Hz
// Removes high-frequency noise, preserves QRS morphology
class EcgLowPass {
public:
    EcgLowPass() : _z1(0), _z2(0) {}

    float step(float x) {
        float y = _b0 * x + _z1;
        _z1 = _b1 * x - _a1 * y + _z2;
        _z2 = _b2 * x - _a2 * y;
        return y;
    }

    void reset() { _z1 = _z2 = 0; }

private:
    float _z1, _z2;
    // Direct Form II Transposed
    static constexpr float _b0 =  0.145310f;
    static constexpr float _b1 =  0.290620f;
    static constexpr float _b2 =  0.145310f;
    static constexpr float _a1 = -0.670919f;
    static constexpr float _a2 =  0.252160f;
};

// DC Baseline Removal (high-pass ~0.5Hz)
// Reuses DCRemover pattern from MAX30100_Filters.h
// Alpha=0.9875 gives Fc≈0.5Hz at Fs=250Hz
class EcgDCRemover {
public:
    EcgDCRemover(float alpha = 0.9875f) : _alpha(alpha), _dcw(0) {}

    float step(float x) {
        float oldDcw = _dcw;
        _dcw = x + _alpha * _dcw;
        return _dcw - oldDcw;
    }

    void reset() { _dcw = 0; }

private:
    float _alpha;
    float _dcw;
};

#endif // ECG_FILTER_H
