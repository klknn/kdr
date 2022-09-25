/// Parameter utility.
module kdr.params;

import std.traits : getUDAs, EnumMembers;

import dplug.core.vec : makeVec, Vec;
import dplug.client.params : Parameter, EnumParameter, IntegerParameter;


/// UDA for registering builder struct of param enum.
/// Params:
///   T = Builder struct.
struct RegisterBuilder(T) {
  alias Builder = T;
}

/// For dplug.client.Client.buildParameters.
/// Params:
///   E = Parameter ID enum.
/// Returns: a type-erased parameter slice of the given enum Params.
Parameter[] buildParams(E)() {
  Vec!Parameter params = makeVec!Parameter(EnumMembers!E.length);
  alias ParamBuilder = getUDAs!(E, RegisterBuilder)[0].Builder;
  static foreach (i, pname; __traits(allMembers, E)) {
    params[i] = __traits(getMember, ParamBuilder, pname)();
    assert(i == params[i].index, pname ~ " has wrong index.");
  }
  return params.releaseData();
}


/// Casts types from untyped parameters using parameter id.
/// Params:
///   pid = Params enum id.
///   params = type-erased parameter array.
/// Returns: statically-known typed param.
auto typedParam(alias pid)(Parameter[] params) {
  alias Params = typeof(pid);
  alias ParamBuilder = getUDAs!(Params, RegisterBuilder)[0].Builder;
  alias T = typeof(__traits(getMember, ParamBuilder, __traits(allMembers, Params)[pid])());
  return cast(T) params[pid];
}

/// Example parameters.
version (unittest) {
  /// Parameter ID.
  @RegisterBuilder!TestParamBuilder
  enum TestParams {
    volume,
    wave,
  }

  /// Parameter builder corresponding to TestParams fields.
  struct TestParamBuilder {
    static volume() {
      return new IntegerParameter(TestParams.volume, "volume", "%", 0, 100, 50);
    }

    static wave() {
      return new EnumParameter(TestParams.wave, "wave", ["saw", "sin"], 0);
    }
  }
}

/// Example to safely convert typed <-> type-erased parameters.
unittest {
  Parameter[] ps = buildParams!TestParams;
  // Access parameters via builder definitions.
  const IntegerParameter i = typedParam!(TestParams.volume)(ps);
  assert(i !is null);
  const EnumParameter e = typedParam!(TestParams.wave)(ps);
  assert(e !is null);
}
