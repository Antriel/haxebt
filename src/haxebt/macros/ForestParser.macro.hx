package haxebt.macros;

import haxe.macro.Expr;

using haxe.macro.Context;

class ForestParser {

    public static macro function build():Array<Field> {
        return new ForestParser().fields;
    }

    final fields:Array<Field>;
    final configCache:Map<String, BehaviorConfig> = new Map();
    final behaviors:Array<Expr> = [];

    function new() {
        final args = [];
        final refs = [];
        for (f in Context.getBuildFields()) {
            switch f.kind {
                case FVar(t, null):
                    args.push({ name: f.name, type: t });
                case FVar(t, e):
                    refs.push({
                        id: behaviors.length,
                        name: f.name,
                        pos: f.pos
                    });
                    createBehavior(e);
                case _:
                    Context.warning('Unhandled field kind.', f.pos);
            }
        }
        // trace(new haxe.macro.Printer().printExpr(macro $b{behaviors}));

        fields = [
            {
                name: 'build',
                pos: Context.currentPos(),
                access: [APublic, AStatic],
                kind: FFun({
                    args: args,
                    params: [{ name: 'T' }],
                    ret: macro :haxebt.BehaviorForest<T>,
                    expr: macro {
                        var forest = [];
                        $b{behaviors.map(e -> macro forest.push($e))};
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
                kind: FVar(macro :haxebt.BehaviorNodeId, macro $v{ref.id}),
                access: [APublic, AStatic, AInline]
            });
            mapInitArrExpr.push(macro $v{ref.name.toLowerCase()} => $v{ref.id});
        }
        fields.push({
            name: 'treeMap',
            pos: Context.currentPos(),
            kind: FVar(macro :Map<String, haxebt.BehaviorNodeId>, macro $a{mapInitArrExpr}),
            access: [AFinal, APrivate, AStatic]
        });
        fields.push({
            name: 'getByName',
            pos: Context.currentPos(),
            kind: FFun({
                args: [{ name: 'name', type: macro :String }],
                ret: macro :haxebt.BehaviorNodeId,
                expr: macro return treeMap.get(name)
            }),
            access: [APublic, AStatic, AInline]
        });
    }

    function createBehavior(e:Expr):Expr {
        switch e.expr {
            case EConst(CIdent(name)):
                final inst = getInstanceExpr(name, e.pos, [], 0);
                behaviors.push(inst);
                return inst;
            case ECall({ expr: EConst(CIdent(name)) }, params):
                var children:Array<Expr> = null;
                function exprToChildren(e:Expr) return switch e {
                    case null: [];
                    case { expr: EArrayDecl(fields) }: fields;
                    case e: [e];
                }
                final atts = switch params[0] {
                    case null: [];
                    case { expr: EObjectDecl(fields) }: fields.map(f -> {name: f.field, expr: f.expr });
                    case e:
                        children = exprToChildren(e);
                        [];
                }
                if (children != null && params.length > 1)
                    Context.error('Unexpected second argument (assuming first argument "${params[0].expr.getName()}" are children', params[1].pos);
                if (children == null) children = switch params[1] {
                    case null: [];
                    case { expr: EArrayDecl(fields) }: fields;
                    case e: [e];
                }
                final inst:Expr = getInstanceExpr(name, e.pos, atts, children.length);
                behaviors.push(inst);
                if (children.length > 0) {
                    setArg(inst, 3, macro $v{behaviors.length});
                    var prev = null;
                    for (child in children) {
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
            case ECall(e, params): Context.error('Expected identifier.', e.pos);
            case _: Context.error('Unhandled expr "${e.expr.getName()}".', e.pos);
        }
        return null;
    }

    function getInstanceExpr(name:String, pos:Position, atts:Array<{name:String, expr:Expr}>,
            childrenCount:Int):Expr {
        var params = [
            macro forest,
            macro $v{behaviors.length},
            macro haxebt.BehaviorNodeId.NONE,
            macro haxebt.BehaviorNodeId.NONE
        ];
        var expr:Expr = {
            pos: pos,
            expr: ENew({ name: name, pack: [] }, params)
        };

        var missing = [];
        var config = getBehaviorConfig(name, pos);
        config.behaviorType.check(childrenCount, name, pos);

        for (c in config.configs) {
            if (atts.length == 0) break;
            var att = findAndRemove(atts, a -> a.name == c.name);
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
                var d = levenshtein(c.name, att.name);
                if (closest == null || dist > d) {
                    closest = c.name;
                    dist = d;
                }
            }
            if (closest != null) {
                Context.warning('Unknown attribute, did you mean `$closest`?', pos);
            } else Context.warning('Unknown attribute.', pos);
        }

        if (missing.length > 0) {
            var many = missing.length > 1;
            var args = missing.map(n -> '`$n`').join(', ');
            Context.error('Missing attribute${many ? 's' : ''} $args ${many ? 'are' : 'is'} required for `${name}`.', pos);
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

    function getBehaviorConfig(name:String, pos:Position) {
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
            Context.error('Unknown Behavior $name.', pos);
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

}

typedef BehaviorConfig = {

    behaviorType:BehaviorType,
    configs:Array<{name:String, optional:Bool}>

}

enum abstract BehaviorType(String) {

    var Action = "action";
    var Composite = "composite";
    var Decorator = "decorator";

    public inline function check(count:Int, name:String, pos:Position) {
        switch (cast this:BehaviorType) {
            case Action if (count != 0):
                Context.fatalError('Action ${name} cannot have children. Got $count.', pos);
            case Decorator if (count != 1):
                Context.fatalError('Decorator ${name} expects exactly 1 child. Got $count.', pos);
            case Composite if (count == 0):
                Context.fatalError('Composite ${name} expects at least 1 children. Got $count.', pos);
            case _:
        }
    }

}
