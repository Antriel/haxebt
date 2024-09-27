package haxebt.macros;

import haxe.macro.Expr;

using haxe.macro.Context;

class ForestParser {

    public static macro function build():Array<Field> {
        return new ForestParser().fields;
    }

    final fields:Array<Field>;
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
                    addBehavior(e);
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

    function addBehavior(e:Expr):Array<Expr> {
        final args = [
            macro forest,
            macro $v{behaviors.length},
            macro haxebt.BehaviorNodeId.NONE,
            macro haxebt.BehaviorNodeId.NONE
        ];
        final beh = switch e.expr {
            // TODO support dot paths too. (Wait, is that valid syntax?)
            case EConst(CIdent(name)):
                { expr: ENew({ name: name, pack: [] }, args), children: [], name: name };
            case ECall({ expr: EConst(CIdent(name)) }, params):
                var childrenExpr = params[1];
                switch params[0] {
                    case null | { expr: EBlock([]) }: // Empty config. Ignore.
                    case { expr: EObjectDecl(_) }: args.push(params[0]); // Config object, pass it through.
                    case e: // Assuming it's children.
                        if (childrenExpr != null)
                            Context.error('Unexpected second argument (assuming first argument "${e.expr.getName()}" are children', params[1].pos);
                        childrenExpr = e;
                }
                final children = switch childrenExpr {
                    case null: [];
                    case { expr: EArrayDecl(fields) }: fields;
                    case e: [e];
                }
                { expr: ENew({ name: name, pack: [] }, args), children: children, name: name };
            case ECall(e, params): Context.error('Expected identifier.', e.pos);
            case _: Context.error('Unhandled expr "${e.expr.getName()}".', e.pos);
        }
        behaviors.push({ expr: beh.expr, pos: e.pos });
        if (beh.children.length > 0) {
            args[3] = macro $v{behaviors.length}; // Set next behavior as child of this one.
            var prev = null;
            for (child in beh.children) {
                var siblingId = behaviors.length;
                var next = addBehavior(child);
                if (prev != null) prev[2] = macro $v{siblingId};
                prev = next;
            }
        }
        try switch Context.getType(beh.name) {
            case TInst(t, params):
                var meta = Lambda.find(t.get().meta.get(), m -> m.name == ':behavior');
                final behaviorType = switch meta {
                    case { params: [{ expr: EConst(CString(s)) }] }:
                        switch s {
                            case "composite": Composite;
                            case "decorator": Decorator;
                            case "action": Action;
                            case _: Context.error('Invalid behavior type $s.', meta.pos);
                        }
                    case null: Action;
                    case _: Context.error('Invalid behavior type value.', meta.pos);
                }
                behaviorType.check(beh.children.length, beh.name, e.pos);
            case _: Context.error('Expected TInst.', e.pos);
        } catch (_) Context.error('Unknown Behavior ${beh.name}.', e.pos);
        return args;
    }

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
