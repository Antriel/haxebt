package haxebt.behaviors;

import haxebt.BehaviorForest.BehaviorNodeID;

@:autoBuild(haxebt.BehaviorBuilder.build())
class Behavior<T> {
    
    public final forest:BehaviorForest<T>;
    public final id:BehaviorNodeID;
    public final child:BehaviorNodeID;
    public final sibling:BehaviorNodeID;
    
    public function new(forest:BehaviorForest<T>, id:BehaviorNodeID, sibling:BehaviorNodeID, child:BehaviorNodeID) {
        this.forest = forest;
        this.id = id;
        this.sibling = sibling;
        this.child = child;
    }
    
    public function run(storage:Map<BehaviorNodeID, Dynamic>, entity:T, deltaTime:Float):BehaviorResult {
        throw "Abstract class.";
    }
    
    @:dce function runOther(b:Behavior<T>):BehaviorResult throw "Shouldn't actually get called.";
    @:dce function clearData():Void throw "Shouldn't actually get called.";
    @:dce function deltaTime():Float throw "Shouldn't actually get called.";
    
    #if ai_debug
    public function getInfo():Dynamic return null;
    #end
    
}

enum BehaviorResult {
    Running;
    Success;
    Failure;
}
