/**
 * Stereo Capture Buffer and Hermite Cubic Interpolator for kdr-stutter.
 *
 * Implements:
 * - 524,288 sample (2^19) stereo circular capture buffer pre-allocated in reset() / allocate().
 * - Continuous sample capture for dry audio history.
 * - 4-point, 3rd-order Hermite cubic interpolation for alias-free pitch/rate shifting,
 *   tape plunge scrubbing, and fractional delay reads.
 * - Forward, reverse, pendulum read indexing and L/R split stereo offset.
 * - Pure @nogc nothrow @safe public interface with @trusted low-level memory primitives.
 *
 * Copyright: kdr 2026.
 * License: Boost License 1.0.
 */
module kdr.stutter.buffer;

import core.memory : pureFree, pureRealloc;
import std.math : floor, isNaN, isInfinity, fabs, sin, cos, PI;
import kdr.stutter.params : BufferDirection;

/// Power-of-two capacity for circular capture buffer: 2^19 = 524,288 samples.
/// At 44.1 kHz, ~11.89 seconds of capture history.
/// At 48.0 kHz, ~10.92 seconds.
/// At 96.0 kHz, ~5.46 seconds.
/// At 192.0 kHz, ~2.73 seconds.
enum size_t CAPTURE_BUFFER_SIZE = 524_288; // 1 << 19
enum size_t CAPTURE_BUFFER_MASK = CAPTURE_BUFFER_SIZE - 1; // 0x7FFFF

/**
 * 4-point, 3rd-order Hermite cubic interpolation.
 *
 * Evaluates the interpolated amplitude between y0 and y1 at fractional offset frac in [0.0, 1.0).
 * Matches the reference oracle in tests/stutter_e2e.d bit-identically.
 *
 * Guaranteed C1 continuous across sample boundaries, suppressing aliasing during pitch shifting,
 * scrubbing, and rate transitions.
 *
 * Params:
 *   ym1  = Sample at (t - 1)
 *   y0   = Sample at (t)
 *   y1   = Sample at (t + 1)
 *   y2   = Sample at (t + 2)
 *   frac = Fractional offset between y0 and y1 in [0.0, 1.0)
 *
 * Returns:
 *   Interpolated amplitude value.
 */
@nogc nothrow pure @safe
float hermiteInterpolate(float ym1, float y0, float y1, float y2, float frac) {
    const float c0 = y0;
    const float c1 = 0.5f * (y1 - ym1);
    const float c2 = ym1 - 2.5f * y0 + 2.0f * y1 - 0.5f * y2;
    const float c3 = 0.5f * (y2 - ym1) + 1.5f * (y0 - y1);
    return ((c3 * frac + c2) * frac + c1) * frac + c0;
}

/**
 * Stereo circular audio capture buffer for kdr-stutter.
 *
 * Pre-allocates 524,288 samples (2 MB) per channel (4 MB total) in reset() / allocate().
 * Continuously records incoming dry stereo samples in real-time.
 * Supports fractional buffer reads via 4-point Hermite cubic interpolation.
 */
struct StereoCaptureBuffer {
public:
    @nogc nothrow:

    /**
     * Allocates the circular capture buffer for the given sample rate.
     * Conforms to the PROJECT.md interface contract.
     *
     * Params:
     *   sampleRate = Current audio sample rate in Hz.
     *   maxSeconds = Maximum duration in seconds (defaults to 10.0f; pre-allocates 2^19 samples).
     */
    void allocate(double sampleRate, float maxSeconds = 10.0f) pure @safe {
        _sampleRate = sampleRate > 0.0 ? sampleRate : 44_100.0;
        allocateInternal();
        reset();
    }

    /**
     * Resets the capture buffer: ensures memory is allocated, zeros all sample data,
     * and resets the write head to index 0.
     * Conforms to the PROJECT.md interface contract.
     */
    void reset() pure @safe {
        allocateInternal();
        clearInternal();
        _writePos = 0;
    }

    /**
     * Writes a single stereo sample frame to the capture buffer at the current write head.
     * Automatically advances the write head with bitwise power-of-two wrap.
     *
     * Params:
     *   inL = Left channel sample amplitude.
     *   inR = Right channel sample amplitude.
     */
    void writeSample(float inL, float inR) pure @safe {
        writeSampleInternal(inL, inR);
    }

    /**
     * Reads interpolated stereo samples at fractional positions posL and posR using
     * 4-point, 3rd-order Hermite cubic interpolation.
     * Conforms to the PROJECT.md interface contract.
     *
     * Params:
     *   posL = Fractional sample position in circular buffer for left channel.
     *   posR = Fractional sample position in circular buffer for right channel.
     *   outL = (out) Interpolated left channel sample.
     *   outR = (out) Interpolated right channel sample.
     */
    void readHermite(float posL, float posR, out float outL, out float outR) const pure @safe {
        outL = readChannelHermite(0, posL);
        outR = readChannelHermite(1, posR);
    }

