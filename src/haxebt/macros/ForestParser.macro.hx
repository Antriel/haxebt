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
        inline function parsePath(e:Expr):Array<String> {
            final path = [];
            function parse(e:Expr) switch e.expr {
                case EConst(CIdent(s)): path.unshift(s);
                case EField(e, field):
                    path.unshift(field);
                    parse(e);
                case _: Context.error('Unhandled expr "${e.expr.getName()}".', e.pos);
            }
            parse(e);
            return path;
        }
        final beh = switch e.expr {
            case EConst(CIdent(name)): { path: [name], children: [] };
            case ECall(e, params):
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
                { path: parsePath(e), children: children };
            case EField(e, name): { path: parsePath(e).concat([name]), children: [] };
            case _: Context.error('Unhandled expr "${e.expr.getName()}".', e.pos);
        }
        final upperIndex = Lambda.findIndex(beh.path, s -> s.charCodeAt(0) < 91);
        behaviors.push({
            expr: ENew({
                name: beh.path[upperIndex],
                pack: beh.path.slice(0, upperIndex),
                sub: beh.path[upperIndex + 1],
            }, args),
            pos: e.pos
        });
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
        try switch Context.getType(beh.path.join('.')) {
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
                behaviorType.check(beh.children.length, e.pos);
            case _: Context.error('Expected TInst.', e.pos);
        } catch (_) Context.error('Unknown Behavior ${beh.path.join('.')}.', e.pos);
        return args;
    }

}

enum abstract BehaviorType(String) {

    var Action = "action";
    var Composite = "composite";
    var Decorator = "decorator";

    public inline function check(count:Int, pos:Position) {
        switch (cast this:BehaviorType) {
            case Action if (count != 0):
                Context.fatalError('Action cannot have children. Got $count.', pos);
            case Decorator if (count != 1):
                Context.fatalError('Decorator expects exactly 1 child. Got $count.', pos);
            case Composite if (count == 0):
                Context.fatalError('Composite expects at least 1 children. Got $count.', pos);
            case _:
        }
    }

}
