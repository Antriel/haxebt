package haxebt;

#if macro
import haxe.macro.ComplexTypeTools;
import haxe.macro.Context;
import haxe.macro.Expr.Field;
import haxe.macro.Expr;
import tink.hxx.Node;
import tink.hxx.Parser;
import tink.hxx.StringAt;

using haxe.macro.Context;
#end

class ForestParser {

    public static macro function build():Array<Field> {
        Context.registerModuleDependency('haxebt.ForestParser', "src/haxebt/BehaviorBuilder.hx");
        return new ForestParser().fields;
    }

    #if macro
    static final parserConfig:tink.hxx.Parser.ParserConfig = {
        defaultExtension: 'hxx',
        noControlStructures: true,
        defaultSwitchTarget: macro __data__,
        isVoid: function(_) return false,
        treatNested: function(children) {
            Context.error('Nested? ' + children, children.pos);
            return null;
        }
    }

    final fields:Array<Field>;
    var behaviors:Array<Expr> = [];
    var configCache:Map<String, BehaviorConfig> = new Map();

    function new() {
        var args = [];
        var refs = [];
        for (f in Context.getBuildFields()) {
            switch f.kind {
                case FVar(t, e):
                    if (e != null) {
                        refs.push({
                            id: behaviors.length,
                            name: f.name,
                            pos: f.pos
                        });
                        var source = ParserSource.ofExpr(e);
                        var rgx = ~/\/\/.*$|\/\*[\S\s]*?\*\//gm; // Remove comments.
                        var str = rgx.map(source.source.string, match -> [for (_ in 0...match.matched(0).length) " "].join(""));
                        @:privateAccess source.source.string = str;
                        function create(source:ParserSource):Parser @:privateAccess return new Parser(source, create, parserConfig);
                        var nodes = create(source).parseRootNode();
                        createBehavior(nodes.value[0]);
                    } else {
                        args.push({ name: f.name, type: t });
                    }
                case _:
                    Context.warning('Unhandled field kind.', f.pos);
            }
        }
        // trace(new haxe.macro.Printer().printExpr(macro $b{behaviors}));

        behaviors = behaviors.map(e -> macro forest.push($e));

        fields = [
            {
                name: 'build',
                pos: Context.currentPos(),
                access: [APublic, AStatic],
                kind: FFun({
                    args: args,
                    params: [{ name: 'T' }],
                    ret: macro:haxebt.BehaviorForest<T>,
                    expr: macro {
                        var forest = [];
                        $b{behaviors};
                        return cast forest;
                    }
                })
            }
        ];
        var mapInitArrExpr = [];
        for (ref in refs) {
            fields.push({
                name: ref.name,
                pos: ref.pos,
                kind: FVar(macro:haxebt.BehaviorForest.BehaviorNodeID, macro $v{ref.id}),
                access: [APublic, AStatic, AInline]
            });
            mapInitArrExpr.push(macro $v{ref.name.toLowerCase()} => $v{ref.id});
        }
        fields.push({
            name: 'treeMap',
            pos: Context.currentPos(),
            kind: FVar(macro:Map<String, haxebt.BehaviorForest.BehaviorNodeID>, macro $a{mapInitArrExpr}),
            access: [AFinal, APrivate, AStatic]
        });
        fields.push({
            name: 'getByName',
            pos: Context.currentPos(),
            kind: FFun({
                args: [{ name: 'name', type: macro:String }],
                ret: macro:haxebt.BehaviorForest.BehaviorNodeID,
                expr: macro return treeMap.get(name)
            }),
            access: [APublic, AStatic, AInline]
        });
    }

    function createBehavior(root:Child):Expr {
        switch root.value {
            case CNode(node):
                var atts = [];
                for (att in node.attributes) {
                    switch att {
                        case Regular(name, value):
                            atts.push({ name: name, expr: value });
                        case Empty(name):
                            atts.push({ name: name, expr: macro true });
                        case _: Context.error('Unhandled attribute `$att`.', root.pos);
                    }
                }

                var childrenCount = node.children == null ? 0 : Lambda.count(node.children.value, c -> switch c.value {
                    case CNode(_): true;
                    case _: false;
                });
                var inst:Expr = getInstanceExpr(node.name, atts, childrenCount);
                behaviors.push(inst);
                // trace(new haxe.macro.Printer().printExpr(macro $b{behaviors}));
                if (node.children != null) {
                    setArg(inst, 3, macro $v{behaviors.length});
                    var prev = null;
                    for (child in node.children.value) {
                        var siblingId = behaviors.length;
                        var next = createBehavior(child);
                        if (prev != null && next != null) {
                            setArg(prev, 2, macro $v{siblingId});
                        }
                        if (next == null) continue;
                        prev = next;
                    }
                }
                return inst;
            case CText(text):
                var trimmed = StringTools.trim(text.value);
                var ignore = trimmed == '' || (StringTools.startsWith(trimmed, '//') && trimmed.indexOf('\n') == -1);
                if (!ignore) {
                    Context.error('Unhandled CText node: ' + text.value, text.pos);
                }
            case a:
                Context.error('Unhandled node type: $a', root.pos);
        }
        return null;
    }

