module kdr.hott.params;

import dplug.client;
import dplug.core;
import kdr.params : RegisterBuilder;

/// Parameter ID enum.
@RegisterBuilder!ParamBuilder
enum Params {
    lowXover = 0,
    highXover = 1,
    amount = 2,
    time = 3,
    output = 4,
    lowOut = 5,
    midOut = 6,
    highOut = 7,
    enable = 8,
    lowDownThresh = 9,
    midDownThresh = 10,
    highDownThresh = 11,
    lowUpThresh = 12,
    midUpThresh = 13,
    highUpThresh = 14,
    softKnee = 15,
    rmsMode = 16,
    lowAttack = 17,
    midAttack = 18,
    highAttack = 19,
    lowRelease = 20,
    midRelease = 21,
    highRelease = 22,
    lowDownRatio = 23,
    midDownRatio = 24,
    highDownRatio = 25,
    lowUpRatio = 26,
    midUpRatio = 27,
    highUpRatio = 28,
    lowIn = 29,
    midIn = 30,
    highIn = 31,
}

struct ParamBuilder {
    static @nogc nothrow:

    static auto lowXover() {
        return mallocNew!LinearFloatParameter(Params.lowXover, "LowXover", "", 0.0f, 1.0f, 0.461f);
    }
    static auto highXover() {
        return mallocNew!LinearFloatParameter(Params.highXover, "HighXover", "", 0.0f, 1.0f, 0.436f);
    }
    static auto amount() {
        return mallocNew!LinearFloatParameter(Params.amount, "Amount", "", 0.0f, 1.0f, 1.0f);
    }
    static auto time() {
        return mallocNew!LinearFloatParameter(Params.time, "Time", "", 0.0f, 1.0f, 1.0f);
    }
    static auto output() {
        return mallocNew!LinearFloatParameter(Params.output, "Output", "", 0.0f, 1.0f, 0.5f);
    }
    static auto lowOut() {
        return mallocNew!LinearFloatParameter(Params.lowOut, "LowOut", "", 0.0f, 1.0f, 0.715f);
    }
    static auto midOut() {
        return mallocNew!LinearFloatParameter(Params.midOut, "MidOut", "", 0.0f, 1.0f, 0.619f);
    }
    static auto highOut() {
        return mallocNew!LinearFloatParameter(Params.highOut, "HighOut", "", 0.0f, 1.0f, 0.715f);
    }
    static auto enable() {
        return mallocNew!BoolParameter(Params.enable, "Enable", true);
    }
    static auto lowDownThresh() {
        return mallocNew!LinearFloatParameter(Params.lowDownThresh, "LowDownThresh", "", 0.0f, 1.0f, 0.436667f);
    }
    static auto midDownThresh() {
        return mallocNew!LinearFloatParameter(Params.midDownThresh, "MidDownThresh", "", 0.0f, 1.0f, 0.496667f);
    }
    static auto highDownThresh() {
        return mallocNew!LinearFloatParameter(Params.highDownThresh, "HighDownThresh", "", 0.0f, 1.0f, 0.408333f);
    }
    static auto lowUpThresh() {
        return mallocNew!LinearFloatParameter(Params.lowUpThresh, "LowUpThresh", "", 0.0f, 1.0f, 0.266667f);
    }
    static auto midUpThresh() {
        return mallocNew!LinearFloatParameter(Params.midUpThresh, "MidUpThresh", "", 0.0f, 1.0f, 0.252778f);
    }
    static auto highUpThresh() {
        return mallocNew!LinearFloatParameter(Params.highUpThresh, "HighUpThresh", "", 0.0f, 1.0f, 0.266667f);
    }
    static auto softKnee() {
        return mallocNew!BoolParameter(Params.softKnee, "SoftKnee", true);
    }
    static auto rmsMode() {
        return mallocNew!BoolParameter(Params.rmsMode, "RmsMode", true);
    }
    static auto lowAttack() {
        return mallocNew!LinearFloatParameter(Params.lowAttack, "LowAttack", "", 0.0f, 1.0f, 0.893114f);
    }
    static auto midAttack() {
        return mallocNew!LinearFloatParameter(Params.midAttack, "MidAttack", "", 0.0f, 1.0f, 0.783403f);
    }
    static auto highAttack() {
        return mallocNew!LinearFloatParameter(Params.highAttack, "HighAttack", "", 0.0f, 1.0f, 0.710078f);
    }
    static auto lowRelease() {
        return mallocNew!LinearFloatParameter(Params.lowRelease, "LowRelease", "", 0.0f, 1.0f, 0.725123f);
    }
    static auto midRelease() {
        return mallocNew!LinearFloatParameter(Params.midRelease, "MidRelease", "", 0.0f, 1.0f, 0.725123f);
    }
    static auto highRelease() {
        return mallocNew!LinearFloatParameter(Params.highRelease, "HighRelease", "", 0.0f, 1.0f, 0.560275f);
    }
    static auto lowDownRatio() {
        return mallocNew!LinearFloatParameter(Params.lowDownRatio, "LowDownRatio", "", 0.0f, 1.0f, 0.985007f);
    }
    static auto midDownRatio() {
        return mallocNew!LinearFloatParameter(Params.midDownRatio, "MidDownRatio", "", 0.0f, 1.0f, 0.985007f);
    }
    static auto highDownRatio() {
        return mallocNew!LinearFloatParameter(Params.highDownRatio, "HighDownRatio", "", 0.0f, 1.0f, 0.999f);
    }
    static auto lowUpRatio() {
        return mallocNew!LinearFloatParameter(Params.lowUpRatio, "LowUpRatio", "", 0.0f, 1.0f, 0.760192f);
    }
    static auto midUpRatio() {
        return mallocNew!LinearFloatParameter(Params.midUpRatio, "MidUpRatio", "", 0.0f, 1.0f, 0.760192f);
    }
    static auto highUpRatio() {
        return mallocNew!LinearFloatParameter(Params.highUpRatio, "HighUpRatio", "", 0.0f, 1.0f, 0.760192f);
    }
    static auto lowIn() {
        return mallocNew!LinearFloatParameter(Params.lowIn, "LowIn", "", 0.0f, 1.0f, 0.608f);
    }
    static auto midIn() {
        return mallocNew!LinearFloatParameter(Params.midIn, "MidIn", "", 0.0f, 1.0f, 0.608f);
    }
    static auto highIn() {
        return mallocNew!LinearFloatParameter(Params.highIn, "HighIn", "", 0.0f, 1.0f, 0.608f);
    }
}
