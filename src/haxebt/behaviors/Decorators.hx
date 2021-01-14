package ai.behaviors;

@:behavior("decorator")
class UntilFail<T> extends Behavior<T> {
    
    function execute() {
        return switch(runOther(forest[child])) {
            case Failure: Success;
            case _: Running;
        }
    }
    
}

@:behavior("decorator")
class UntilSuccess<T> extends Behavior<T> {
    
    function execute() {
        return switch(runOther(forest[child])) {
            case Success: Success;
            case _: Running;
        }
    }
    
}

@:behavior("decorator")
class AlwaysSucceed<T> extends Behavior<T> {
    
    function execute() {
        runOther(forest[child]);
        return Success;
    }
    
}

@:behavior("decorator")
class AlwaysFail<T> extends Behavior<T> {
    
    function execute() {
        runOther(forest[child]);
        return Failure;
    }
    
}
