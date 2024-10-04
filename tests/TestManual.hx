import Common;
import haxebt.BehaviorForest;
import haxebt.behaviors.Behavior;
import haxebt.behaviors.Composites;
import utest.Assert;
import utest.Test;

class TestManual extends Test {

    public function testSimple() {
        var e = { life: 3 };
        var forest:BehaviorForest<LifeEntity, {a:Int, b:String}> = [];
        forest.push(new DecLife(forest, null, 1, 2, -1));
        forest[0].run(null, e);
        Assert.equals(2, e.life);
    }

    public function testSimpleSequence() {
        var e = { life: 3 };
        var forest:BehaviorForest<LifeEntity, {b:String}> = [];
        forest.push(new Sequence(forest, null, 0, -1, 1));
        forest.push(new DecLife(forest, null, 1, 2, -1, { once: true }));
        forest.push(new DecLife(forest, null, 2, -1, -1, { once: true }));
        var res = null;
        do {
            res = forest[0].run([], e);
        } while (res != Success);
        Assert.equals(1, e.life);
    }

}
