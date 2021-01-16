import Common;
import haxebt.BehaviorForest;
import haxebt.behaviors.Behavior;
import haxebt.behaviors.Composites;
import utest.Assert;
import utest.Test;

class TestComments extends Test {

    public function testSingleLine() {
        var e = { life: 3 };
        var forest = SingleCommentForest.build();
        forest[0].run([], e, 0);
        Assert.equals(10, e.life);
    }

}

@:build(haxebt.ForestParser.build())
class SingleCommentForest {

    // @formatter:off
    public final SingleComment =
    <Sequence>
        // Hello
        //Comment
        //<NonExistingNode />
        <SetLife life={10} /> // <NonExistingNode />
        //<SetLife life={0} />
    </Sequence>
    // @formatter:on
}