    /**
     * Reads a single interpolated sample for the specified channel at fractional position pos.
     *
     * Params:
     *   channel = Channel index (0 = Left, 1 = Right).
     *   pos     = Fractional sample position in circular buffer.
     *
     * Returns:
     *   Interpolated sample value (or 0.0f on invalid pos/unallocated buffer).
     */
    float readChannelHermite(int channel, float pos) const pure @safe {
        if (isNaN(pos) || isInfinity(pos)) {
            return 0.0f;
        }
        return readChannelHermiteInternal(channel, pos);
    }

    /**
     * Reads stereo samples at fractional delay offsets relative to the most recent written sample.
     *
     * Params:
     *   delayL = Delay in samples behind current write head for left channel (>= 0.0).
     *   delayR = Delay in samples behind current write head for right channel (>= 0.0).
     *   outL   = (out) Interpolated left channel sample.
     *   outR   = (out) Interpolated right channel sample.
     */
    void readRelativeHermite(float delayL, float delayR, out float outL, out float outR) const pure @safe {
        const float head = cast(float)(_writePos > 0 ? _writePos - 1 : CAPTURE_BUFFER_MASK);
        readHermite(head - delayL, head - delayR, outL, outR);
    }

    /**
     * Direct sample inspection for testing or integer reads.
     */
    float peek(int channel, size_t index) const pure @safe {
        return peekInternal(channel, index);
    }

    /// Returns current write head position in [0, CAPTURE_BUFFER_SIZE - 1].
    size_t writePos() const pure @safe {
        return _writePos;
    }

    /// Returns configured sample rate.
    double sampleRate() const pure @safe {
        return _sampleRate;
    }

    /// Returns true if buffers are currently allocated.
    bool isAllocated() const pure @safe {
        return isAllocatedInternal();
    }

    /// Explicitly releases all allocated memory.
    void free() pure @safe {
        freeInternal();
        _writePos = 0;
    }

    /// Destructor: frees allocated memory safely.
    ~this() pure @safe {
        freeInternal();
    }

    /// Disable implicit copies to prevent double frees of raw buffers.
    @disable this(this);

private:
    float* _left = null;
    float* _right = null;
    size_t _writePos = 0;
    double _sampleRate = 44_100.0;

    void allocateInternal() pure @trusted {
        if (_left is null) {
            _left = cast(float*) pureRealloc(null, CAPTURE_BUFFER_SIZE * float.sizeof);
            assert(_left !is null, "Failed to allocate left capture buffer");
        }
        if (_right is null) {
            _right = cast(float*) pureRealloc(null, CAPTURE_BUFFER_SIZE * float.sizeof);
            assert(_right !is null, "Failed to allocate right capture buffer");
        }
    }

    void clearInternal() pure @trusted {
        if (_left !is null) {
            _left[0 .. CAPTURE_BUFFER_SIZE] = 0.0f;
        }
        if (_right !is null) {
            _right[0 .. CAPTURE_BUFFER_SIZE] = 0.0f;
        }
    }

    void freeInternal() pure @trusted {
        if (_left !is null) {
            pureFree(_left);
            _left = null;
        }
        if (_right !is null) {
            pureFree(_right);
            _right = null;
        }
    }

    bool isAllocatedInternal() const pure @trusted {
        return _left !is null && _right !is null;
    }

    void writeSampleInternal(float inL, float inR) pure @trusted {
        if (_left is null || _right is null) {
            allocateInternal();
            clearInternal();
        }
        _left[_writePos] = inL;
        _right[_writePos] = inR;
        _writePos = (_writePos + 1) & CAPTURE_BUFFER_MASK;
    }

    float peekInternal(int channel, size_t index) const pure @trusted {
        const(float)* buf = (channel == 0) ? _left : _right;
        if (buf is null) return 0.0f;
        return buf[index & CAPTURE_BUFFER_MASK];
    }

