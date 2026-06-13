module kdr.hott.client;

import std.algorithm.comparison : clamp;
import std.math : pow;
import core.atomic : atomicStore, atomicLoad;

import dplug.math : vec2f;
import dplug.client : Client, IGraphics, LegalIO, LinearFloatParameter, BoolParameter, Parameter, PluginInfo, TimeInfo;
import dplug.core;

import kdr.hott.params;
import kdr.hott.dsp;
import kdr.hott.gui;
import kdr.params : buildParams;
import kdr.logging : logInfo;
import kdr.testing : benchmarkWithDefaultParams;

class HottClient : Client, IHottClient {
public:
    nothrow @nogc:

    this() {
        super();
        logInfo("Initialize %s", __FUNCTION__.ptr);
    }

    override IGraphics createGraphics() {
        if (!_gui) _gui = mallocNew!HottGUI(this, params);
        return _gui;
    }

    override Parameter[] buildParameters() {
        return buildParams!Params;
    }

    override PluginInfo buildPluginInfo() {
        return PluginInfo.init;
    }

    override LegalIO[] buildLegalIO() {
        auto io = makeVec!LegalIO();
        io ~= LegalIO(2, 2);
        return io.releaseData();
    }

    override void reset(double sampleRate, int maxFrames, int numInputs, int numOutputs) {
        _sampleRate = sampleRate;
        _dsp.reset();
        _dsp.updateCrossovers(cast(float)_sampleRate);
    }

    override void processAudio(const(float*)[] inputs, float*[] outputs, int frames, TimeInfo info) {
        if (!readParam!bool(Params.enable)) {
            // Bypass
            outputs[0][0..frames] = inputs[0][0..frames];
            outputs[1][0..frames] = inputs[1][0..frames];
            for (int b = 0; b < 3; ++b) {
                atomicStore(_bandInputDb[b], -200.0f);
                atomicStore(_bandOutputDb[b], -200.0f);
                atomicStore(_bandGainReductionDb[b], 0.0f);
            }
            return;
        }

        // 1. Read global parameters
        _dsp.lowCrossoverNorm = readParam!float(Params.lowXover);
        _dsp.highCrossoverNorm = readParam!float(Params.highXover);
        _dsp.amount = readParam!float(Params.amount);
        
        float timeParam = readParam!float(Params.time);
        _dsp.timeMult = timeParam * 2.0f;
        if (_dsp.timeMult < 0.01f) _dsp.timeMult = 0.01f;

        _dsp.globalOutputDb = readParam!float(Params.output) * 48.0f - 24.0f;

        bool softKnee = readParam!bool(Params.softKnee);
        bool rmsMode = readParam!bool(Params.rmsMode);

        // 2. Read per-band parameters
        for (int b = 0; b < 3; ++b) {
            float inDb = readParam!float(cast(Params)(Params.lowIn + b)) * 48.0f - 24.0f;
            _dsp.bandInLin[b] = pow(10.0f, inDb / 20.0f);

            float outDb = readParam!float(cast(Params)(Params.lowOut + b)) * 48.0f - 24.0f;
            _dsp.bandOutLin[b] = pow(10.0f, outDb / 20.0f);

            _dsp.bands[b].thresholdDb = readParam!float(cast(Params)(Params.lowDownThresh + b)) * 60.0f - 60.0f;
            _dsp.bands[b].upThresholdDb = readParam!float(cast(Params)(Params.lowUpThresh + b)) * 72.0f - 60.0f;

            _dsp.bands[b].ratio = normToRatio(readParam!float(cast(Params)(Params.lowDownRatio + b)));
            _dsp.bands[b].upRatio = normToRatio(readParam!float(cast(Params)(Params.lowUpRatio + b)));

            _dsp.bands[b].attackMs = normToAttack(readParam!float(cast(Params)(Params.lowAttack + b))) * _dsp.timeMult;
            _dsp.bands[b].releaseMs = normToRelease(readParam!float(cast(Params)(Params.lowRelease + b))) * _dsp.timeMult;

            _dsp.bands[b].kneeDb = softKnee ? 10.0f : 0.0f;
            _dsp.bands[b].rmsMode = rmsMode;
        }

        // 3. Process
        _dsp.resetPeaks();
        _dsp.updateCrossovers(cast(float)_sampleRate);
        _dsp.process(inputs, outputs, frames, cast(float)_sampleRate);

        // 4. Store peak levels for GUI
        for (int b = 0; b < 3; ++b) {
            atomicStore(_bandInputDb[b], _dsp.bands[b].peakInputDb);
            atomicStore(_bandOutputDb[b], _dsp.bands[b].peakOutputDb);
            atomicStore(_bandGainReductionDb[b], _dsp.bands[b].gainReductionDb);
        }
    }

    // IHottClient interface methods
    float getBandInputDb(int band) {
        return atomicLoad(_bandInputDb[2 - band]);
    }
    float getBandOutputDb(int band) {
        return atomicLoad(_bandOutputDb[2 - band]);
    }
    float getBandGainReduction(int band) {
        return atomicLoad(_bandGainReductionDb[2 - band]);
    }

private:
    double _sampleRate = 44100.0;
    HottDSP _dsp;
    HottGUI _gui;

    shared(float)[3] _bandInputDb = -200.0f;
    shared(float)[3] _bandOutputDb = -200.0f;
    shared(float)[3] _bandGainReductionDb = 0.0f;

    static float normToRatio(float norm) {
        if (norm >= 0.999f) return 1000.0f;
        return 1.0f / (1.0f - norm);
    }

    static float normToAttack(float norm) {
        return 0.1f * pow(1000.0f, norm);
    }

    static float normToRelease(float norm) {
        return 10.0f * pow(100.0f, norm);
    }
}

unittest {
    import kdr.testing : benchmarkWithDefaultParams;
    benchmarkWithDefaultParams!HottClient(50);
}
