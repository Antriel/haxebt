import haxebt.behaviors.Behavior;

typedef LifeEntity = {life:Int};

class DecLife extends Behavior<LifeEntity> {

    final once:Bool = false;

    function execute(entity:LifeEntity) {
        if (--entity.life <= 0 || once) {
            return Success;
        } else {
            return Running;
        }
    }

}

class SetLife extends Behavior<LifeEntity> {

    final life:Int;

    function execute(entity:LifeEntity) {
        entity.life = life;
        return Success;
    }

}

@:behavior("composite") class CustomComposite<T> extends Behavior<T> {

    final index:Int;

    function init() {
        var i = index;
        var id = child;
        while (i-- > 0) id = forest[id].sibling;
        return id;
    }

    function execute(child) {
        return switch runOther(forest[child]) {
            case Running: Running;
            case res:
                clearData();
                res;
        }
    }

}
