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
                final inst = getInstanceExpr(name, e.pos, null, 0);
                behaviors.push(inst);
                return inst;
            case ECall({ expr: EConst(CIdent(name)) }, params):
                var children:Array<Expr> = null;
                function exprToChildren(e:Expr) return switch e {
                    case null: [];
                    case { expr: EArrayDecl(fields) }: fields;
                    case e: [e];
                }
                final atts:Expr = switch params[0] {
                    case null: null;
                    case { expr: EObjectDecl(_) }: params[0];
                    case { expr: EBlock([]) }: null; // Empty config.
                    case e:
                        children = exprToChildren(e);
                        null;
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

    function getInstanceExpr(name:String, pos:Position, configArg:Expr, childrenCount:Int):Expr {
        var params = [
            macro forest,
            macro $v{behaviors.length},
            macro haxebt.BehaviorNodeId.NONE,
            macro haxebt.BehaviorNodeId.NONE
        ];
        if (configArg != null) params.push(configArg);
        var expr:Expr = {
            pos: pos,
            expr: ENew({ name: name, pack: [] }, params)
        };

        var config = getBehaviorConfig(name, pos);
        config.behaviorType.check(childrenCount, name, pos);

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
        var behaviorConfig = { behaviorType: behaviorType, configs: configs };
        configCache.set(name, behaviorConfig);
        return behaviorConfig;
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