    float readChannelHermiteInternal(int channel, float pos) const pure @trusted {
        const(float)* buf = (channel == 0) ? _left : _right;
        if (buf is null) {
            return 0.0f;
        }

        // Circular reduction to prevent floating-point / integer overflow on extreme bounds
        const double cap = cast(double) CAPTURE_BUFFER_SIZE;
        double dPos = pos % cap;
        if (dPos < 0.0) {
            dPos += cap;
        }

        const double fPos = floor(dPos);
        const long i0 = cast(long) fPos;
        const float frac = cast(float)(dPos - fPos);

        const size_t im1    = cast(size_t)((i0 - 1) & CAPTURE_BUFFER_MASK);
        const size_t i0_idx = cast(size_t)(i0 & CAPTURE_BUFFER_MASK);
        const size_t i1     = cast(size_t)((i0 + 1) & CAPTURE_BUFFER_MASK);
        const size_t i2     = cast(size_t)((i0 + 2) & CAPTURE_BUFFER_MASK);

        const float ym1 = buf[im1];
        const float y0  = buf[i0_idx];
        const float y1  = buf[i1];
        const float y2  = buf[i2];

        return hermiteInterpolate(ym1, y0, y1, y2, frac);
    }
}

/**
 * Helper utilities for buffer playback trajectory calculation:
 * Forward, reverse, pendulum read indexing and L/R split stereo offset.
 */
struct BufferPlayhead {
    @nogc nothrow pure @safe:

    /**
     * Calculates the normalized progress within a slice [0.0 .. 1.0) given the playback direction
     * and current slice repetition index.
     *
     * Params:
     *   phase       = Linear slice phase in [0.0 .. 1.0)
     *   sliceIndex  = Slice repetition index (0, 1, 2, ...)
     *   direction   = Forward, reverse, or pendulum
     *
     * Returns:
     *   Effective directional progress in [0.0 .. 1.0).
     */
    static float calculateDirectionalPhase(float phase, int sliceIndex, BufferDirection direction) {
        if (phase < 0.0f) phase = 0.0f;
        if (phase > 1.0f) phase = 1.0f;

        final switch (direction) {
            case BufferDirection.forward:
                return phase;
            case BufferDirection.reverse:
                return 1.0f - phase;
            case BufferDirection.pendulum:
                return (sliceIndex % 2 == 0) ? phase : (1.0f - phase);
        }
    }

    /**
     * Calculates the stereo read positions in the capture buffer given playback parameters.
     *
     * Params:
     *   anchorPos           = Capture buffer write position when gesture / slice was triggered.
     *   slicePhase          = Linear slice phase in [0.0 .. 1.0).
     *   sliceLengthSamples  = Length of slice in samples.
     *   sliceIndex          = Repetition index.
     *   direction           = Playback direction (forward, reverse, pendulum).
     *   pitchRatio          = Pitch/rate scaling factor (e.g. 2^(semitones / 12)).
     *   stereoOffsetSamples = Offset in samples applied to right channel.
     *   posL                = (out) Calculated circular read position for left channel.
     *   posR                = (out) Calculated circular read position for right channel.
     */
    static void calculateStereoReadPositions(
        size_t anchorPos,
        float slicePhase,
        float sliceLengthSamples,
        int sliceIndex,
        BufferDirection direction,
        float pitchRatio,
        float stereoOffsetSamples,
        out float posL,
        out float posR)
    {
        const float dirPhase = calculateDirectionalPhase(slicePhase, sliceIndex, direction);
        const float sliceOffset = dirPhase * sliceLengthSamples * pitchRatio;

        // Base read position relative to anchor
        const float basePos = cast(float) anchorPos + sliceOffset;

        posL = basePos;
        posR = basePos + stereoOffsetSamples;
    }
}

// ----------------------------------------------------------------------------
// Unit Tests
// ----------------------------------------------------------------------------

@nogc nothrow pure @safe
unittest {
    // 1. Hermite Interpolation Verification
    // Exact at integer positions (frac = 0.0)
    assert(fabs(hermiteInterpolate(1.0f, 2.0f, 3.0f, 4.0f, 0.0f) - 2.0f) < 1e-6f);
    // Exact at midpoint of linear ramp
    assert(fabs(hermiteInterpolate(1.0f, 2.0f, 3.0f, 4.0f, 0.5f) - 2.5f) < 1e-6f);
    // Smooth curve through peak
    const float peak = hermiteInterpolate(0.0f, 1.0f, 1.0f, 0.0f, 0.5f);
    assert(peak > 1.0f && peak < 1.25f);
    // C1 derivative continuity across adjacent segments
    const float left = hermiteInterpolate(0.0f, 1.0f, 2.0f, 3.0f, 0.999f);
    const float right = hermiteInterpolate(1.0f, 2.0f, 3.0f, 4.0f, 0.001f);
    assert(fabs(left - right) < 0.01f);
    // Bounds on zero signal
    assert(fabs(hermiteInterpolate(0.0f, 0.0f, 0.0f, 0.0f, 0.33f)) < 1e-6f);
}

