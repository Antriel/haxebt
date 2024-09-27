package haxebt.behaviors;

import haxebt.BehaviorNodeId;

@:autoBuild(haxebt.macros.BehaviorBuilder.build())
abstract class Behavior<T> {

    public final forest:BehaviorForest<T>;
    public final id:BehaviorNodeId;
    public final child:BehaviorNodeId;
    public final sibling:BehaviorNodeId;

    public function new(forest:BehaviorForest<T>, id:BehaviorNodeId, sibling:BehaviorNodeId,
            child:BehaviorNodeId) {
        this.forest = forest;
        this.id = id;
        this.sibling = sibling;
        this.child = child;
    }

    public abstract function run(storage:Map<BehaviorNodeId, Dynamic>, entity:T):BehaviorResult;

    @:dce function runOther(b:Behavior<T>):BehaviorResult throw "Shouldn't actually get called.";

    @:dce function clearData():Void throw "Shouldn't actually get called.";

    #if haxebt.debug
    public function getInfo():Dynamic return null;

    public static var onEnter:BehaviorNodeId->Dynamic->Void = (_, _) -> {};
    public static var onExit:BehaviorNodeId->BehaviorResult->Dynamic->Void = (_, _, _) -> {};
    #end

}

enum BehaviorResult {

    Running;
    Success;
    Failure;

}
