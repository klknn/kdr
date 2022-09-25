/// Parameter utility.
module kdr.params;

import std.traits : getUDAs, EnumMembers;

import dplug.core.vec : makeVec, Vec;
import dplug.client.params; // : Parameter, EnumParameter;


/// UDA for registering builder struct of param enum.
struct registerBuilder(T) {
  alias Builder = T;
}

///
version (unittest) {
  @registerBuilder!TestParamBuilder
  enum TestParams {
    volume,
    wave,
  }

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

  IntegerParameter i = typedParam!(TestParams.volume)(ps);
  assert(i !is null);
  EnumParameter e = typedParam!(TestParams.wave)(ps);
  assert(e !is null);
}

/// Build a type-erased parameter slice of the given enum Params.
Parameter[] buildParams(Params)() {
  Vec!Parameter params = makeVec!Parameter(EnumMembers!Params.length);
  alias ParamBuilder = getUDAs!(Params, registerBuilder)[0].Builder;
  static foreach (i, pname; __traits(allMembers, Params)) {
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
  alias ParamBuilder = getUDAs!(Params, registerBuilder)[0].Builder;
  static immutable paramNames = [__traits(allMembers, Params)];
  alias T = typeof(__traits(getMember, ParamBuilder, paramNames[pid])());
  auto ret = cast(T) params[pid];
  assert(ret !is null);
  return ret;
}
