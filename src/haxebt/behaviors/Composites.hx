package haxebt.behaviors;

import haxebt.BehaviorNodeId;

@:behavior("composite")
class Sequence<T> extends Behavior<T> {

    function init():ChildData {
        return {
            child: this.child
        }
    }

    function execute(data) {
        while (true) {
            var child = forest[data.child];
            var status = runOther(child);
            switch status {
                case Success:
                    if (child.sibling.valid()) {
                        data.child = child.sibling;
                    } else {
                        clearData();
                        return Success; // TODO repeat mechanism?
                    }
                case Failure:
                    clearData();
                    return Failure;
                case Running:
                    return Running;
            }
        }
    }

}

typedef ChildData = {

    child:BehaviorNodeId

}

@:behavior("composite")
class Selector<T> extends Behavior<T> {

    function init():ChildData {
        return {
            child: this.child
        }
    }

    function execute(data) {
        while (true) {
            var child = forest[data.child];
            var status = runOther(child);
            switch status {
                case Success:
                    clearData();
                    return Success;
                case Failure:
                    if (child.sibling.valid()) {
                        data.child = child.sibling;
                    } else {
                        clearData();
                        return Failure;
                    }
                case Running:
                    return Running;
            }
        }
    }

}

@:behavior("composite")
class Parallel<T> extends Behavior<T> {

    function execute() {
        var child = forest[this.child];
        var allSuccess = true;
        while (true) {
            var status = runOther(child);
            switch status {
                case Failure:
                    return Failure;
                case Running:
                    allSuccess = false;
                case _:
            }
            if (child.sibling.valid()) {
                child = forest[child.sibling];
            } else {
                return allSuccess ? Success : Running;
            }
        }
    }

}

@:behavior("composite")
class RandomSelector<T> extends Behavior<T> {

    final weights:Array<Int> = null;

    function init() {
        var child = this.child;
        var children = [];
        var childWeights = [];
        var totalWeight = 0;
        var i = 0;
        while (child.valid()) {
            children.push(child);

            var weight = weights != null && weights.length > i ? weights[i] : 1;
            totalWeight += weight;
            childWeights.push(weight);

            child = forest[child].sibling;
            i++;
        }

        var randWeight = Math.ceil(Math.random() * totalWeight);

        child = this.child;
        i = 0;
        while (child.valid()) {
            randWeight -= childWeights[i++];
            if (randWeight <= 0) break;
            child = forest[child].sibling;
        }
        return child;
    }

    function execute(data) {
        var res = runOther(forest[data]);
        switch res {
            case Running:
                return Running;
            case _:
                clearData();
                return res;
        }
    }

}
