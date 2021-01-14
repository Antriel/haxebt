import Common;
import haxebt.BehaviorForest;
import haxebt.behaviors.Behavior;
import haxebt.behaviors.Composites;
import utest.Assert;
import utest.Test;

class TestManual extends Test {

    public function testSimple() {
        var e = { life: 3 };
        var forest:BehaviorForest<LifeEntity> = [];
        forest.push(new DecLife(forest, 1, 2, -1));
        forest[0].run(null, e, 0);
        Assert.equals(2, e.life);
    }

    public function testSimpleSequence() {
        var e = { life: 3 };
        var forest:BehaviorForest<LifeEntity> = [];
        forest.push(new Sequence(forest, 0, -1, 1));
        forest.push(new DecLife(forest, 1, 2, -1, true));
        forest.push(new DecLife(forest, 2, -1, -1, true));
        var res = null;
        do {
            res = forest[0].run([], e, 0);
        } while (res != Success);
        Assert.equals(1, e.life);
    }

}
