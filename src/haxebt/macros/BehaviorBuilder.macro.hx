package haxebt.macros;

import haxe.macro.Expr;
import haxe.macro.ExprTools;
import haxe.macro.Type;
import haxe.macro.TypeTools;

using haxe.macro.ComplexTypeTools;
using haxe.macro.Context;

class BehaviorBuilder {

    public static macro function build():Array<Field> {
        var fields = Context.getBuildFields();
        var i = fields.length - 1;
        var localClass = Context.getLocalClass().get();
        var classModule = localClass.module;
        var entityType = localClass.superClass.params[0];
        var toInit = [];
        while (i >= 0) {
            var field = fields[i];
            switch (field) {
                case { name: 'execute', kind: FieldType.FFun(f), pos: pos }:
                    fields[i] = buildRun(f, entityType, pos);
                case { name: 'run', pos: pos }:
                    Context.error('Behavior should not implement `run` directly. Implement `execute` instead', pos);
                case { name: name, kind: FVar(t, e), access: [AFinal] }:
                    if (e != null) { // remove the default val, otherwise constructor will assign it twice
                        field.kind = FVar(t, null);
                        field.meta.push({ name: ':optional', pos: field.pos });
                    }
                    toInit.push({ name: name, type: t, def: e });
                case _:
            }
            i--;
        }

        if (toInit.length > 0) {
            toInit.sort((a, b) -> sortConfig(a.name, b.name, a.def != null, b.def != null));
            var args:Array<FunctionArg> = BehaviorBuilder.behaviorBaseArgs.copy();
            var exprs = [];
            exprs.push(macro super(forest, id, sibling, child));
            for (init in toInit) {
                args.push({
                    name: init.name,
                    opt: init.def != null,
                    type: init.type,
                    value: init.def
                });
                var n = init.name;
                exprs.push(macro this.$n = $i{n});
            }
            fields.push({
                pos: Context.currentPos(),
                name: 'new',
                access: [APublic],
                kind: FFun({ ret: null, args: args, expr: { pos: Context.currentPos(), expr: EBlock(exprs) } })
            });
        }
        #if haxebt.debug
        var params = [for (init in toInit) {
            var init_name = init.name;
            macro {
                name: $v{init_name},
                value: Std.string(this.$init_name)
            };
        }];
        var infoExpr = macro return {
            id: this.id,
            child: this.child,
            sibling: this.sibling,
            name: $v{localClass.name},
            params: $a{params}
        }
        fields.push({
            pos: Context.currentPos(),
            name: 'getInfo',
            access: [APublic, AOverride],
            meta: [{ name: ':keep', pos: Context.currentPos() }],
            kind: FFun({ ret: null, args: [], expr: infoExpr })
        });
        #end
        return fields;
    }

    public static inline function sortConfig(aName:String, bName:String, aOpt:Bool, bOpt:Bool) {
        if (!aOpt && bOpt) return -1;
        else if (!bOpt && aOpt) return 1;
        else return aName > bName ? 1 : -1;
    }

    public static var behaviorBaseArgs:Array<FunctionArg> = [
        { name: 'forest', type: null },
        { name: 'id', type: macro :haxebt.BehaviorNodeId },
        { name: 'sibling', type: macro :haxebt.BehaviorNodeId },
        { name: 'child', type: macro :haxebt.BehaviorNodeId }
    ];

    static var entityArgName:String = 'entity';

