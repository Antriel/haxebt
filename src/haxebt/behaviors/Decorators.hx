package haxebt.behaviors;

@:behavior("decorator")
class UntilFail<E, W> extends Behavior<E, W> {

    function execute() {
        return switch runOther(forest[child]) {
            case Failure: Success;
            case _: Running;
        }
    }

}

@:behavior("decorator")
class UntilSuccess<E, W> extends Behavior<E, W> {

    function execute() {
        return switch runOther(forest[child]) {
            case Success: Success;
            case _: Running;
        }
    }

}

@:behavior("decorator")
class AlwaysSucceed<E, W> extends Behavior<E, W> {

    function execute() {
        runOther(forest[child]);
        return Success;
    }

}

@:behavior("decorator")
class AlwaysFail<E, W> extends Behavior<E, W> {

    function execute() {
        runOther(forest[child]);
        return Failure;
    }

}
