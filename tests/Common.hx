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

    @:keep final life:Int;

    function execute(entity:LifeEntity) {
        entity.life = life;
        return Success;
    }

}
