package tink.template;

import haxe.macro.Expr;

enum TplExpr {
  Const(value:String, pos:Position);
  Meta(data:Metadata, expr:TplExpr);
  Yield(e:Expr);
  Do(e:Expr);
  Var(a:Array<Var>);
  Define(name:String, value:TplExpr);
  If(cond:Expr, cons:TplExpr, ?alt:TplExpr);
  For(target:Expr, body:TplExpr, ?legacy:Bool);
  While(cond:Expr, body:TplExpr);
  Function(name:String, args:Array<FunctionArg>, body:TplExpr, ret:ComplexType);
  Switch(target:Expr, cases:Array<{ values:Array<Expr>, ?guard:Expr, expr: TplExpr }>);
  Block(exprs:Array<TplExpr>);
}

enum TplDecl {
  VanillaField(f:Field);
  TemplateField(f:Field, expr:TplExpr);
  SuperType(t:TypePath, isClass:Bool, pos:Position);
  Meta(m:Metadata);
  Import(path:String, mode:ImportMode, pos:Position);
  Using(path:String, pos:Position);
}