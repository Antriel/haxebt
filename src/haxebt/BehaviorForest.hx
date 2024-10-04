package haxebt;

import haxebt.behaviors.Behavior;

@:forward(push)
abstract BehaviorForest<E, W>(Array<Behavior<E, W>>) from Array<Behavior<E, W>> to Array<Behavior<E, W>> { }
