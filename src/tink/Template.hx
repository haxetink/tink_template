package tink;

// #if !macro
// // @:autoBuild()
// interface Template {
	
// }
// #else

import haxe.macro.*;
import haxe.macro.Expr;
import tink.template.Parser;

using tink.MacroApi;
using sys.FileSystem;
using sys.io.File;
using StringTools;

class Template {
	static public function use() 
		Context.onTypeNotFound(getType);
	
	static function getType(name:String) {
		var tail = '/' + name.replace('.', '/')+'.tpl';
		for (path in Context.getClassPath()) {
			var file = path+tail;
			if (file.exists()) 
				return parse(file, name);
		}
		return null;
	}
	
	static function getPos(t:TExpr)
		return
			switch t {
				case Const(_, pos): pos;
				case For(e, _), If(e, _, _), Yield(e), Do(e): e.pos;
				case Var([]): Context.currentPos();
				case Block([]): Context.currentPos();
				case Var(a): a[0].expr.pos;
				case Function(_, _, t): getPos(t);
				case Block(a): getPos(a[0]);
			}	
	
	static public function generate(t:TExpr):Expr {
					
		var ret:Expr = 
			if (t == null) null;
			else switch t {
				case Const(value, pos):
					macro @:pos(pos) ret.add(tink.template.Html.fragment($v{value}));
				case Yield(e):
					macro @:pos(e.pos) ret.add($e);
				case Do(e):
					e;
				case Var(vars):
					EVars(vars).at();
				case If(cond, cons, alt):
					macro 
						if ($cond)
							${generate(cons)}
						else
							${generate(alt)};
				case For(target, body):
					macro @:pos(target.pos)
						for ($target) 
							${generate(body)};
				case Function(name, args, body):
					var body = macro {
						var ret = new tink.template.Html();
						${generate(body)};
						return ret.collapse();
					}
					body.func(args, false).asExpr(name);
				case Block(exprs):
					exprs.map(generate).toBlock();
			}
		
		return ret;
	}		
	
	static function parse(file:String, name:String):TypeDefinition {
		
		var source = file.getContent();
		var pos = Context.makePosition({ file: file, min: 0, max: source.length });
		
		pos.warning('Generating $name');
		
		var parts = 
			switch new Parser(source, file).parseFull() {
				case Block(exprs): exprs;
				case v: [v];
			}
		
		var fields = new Array<Field>();
		
		for (part in parts)
			switch part {
				case Function(name, args, body):
					fields.push({
						name: name,
						access: [APublic, AStatic],
						pos: getPos(part),
						kind: FFun({
							args: args,
							ret: null,
							expr: macro {
								var ret = new tink.template.Html();
								${generate(body)};
								return ret.collapse();
							}
						})
					});
				case Const(v, _) if (v.trim() == ''):
				default:
					getPos(part).error('function expected');
			}
		
		
		var pack = name.split('.');
		var name = pack.pop();
		return {
			pos: pos,
			fields: fields,
			name: name,
			pack: pack,
			kind: TDClass()
		}
	}
}
// #end