    function getInstanceExpr(name:StringAt, atts:Array<{name:StringAt, expr:Expr}>, childrenCount:Int):Expr {
        var params = [
            macro forest,
            macro $v{behaviors.length},
            macro haxebt.BehaviorForest.BehaviorNodeID.NONE,
            macro haxebt.BehaviorForest.BehaviorNodeID.NONE
        ];
        var expr:Expr = {
            pos: Context.currentPos(),
            expr: ENew({ name: name.value, pack: [] }, params)
        };

        var missing = [];
        var config = getBehaviorConfig(name);
        config.behaviorType.check(childrenCount, name);

        for (c in config.configs) {
            if (atts.length == 0) break;
            var att = findAndRemove(atts, a -> a.name.value == c.name);
            if (att != null) {
                params.push(att.expr);
            } else {
                if (c.optional) {
                    params.push(macro null);
                } else {
                    missing.push(c.name);
                }
            }
        }

        for (att in atts) {
            var closest = null;
            var dist = 0;
            for (c in config.configs) {
                var d = levenshtein(c.name, att.name.value);
                if (closest == null || dist > d) {
                    closest = c.name;
                    dist = d;
                }
            }
            if (closest != null) {
                Context.warning('Unknown attribute, did you mean `$closest`?', att.name.pos);
            } else Context.warning('Unknown attribute.', att.name.pos);
        }

        if (missing.length > 0) {
            var many = missing.length > 1;
            var args = missing.map(n -> '`$n`').join(', ');
            Context.error('Missing attribute${many ? 's' : ''} $args ${many ? 'are' : 'is'} required for `${name.value}`.', name.pos);
        }

        return expr;
    }

    function setArg(inst:Expr, argIndex:Int, expr:Expr):Void {
        switch inst.expr {
            case ENew(_, params):
                params[argIndex] = expr;
            case _:
                Context.error("Expected ENew", Context.currentPos());
        }
    }

    function findAndRemove<T>(arr:Array<T>, check:T->Bool):T {
        for (i in 0...arr.length) {
            if (check(arr[i])) {
                return arr.splice(i, 1)[0];
            }
        }
        return null;
    }

    function getBehaviorConfig(nameAt:StringAt) {
        var name = nameAt.value;
        if (configCache.exists(name)) return configCache.get(name);
        var configs = [];
        var behaviorType = Action;
        try {
            switch Context.getType(name) {
                case TInst(t, params):
                    var meta = Lambda.find(t.get().meta.get(), m -> m.name == ':behavior');
                    switch meta {
                        case { params: [{ expr: EConst(CString(s)) }] }:
                            switch s {
                                case "composite": behaviorType = Composite;
                                case "decorator": behaviorType = Decorator;
                                case "action": behaviorType = Action;
                                case _: Context.error('Invalid behavior type $s.', meta.pos);
                            }
                        case null: // default is action
                        case _: Context.error('Invalid behavior type value.', meta.pos);
                    }
                    var pos = t.get().pos;
                    var file = pos.getPosInfos().file;
                    Context.registerModuleDependency('haxebt.ForestParser', file);
                    var fields = t.get().fields.get();
                    for (f in fields) {
                        if (f.isFinal) switch f.kind {
                            case FVar(AccNormal, AccCtor):
                                configs.push({ name: f.name, optional: f.meta.has(':optional') });
                            case _:
                        }
                    }
                case _:
            }
        } catch (e:Dynamic) {
            Context.error('Unknown Behavior ${nameAt.value}.', nameAt.pos);
            return null;
        }
        configs.sort((a, b) -> BehaviorBuilder.sortConfig(a.name, b.name, a.optional, b.optional));
        var behaviorConfig = { behaviorType: behaviorType, configs: configs };
        configCache.set(name, behaviorConfig);
        return behaviorConfig;
    }

    static function levenshtein(s1:String, s2:String):Int {
        final len1 = s1.length, len2 = s2.length;
        var d:Array<Array<Int>> = [for (i in 0...len1 + 1) new Array()];

        d[0][0] = 0;

        for (i in 1...len1 + 1) d[i][0] = i;
        for (i in 1...len2 + 1) d[0][i] = i;

        for (i in 1...len1 + 1)
            for (j in 1...len2 + 1)
                d[i][j] = cast Math.min(Math.min(d[i - 1][j] + 1, d[i][j - 1] + 1),
                    d[i - 1][j - 1] + (s1.charAt(i - 1) == s2.charAt(j - 1) ? 0 : 1));
        return (d[len1][len2]);
    }
    #end

}

#if macro
typedef BehaviorConfig = {

    behaviorType:BehaviorType,
    configs:Array<{name:String, optional:Bool}>

}

enum abstract BehaviorType(String) {

    var Action = "action";
    var Composite = "composite";
    var Decorator = "decorator";

    public inline function check(count:Int, name:StringAt) {
        switch (cast this:BehaviorType) {
            case Action if (count != 0):
                Context.fatalError('Action ${name.value} cannot have children. Got $count.', name.pos);
            case Decorator if (count != 1):
                Context.fatalError('Decorator ${name.value} expects exactly 1 child. Got $count.', name.pos);
            case Composite if (count == 0):
                Context.fatalError('Composite ${name.value} expects at least 1 children. Got $count.', name.pos);
            case _:
        }
    }

}
#end
