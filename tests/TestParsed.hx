import Common;
import haxebt.BehaviorForest;
import haxebt.behaviors.Behavior;
import haxebt.behaviors.Composites;
import utest.Assert;
import utest.Test;

class TestParsed extends Test {

    public function testSimple() {
        var e = { life: 3 };
        var forest = Forest.build(10);
        forest[Forest.Life].run([], e);
        Assert.equals(10, e.life);
        var res = null;
        do {
            res = forest[Forest.Death].run([], e);
        } while (res == Running);
        Assert.equals(0, e.life);
    }

    public function testOrder() {
        var e = { life: 3 };
        var forest = Forest.build(5);
        forest[Forest.Order].run([], e);
        Assert.equals(5, e.life);
    }

}

@:build(haxebt.macros.ForestParser.build())
class Forest {

    public static final initLife:Int;

    public static var Life = SetLife({ life: initLife });
    public static var Death = Sequence([
        DecLife
    ]);
    public static var Order = CustomComposite({ index: 1 }, [
        DecLife,
        SetLife({ life: 5 }),
        sub.Beh,
        sub.subber.Beh2({ }),
        sub.subber.Beh2.Beh3({ }),
        sub.subber.Beh2.Beh3,
    ]);

}
