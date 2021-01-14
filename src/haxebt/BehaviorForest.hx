package haxebt;

import haxebt.behaviors.Behavior;

@:forward(push)
abstract BehaviorForest<T>(Array<Behavior<T>>) from Array<Behavior<T>> to Array<Behavior<T>> {
    
}

abstract BehaviorNodeID(Int) from Int to Int {
    
    public static inline var NONE = -1;
    
    public inline function valid() return this >= 0;
    
}