    private static function buildRun(execute:Function, entityType:Type, pos:Position):Field {
        var expr = execute.expr;
        var dataInit = macro { };
        if (execute.args.length > 2)
            Context.error('Unexpected amount of arguments, use data and/or entity, no more.', pos);
        var dataArg = null;
        for (arg in execute.args) {
            if (arg.type != null && TypeTools.unify(arg.type.toType(), entityType)) { // is the entity type
                entityArgName = arg.name;
            } else { // data required
                dataArg = arg;
            }
        }
        if (dataArg != null) { // now entityArgName is available, we can fill init
            var type = dataArg.type;
            if (type == null) {
                type = getInitType();
            }
            dataInit = getDataInit(dataArg.name, type, pos);
        }
        expr = ExprTools.map(expr, replaceRunOther);
        expr = ExprTools.map(expr, replaceClearData);
        expr = ExprTools.map(expr, replaceDeltaTime);
        #if haxebt.debug
        expr = ExprTools.map(expr, addDebugToReturn);
        #end
        // expr = ExprTools.map(expr, addClearToReturn);
        // TODO ^ performance blocked by https://github.com/HaxeFoundation/haxe/issues/7934
        // let's enable it once it won't cause extra overhead

        // trace(new haxe.macro.Printer().printExpr(dataInit));
        // trace(new haxe.macro.Printer().printExpr(expr));
        // var debugExpr = macro trace('Entering '+id);
        #if haxebt.debug
        var debugExpr = macro haxebt.behaviors.Behavior.onEnter(this.id, $i{entityArgName});
        #else
        var debugExpr = macro { };
        #end
        return {
            name: 'run',
            access: [AOverride, APublic],
            kind: FFun({
                args: [
                    { name: 'storage', type: macro :Map<haxebt.BehaviorNodeId, Dynamic> },
                    { name: entityArgName, type: entityType.toComplexType() },
                    { name: 'dt', type: macro :Float }
                ],
                ret: macro :haxebt.behaviors.Behavior.BehaviorResult,
                // expr: tink.MacroApi.Exprs.concat(tink.MacroApi.Exprs.concat(debugExpr, dataInit), expr)
                expr: macro @:mergeBlock {
                    @:mergeBlock $debugExpr;
                    @:mergeBlock $dataInit;
                    @:mergeBlock
                    $expr;
                }
            }),
            pos: pos
        }
    }

    private static function getDataInit(dataName:String, dataType:ComplexType, pos:Position):Expr {
        if (!Lambda.exists(Context.getBuildFields(), field -> switch (field) {
            case { name: 'init', kind: FieldType.FFun(_) }: true;
            case _: false;
        })) Context.error('Behavior requests data but does not provide init method.', pos);
        if (dataType == null) dataType = macro :Dynamic;
        var initField = Lambda.find(Context.getBuildFields(), (f) -> return f.name == 'init');
        var wantsEntity = initField != null && switch (initField.kind) {
            case FFun({ args: args }): args.length == 1;
            case _: false;
        };
        var initCall:Expr = wantsEntity ? (macro init($i{entityArgName})) : (macro init());
        return macro {
            var $dataName:$dataType = storage.get(id);
            if ($i{dataName} == null) {
                $i{dataName} = inline
                $initCall;
                storage.set(id, $i{dataName});
            }
        };
    }

    private static function replaceRunOther(e:Expr):Expr {
        return switch (e.expr) {
            case ECall({ expr: EConst(CIdent('runOther')) }, params):
                macro ${params[0]}.run(storage, $i{entityArgName}, dt);
            case _: ExprTools.map(e, replaceRunOther);
        }
    }

    private static function replaceClearData(e:Expr):Expr {
        return switch (e.expr) {
            case ECall({ expr: EConst(CIdent('clearData')) }, params):
                macro storage.remove(this.id);
            case _: ExprTools.map(e, replaceClearData);
        }
    }

    private static function replaceDeltaTime(e:Expr):Expr {
        return switch (e.expr) {
            case ECall({ expr: EConst(CIdent('deltaTime')) }, params):
                macro dt;
            case _: ExprTools.map(e, replaceDeltaTime);
        }
    }

    private static function addDebugToReturn(e:Expr):Expr {
        return switch (e.expr) {
            case EReturn(e):
                macro @:mergeBlock {
                    final result:haxebt.behaviors.Behavior.BehaviorResult = $e;
                    haxebt.behaviors.Behavior.onExit(this.id, result, $i{entityArgName});
                    return result;
                }
            case _: ExprTools.map(e, addDebugToReturn);
        }
    }

    private static function addClearToReturn(e:Expr):Expr {
        return switch (e.expr) {
            case EReturn(e):
                macro @:mergeBlock {
                    final result:haxebt.behaviors.Behavior.BehaviorResult = $e;
                    if (result != haxebt.behaviors.Behavior.BehaviorResult.Running) {
                        storage.remove(this.id);
                    }
                    return result;
                }
            case _: ExprTools.map(e, addClearToReturn);
        }
    }

    private static function getInitType():ComplexType {
        // this could use a lot of improvements
        // but they proved quite tricky
        for (field in Context.getBuildFields()) {
            if (field.name == 'init') return switch (field.kind) {
                case FFun({ ret: ret, expr: e }): {
                        if (ret == null) {
                            return switch (e.expr) {
                                case EReturn(e):
                                    Context.typeof(e).toComplexType();
                                case _: null;
                            }
                        } else ret;
                    }
                case _: return null;
            }
        }
        return null;
    }

}
