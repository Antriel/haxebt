package haxebt;

abstract BehaviorNodeId(Int) from Int to Int {

    public static inline var NONE = -1;

    public inline function valid() return this >= 0;

}
