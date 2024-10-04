import haxebt.IForest;
import haxebt.behaviors.Behavior;
import utest.Assert;
import utest.Test;

class TestWorldAccess extends Test {

    public function testSimple() {
        var e = { v: 0 };
        var forest = OtherForest.build({ value: 100 });
        forest[OtherForest.Test].run([], e);
        Assert.equals(100, e.v);
    }

    public function testForestConfig() {
        var e = { v: 0 };
        var forest = ConfigurableForest.build(null, 99);
        var forest2 = ConfigurableForest.build(null, 49);
        forest[OtherForest.Test].run([], e);
        Assert.equals(99, e.v);
        forest2[OtherForest.Test].run([], e);
        Assert.equals(49, e.v);
        forest[OtherForest.Test].run([], e);
        Assert.equals(99, e.v);
    }

}

class ConfigurableForest implements IForest {

    final someConst:Int;

    public static var Test = UseConst({ value: someConst });

}

class OtherForest implements IForest {

    public static var Test = AccessWorld;

}

class AccessWorld extends Behavior<{v:Int}, {value:Int}> {

    function execute(o:{v:Int}) {
        o.v = world.value;
        return Success;
    }

}

class UseConst<W> extends Behavior<{v:Int}, W> {

    final value:Int;

    function execute(o:{v:Int}) {
        o.v = value;
        return Success;
    }

}
