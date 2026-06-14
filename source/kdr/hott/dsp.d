module kdr.hott.dsp;

import std.math : log10, pow, abs, cos, sin, PI, exp, sqrt;
import mir.math : approxEqual;

@nogc nothrow:

/// Biquad filter struct for crossover.
struct Biquad {
    @nogc nothrow @safe pure:

    float b0 = 1, b1 = 0, b2 = 0, a1 = 0, a2 = 0;
    float x1 = 0, x2 = 0, y1 = 0, y2 = 0;

    void reset() {
        x1 = x2 = y1 = y2 = 0;
    }

    void setLowpass(float cutoffHz, float q, float sampleRate) {
        const w0 = 2.0f * PI * cutoffHz / sampleRate;
        const alpha = sin(w0) / (2.0f * q);
        const cosW = cos(w0);

        const a0 = 1.0f + alpha;
        b0 = (1.0f - cosW) / (2.0f * a0);
        b1 = (1.0f - cosW) / a0;
        b2 = (1.0f - cosW) / (2.0f * a0);
        a1 = -2.0f * cosW / a0;
        a2 = (1.0f - alpha) / a0;
    }

    void setHighpass(float cutoffHz, float q, float sampleRate) {
        const w0 = 2.0f * PI * cutoffHz / sampleRate;
        const alpha = sin(w0) / (2.0f * q);
        const cosW = cos(w0);

        const a0 = 1.0f + alpha;
        b0 = (1.0f + cosW) / (2.0f * a0);
        b1 = -(1.0f + cosW) / a0;
        b2 = (1.0f + cosW) / (2.0f * a0);
        a1 = -2.0f * cosW / a0;
        a2 = (1.0f - alpha) / a0;
    }

    float process(float x) {
        float y = b0 * x + b1 * x1 + b2 * x2 - a1 * y1 - a2 * y2;
        x2 = x1;
        x1 = x;
        y2 = y1;
        y1 = y;
        return y;
    }
}

/// Linkwitz-Riley 4th order crossover filter (2 cascaded biquads).
struct LinkwitzRiley4 {
    @nogc nothrow @safe:

    Biquad[2] lpL, lpR;
    Biquad[2] hpL, hpR;

    void reset() {
        foreach (ref f; lpL) f.reset();
        foreach (ref f; lpR) f.reset();
        foreach (ref f; hpL) f.reset();
        foreach (ref f; hpR) f.reset();
    }

    void setFrequency(float freqHz, float sampleRate) {
        import std.math : SQRT1_2;
        lpL[0].setLowpass(freqHz, SQRT1_2, sampleRate);
        lpL[1].setLowpass(freqHz, SQRT1_2, sampleRate);
        lpR[0].setLowpass(freqHz, SQRT1_2, sampleRate);
        lpR[1].setLowpass(freqHz, SQRT1_2, sampleRate);

        hpL[0].setHighpass(freqHz, SQRT1_2, sampleRate);
        hpL[1].setHighpass(freqHz, SQRT1_2, sampleRate);
        hpR[0].setHighpass(freqHz, SQRT1_2, sampleRate);
        hpR[1].setHighpass(freqHz, SQRT1_2, sampleRate);
    }

    // Process stereo input, returning lowpass L/R and highpass L/R.
    void process(float inL, float inR, out float lpOutL, out float lpOutR, out float hpOutL, out float hpOutR) {
        lpOutL = lpL[1].process(lpL[0].process(inL));
        lpOutR = lpR[1].process(lpR[0].process(inR));
        hpOutL = hpL[1].process(hpL[0].process(inL));
        hpOutR = hpR[1].process(hpR[0].process(inR));
    }
}

/// A single band of dynamics processor (downward + upward compression).
struct HottCompressorBand {
    @nogc nothrow:

    float thresholdDb = 0.0f;
    float ratio = 1.0f;
    float attackMs = 10.0f;
    float releaseMs = 100.0f;
    float upThresholdDb = -60.0f;
    float upRatio = 1.0f;
    float kneeDb = 0.0f;
    bool rmsMode = false;

    // States
    float envelopeDb = 0.0f;
    float gainReductionDb = 0.0f;

    // RMS sliding window states
    enum int RMS_WINDOW_SIZE = 128;
    float[RMS_WINDOW_SIZE] rmsBufL = 0;
    float[RMS_WINDOW_SIZE] rmsBufR = 0;
    float rmsSumL = 0.0f;
    float rmsSumR = 0.0f;
    int rmsIndex = 0;

    float peakInputDb = -200.0f;
    float peakOutputDb = -200.0f;

    void reset() {
        envelopeDb = 0.0f;
        gainReductionDb = 0.0f;
        rmsBufL[] = 0;
        rmsBufR[] = 0;
        rmsSumL = 0.0f;
        rmsSumR = 0.0f;
        rmsIndex = 0;
        peakInputDb = -200.0f;
        peakOutputDb = -200.0f;
    }

