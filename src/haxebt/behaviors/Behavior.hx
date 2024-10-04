package haxebt.behaviors;

import haxebt.BehaviorForest;
import haxebt.BehaviorNodeId;

@:autoBuild(haxebt.macros.BehaviorBuilder.build())
abstract class Behavior<E, W> {

    public final forest:BehaviorForest<E, W>;
    public final world:W;
    public final id:BehaviorNodeId;
    public final child:BehaviorNodeId;
    public final sibling:BehaviorNodeId;

    public function new(forest:BehaviorForest<E, W>, world:W, id:BehaviorNodeId, sibling:BehaviorNodeId,
            child:BehaviorNodeId) {
        this.forest = forest;
        this.world = world;
        this.id = id;
        this.sibling = sibling;
        this.child = child;
    }

    public abstract function run(storage:Map<BehaviorNodeId, Dynamic>, entity:E):BehaviorResult;

    @:dce function runOther(b:Behavior<E, W>):BehaviorResult throw "Shouldn't actually get called.";

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