@nogc nothrow pure @safe
unittest {
    // 2. StereoCaptureBuffer Lifecycle & Allocation
    StereoCaptureBuffer buf;
    assert(!buf.isAllocated());

    buf.allocate(48_000.0, 10.0f);
    assert(buf.isAllocated());
    assert(buf.sampleRate() == 48_000.0);
    assert(buf.writePos() == 0);

    // Initial buffer should be zeroed
    assert(buf.peek(0, 0) == 0.0f);
    assert(buf.peek(1, 0) == 0.0f);

    float oL, oR;
    buf.readHermite(0.0f, 0.0f, oL, oR);
    assert(!isNaN(oL) && !isNaN(oR) && oL == 0.0f && oR == 0.0f);

    buf.free();
    assert(!buf.isAllocated());
}

@nogc nothrow pure @safe
unittest {
    // 3. Continuous Write & Circular Wrapping
    StereoCaptureBuffer buf;
    buf.allocate(44_100.0);

    // Write ramp across boundary
    for (size_t i = 0; i < CAPTURE_BUFFER_SIZE + 10; ++i) {
        buf.writeSample(cast(float) i, cast(float)(i * 2));
    }

    assert(buf.writePos() == 10);

    // Sample at index 0 should have been overwritten by CAPTURE_BUFFER_SIZE
    assert(buf.peek(0, 0) == cast(float) CAPTURE_BUFFER_SIZE);
    assert(buf.peek(1, 0) == cast(float)(CAPTURE_BUFFER_SIZE * 2));

    // Sample at index 9 should be CAPTURE_BUFFER_SIZE + 9
    assert(buf.peek(0, 9) == cast(float)(CAPTURE_BUFFER_SIZE + 9));

    // Sample at index 10 should be the oldest sample: 10
    assert(buf.peek(0, 10) == 10.0f);
}

@nogc nothrow pure @safe
unittest {
    // 4. Fractional Hermite Read Across Circular Seam
    StereoCaptureBuffer buf;
    buf.allocate(44_100.0);

    // Place distinct samples around seam (CAPTURE_BUFFER_SIZE - 1 to 0)
    // Write at end of buffer
    for (size_t i = 0; i < CAPTURE_BUFFER_SIZE; ++i) {
        buf.writeSample(cast(float) i, cast(float) i);
    }

    // Read across boundary: index 524287.5
    float oL, oR;
    buf.readHermite(cast(float)(CAPTURE_BUFFER_SIZE - 1) + 0.5f, 0.0f, oL, oR);
    assert(!isNaN(oL) && !isInfinity(oL));
    assert(!isNaN(oR) && !isInfinity(oR));

    // Relative read behind write head
    buf.readRelativeHermite(0.0f, 0.0f, oL, oR);
    assert(oL == cast(float)(CAPTURE_BUFFER_SIZE - 1));
}

@nogc nothrow pure @safe
unittest {
    // 5. BufferPlayhead Direction & Stereo Offset
    // Forward
    assert(BufferPlayhead.calculateDirectionalPhase(0.25f, 0, BufferDirection.forward) == 0.25f);
    // Reverse
    assert(BufferPlayhead.calculateDirectionalPhase(0.25f, 0, BufferDirection.reverse) == 0.75f);
    // Pendulum: even -> forward, odd -> reverse
    assert(BufferPlayhead.calculateDirectionalPhase(0.25f, 0, BufferDirection.pendulum) == 0.25f);
    assert(BufferPlayhead.calculateDirectionalPhase(0.25f, 1, BufferDirection.pendulum) == 0.75f);
    assert(BufferPlayhead.calculateDirectionalPhase(0.25f, 2, BufferDirection.pendulum) == 0.25f);
    assert(BufferPlayhead.calculateDirectionalPhase(0.25f, 3, BufferDirection.pendulum) == 0.75f);

    // Stereo read positions
    float posL, posR;
    BufferPlayhead.calculateStereoReadPositions(
        1000, 0.5f, 400.0f, 0, BufferDirection.forward, 1.0f, 50.0f, posL, posR
    );
    assert(posL == 1200.0f);
    assert(posR == 1250.0f);
}

@nogc nothrow pure @safe
unittest {
    // 6. Adversarial Robustness: NaN, Inf, Extreme Values
    StereoCaptureBuffer buf;
    buf.allocate(44_100.0);

    float oL, oR;
    // NaN position
    buf.readHermite(float.nan, float.nan, oL, oR);
    assert(oL == 0.0f && oR == 0.0f);

    // Inf position
    buf.readHermite(float.infinity, -float.infinity, oL, oR);
    assert(oL == 0.0f && oR == 0.0f);

    // Extreme large positions
    buf.readHermite(1e12f, -1e12f, oL, oR);
    assert(!isNaN(oL) && !isNaN(oR));
}