    // Process a stereo frame, returns gain reduction in dB.
    float process(float inL, float inR, out float outL, out float outR, float sampleRate) {
        import std.algorithm.comparison : max, min;

        float inputAbs;
        if (rmsMode) {
            float sL = inL * inL;
            float sR = inR * inR;
            rmsSumL -= rmsBufL[rmsIndex];
            rmsSumR -= rmsBufR[rmsIndex];
            rmsBufL[rmsIndex] = sL;
            rmsBufR[rmsIndex] = sR;
            rmsSumL += sL;
            rmsSumR += sR;
            rmsIndex = (rmsIndex + 1) % RMS_WINDOW_SIZE;

            float rmsL = sqrt(max(0.0f, rmsSumL / RMS_WINDOW_SIZE));
            float rmsR = sqrt(max(0.0f, rmsSumR / RMS_WINDOW_SIZE));
            inputAbs = max(rmsL, rmsR);
        } else {
            inputAbs = max(abs(inL), abs(inR));
        }

        float inputDb = (inputAbs > 1e-10f) ? 20.0f * log10(inputAbs) : -200.0f;
        peakInputDb = max(peakInputDb, inputDb);

        // Compute static gain reduction
        float grDb = 0.0f;
        float halfKnee = kneeDb / 2.0f;

        // Downward compression
        if (kneeDb <= 0.01f) {
            if (inputDb > thresholdDb) {
                grDb = (thresholdDb - inputDb) * (1.0f - 1.0f / ratio);
            }
        } else {
            float lower = thresholdDb - halfKnee;
            float upper = thresholdDb + halfKnee;
            if (inputDb <= lower) {
                // no downward reduction
            } else if (inputDb >= upper) {
                grDb = (thresholdDb - inputDb) * (1.0f - 1.0f / ratio);
            } else {
                float x = inputDb - lower;
                grDb = -(1.0f - 1.0f / ratio) * x * x / (2.0f * kneeDb);
            }
        }

        // Upward compression
        if (upRatio > 1.001f && inputDb < upThresholdDb && inputDb > -100.0f) {
            float under = upThresholdDb - inputDb;
            float target = upThresholdDb - under / upRatio;
            grDb += (target - inputDb); // positive = boost
        }

        // Smooth with envelope follower
        float attackCoeff = exp(-1.0f / (attackMs * 0.001f * sampleRate));
        float releaseCoeff = exp(-1.0f / (releaseMs * 0.001f * sampleRate));

        if (grDb < envelopeDb) {
            envelopeDb = attackCoeff * envelopeDb + (1.0f - attackCoeff) * grDb;
        } else {
            envelopeDb = releaseCoeff * envelopeDb + (1.0f - releaseCoeff) * grDb;
        }

        gainReductionDb = envelopeDb;
        float gain = pow(10.0f, envelopeDb / 20.0f);
        outL = inL * gain;
        outR = inR * gain;

        float outAbs = max(abs(outL), abs(outR));
        float outDb = (outAbs > 1e-10f) ? 20.0f * log10(outAbs) : -200.0f;
        peakOutputDb = max(peakOutputDb, outDb);

        return gainReductionDb;
    }
}

/// Whole 3-band compressor DSP wrapper
struct HottDSP {
    @nogc nothrow:

    LinkwitzRiley4 xoverLow;
    LinkwitzRiley4 xoverHigh;

    HottCompressorBand[3] bands; // Low=0, Mid=1, High=2

    float lowCrossoverNorm = 0.461f; // 88.3 Hz
    float highCrossoverNorm = 0.436f; // 2.50 kHz

    float amount = 1.0f; // dry/wet
    float timeMult = 1.0f; // time constant multiplier
    float globalInputDb = 0.0f;
    float globalOutputDb = 0.0f;

    float[3] bandInLin = [1.0f, 1.0f, 1.0f];
    float[3] bandOutLin = [1.0f, 1.0f, 1.0f];

    void reset() {
        xoverLow.reset();
        xoverHigh.reset();
        foreach (ref b; bands) b.reset();
    }

    void resetPeaks() {
        foreach (ref b; bands) {
            b.peakInputDb = -200.0f;
            b.peakOutputDb = -200.0f;
        }
    }

    void updateCrossovers(float sampleRate) {
        // Low crossover: 20..500 Hz
        float lowFreq = 20.0f * pow(500.0f / 20.0f, lowCrossoverNorm);
        // High crossover: 500..20000 Hz
        float highFreq = 500.0f * pow(20000.0f / 500.0f, highCrossoverNorm);

        xoverLow.setFrequency(lowFreq, sampleRate);
        xoverHigh.setFrequency(highFreq, sampleRate);
    }

