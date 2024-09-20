package haxebt;

import haxebt.behaviors.Behavior;

@:forward(push)
abstract BehaviorForest<T>(Array<Behavior<T>>) from Array<Behavior<T>> to Array<Behavior<T>> { }
