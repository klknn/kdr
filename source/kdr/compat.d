module kdr.compat;

version(linux) {
    extern(C) {
        pragma(mangle, "fmod@GLIBC_2.2.5") double fmod_compat(double x, double y) nothrow @nogc;
        pragma(mangle, "fmod") double fmod_local(double x, double y) nothrow @nogc { return fmod_compat(x, y); }

        pragma(mangle, "exp@GLIBC_2.2.5") double exp_compat(double x) nothrow @nogc;
        pragma(mangle, "exp") double exp_local(double x) nothrow @nogc { return exp_compat(x); }

        pragma(mangle, "expf@GLIBC_2.2.5") float expf_compat(float x) nothrow @nogc;
        pragma(mangle, "expf") float expf_local(float x) nothrow @nogc { return expf_compat(x); }

        pragma(mangle, "exp2f@GLIBC_2.2.5") float exp2f_compat(float x) nothrow @nogc;
        pragma(mangle, "exp2f") float exp2f_local(float x) nothrow @nogc { return exp2f_compat(x); }

        pragma(mangle, "log@GLIBC_2.2.5") double log_compat(double x) nothrow @nogc;
        pragma(mangle, "log") double log_local(double x) nothrow @nogc { return log_compat(x); }

        pragma(mangle, "logf@GLIBC_2.2.5") float logf_compat(float x) nothrow @nogc;
        pragma(mangle, "logf") float logf_local(float x) nothrow @nogc { return logf_compat(x); }

        pragma(mangle, "log2f@GLIBC_2.2.5") float log2f_compat(float x) nothrow @nogc;
        pragma(mangle, "log2f") float log2f_local(float x) nothrow @nogc { return log2f_compat(x); }

        pragma(mangle, "powf@GLIBC_2.2.5") float powf_compat(float x, float y) nothrow @nogc;
        pragma(mangle, "powf") float powf_local(float x, float y) nothrow @nogc { return powf_compat(x, y); }
    }
}

void forceCompatLink() nothrow @nogc {}
