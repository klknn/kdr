module kdr.epiano2.parameter;

import core.stdc.stdio : snprintf, sscanf;
import std.algorithm : clamp;

import dplug.client.params : IntegerParameter;

/// Uses a negative value for "Pan" and positive for "Trem".
class ModParameter : IntegerParameter {
  nothrow @nogc:

  this(int index, string name, string label,
       int min = 0, int max = 1, int defaultValue = 0) {
    super(index, name, label, min, max, defaultValue);
    this._min = min;
    this._max = max;
  }

  override void toStringN(char* buffer, size_t numBytes) {
    printValue(buffer, numBytes, value());
  }

  override void stringFromNormalizedValue(
      double normalizedValue, char* buffer, size_t len) const {
    printValue(buffer, len, fromNormalized(normalizedValue));
  }

  override bool normalizedValueFromString(
      const(char)[] valueString, out double result) const {
    if (valueString.length > 63)
      return false;

    // Because the input string is not zero-terminated
    char[64] buf;
    snprintf(buf.ptr, buf.length, "%.*s", cast(int)(valueString.length),
             valueString.ptr);

    int denorm;
    if (buf[0 .. 5] == "Trem " && 1 == sscanf(buf.ptr + 5, "%d", &denorm)) {
      result = toNormalized(denorm);
      return true;
    }
    if (buf[0 .. 4] == "Pan " && 1 == sscanf(buf.ptr + 4, "%d", &denorm)) {
      result = toNormalized(-denorm);
      return true;
    }
    return false;
  }

 private:
  // Funcs from base class because they are private.
  int fromNormalized(double normalizedValue) const {
    double mapped = _min + (_max - _min) * normalizedValue;

    // slightly incorrect rounding, but lround is crashing
    int rounded = void;
    if (mapped >= 0)
      rounded = cast(int)(0.5f + mapped);
    else
      rounded = cast(int)(-0.5f + mapped);

    return clamp(rounded, _min, _max);
  }

  double toNormalized(int value) const {
    return clamp( (cast(double)value - _min) / (_max - _min), 0.0, 1.0);
  }

  int _min;
  int _max;
}

private void printValue(char* buffer, size_t numBytes, int v) @nogc nothrow {
  if (v > 0) {
    snprintf(buffer, numBytes, "Trem %d", v);
    return;
  }
  snprintf(buffer, numBytes, "Pan %d", -v);
}