    void process(const(float*)[] inputs, float*[] outputs, int frames, float sampleRate) {
        float globalInLin = pow(10.0f, globalInputDb / 20.0f);
        float globalOutLin = pow(10.0f, globalOutputDb / 20.0f);

        for (int i = 0; i < frames; ++i) {
            float inL = inputs[0][i] * globalInLin;
            float inR = inputs[1][i] * globalInLin;

            // 1. Crossover splits
            float lpL, lpR, hpL, hpR;
            xoverLow.process(inL, inR, lpL, lpR, hpL, hpR);

            float midL, midR, hiL, hiR;
            xoverHigh.process(hpL, hpR, midL, midR, hiL, hiR);

            // Low band = lpL/lpR
            // Mid band = midL/midR
            // High band = hiL/hiR

            // 2. Per-band input gains
            float b0L = lpL * bandInLin[0];
            float b0R = lpR * bandInLin[0];
            float b1L = midL * bandInLin[1];
            float b1R = midR * bandInLin[1];
            float b2L = hiL * bandInLin[2];
            float b2R = hiR * bandInLin[2];

            // 3. Process bands through their compressor
            float outLowL, outLowR;
            bands[0].process(b0L, b0R, outLowL, outLowR, sampleRate);

            float outMidL, outMidR;
            bands[1].process(b1L, b1R, outMidL, outMidR, sampleRate);

            float outHighL, outHighR;
            bands[2].process(b2L, b2R, outHighL, outHighR, sampleRate);

            // 4. Sum bands with per-band output gains
            float sumL = outLowL * bandOutLin[0] + outMidL * bandOutLin[1] + outHighL * bandOutLin[2];
            float sumR = outLowR * bandOutLin[0] + outMidR * bandOutLin[1] + outHighR * bandOutLin[2];

            // 5. Dry/wet blend and global output gain
            outputs[0][i] = (inL * (1.0f - amount) + sumL * amount) * globalOutLin;
            outputs[1][i] = (inR * (1.0f - amount) + sumR * amount) * globalOutLin;
        }
    }
}

unittest {
    // 1. Test Biquad
    Biquad b;
    b.setLowpass(1000.0f, 0.707f, 44100.0f);
    // Feeding DC signal (1.0), lowpass should eventually output 1.0
    float lpOut = 0;
    foreach (i; 0 .. 1000) {
        lpOut = b.process(1.0f);
    }
    assert(approxEqual(lpOut, 1.0f, 1e-3f));

    b.reset();
    b.setHighpass(1000.0f, 0.707f, 44100.0f);
    // Feeding DC signal (1.0), highpass should eventually output 0.0
    float hpOut = 0;
    foreach (i; 0 .. 1000) {
        hpOut = b.process(1.0f);
    }
    assert(approxEqual(hpOut, 0.0f, 1e-3f));

    // 2. Test LinkwitzRiley4
    LinkwitzRiley4 lr;
    lr.setFrequency(1000.0f, 44100.0f);
    float lpL, lpR, hpL, hpR;
    foreach (i; 0 .. 1000) {
        lr.process(1.0f, 1.0f, lpL, lpR, hpL, hpR);
    }
    assert(approxEqual(lpL, 1.0f, 1e-3f));
    assert(approxEqual(hpL, 0.0f, 1e-3f));

    // 3. Test HottCompressorBand Downward Compression
    HottCompressorBand band;
    band.reset();
    band.thresholdDb = -10.0f;
    band.ratio = 4.0f;
    band.attackMs = 1.0f;
    band.releaseMs = 1.0f;
    band.upRatio = 1.0f; // off

    float outL, outR;
    // Feed 0 dB signal (1.0f) -> inputDb = 0
    // Gain reduction target should be (threshold - inputDb) * (1 - 1/ratio) = (-10 - 0) * (1 - 0.25) = -7.5 dB
    foreach (i; 0 .. 5000) {
        band.process(1.0f, 1.0f, outL, outR, 44100.0f);
    }
    assert(approxEqual(band.gainReductionDb, -7.5f, 1e-2f));

    // 4. Test HottCompressorBand Upward Compression
    band.reset();
    band.thresholdDb = 0.0f;
    band.ratio = 1.0f; // off
    band.upThresholdDb = -20.0f;
    band.upRatio = 2.0f;
    band.attackMs = 1.0f;
    band.releaseMs = 1.0f;

    // Feed -30 dB signal
    float inVal = pow(10.0f, -30.0f / 20.0f);
    // target boost should be:
    // under = -20 - (-30) = 10
    // target = -20 - 5 = -25
    // boost = -25 - (-30) = +5.0 dB
    foreach (i; 0 .. 5000) {
        band.process(inVal, inVal, outL, outR, 44100.0f);
    }
    assert(approxEqual(band.gainReductionDb, 5.0f, 1e-2f));
}
