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
using Lambda;

class Template {
	
	static var rebuild = null;
	static public function use(?rebuildWith:String) {
		MacroApi.onTypeNotFound(getType);
		rebuild = rebuildWith;
	}
	
	static public function just(name:String) {
		Context.onGenerate(function (types:Array<Type>)
			for (t in types)
				if (t.getID() != name)
					switch t {
						case TInst(c, _):
							c.get().exclude();
						case TEnum(e, _):
							e.get().exclude();
						default:
					}
				else
					switch t {
						case TInst(c, _):
							var c = c.get();
							var meta = c.meta;
							if (meta.has(':native'))
								meta.remove(':native');
							meta.add(':native', [macro "$template"], c.pos);
						default:
					}
		);
		Template.use();
		Context.getType(name);
	}
	
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
			if (t == null) null;
			else switch t {
				case Const(_, pos): pos;
				case Define(_, e), Meta(_, e): getPos(e);
				case For(e, _), If(e, _, _), Yield(e), Do(e): e.pos;
				case Var([]): Context.currentPos();
				case Block([]): Context.currentPos();
				case Var(a): a[0].expr.pos;
				case Function(_, _, t): getPos(t);
				case Block(a): getPos(a[0]);
			}	
	
	static function posComment(pos:Position) {
		var pos = Context.getPosInfos(pos);
		return '<!-- POSITION: ${haxe.Json.stringify(pos)} -->';
	}
	
	static function functionBody(body:TExpr):Expr {
		var pos = getPos(body);
		var body = [body];
		if (Context.defined('debug'))
			body.unshift(Const(posComment(pos), pos));
			
		return macro @:pos(pos) {
			var ret = new tink.template.Html();
			$a{body.map(generate)};
			return ret.collapse();			
		}
	}
	
	static function generate(t:TExpr):Expr {
		var pos = getPos(t);		
		var ret:Expr = 
			if (t == null) null;
			else switch t {
				case Meta(meta, e):
					var e = generate(e);
					for (m in meta)
						e = EMeta(m, e).at(m.pos);
					e;
				case Const(value, pos):
					macro @:pos(pos) ret.add(tink.template.Html.raw($v{value}));
				case Define(name, value):
					macro @:pos(pos) var $name = ${generate(value)};
				case Yield(e):
					macro @:pos(e.pos) ret.add($e);
				case Do(e):
					e;
				case Var(vars):
					EVars(vars).at(pos);
				case If(cond, cons, alt):
					macro @:pos(pos)
						if ($cond)
							${generate(cons)}
						else
							${generate(alt)};
				case For(target, body):
					macro @:pos(pos)
						for ($target) 
							${generate(body)};
							
				case Function(name, args, body):						
					functionBody(body).func(args, false).asExpr(name);
				case Block(exprs):
					exprs.map(generate).toBlock(pos);
			}
		
		return ret;
	}		
	
	static function parse(file:String, name:String):TypeDefinition {
		var args = Sys.args();
		var isMain = 
			switch args.indexOf('-main') {
				case -1: false;
				case v: args[v + 1] == name;
			}
			
		var source = file.getContent();
		var pos = Context.makePosition({ file: file, min: 0, max: source.length });
		
		var fields = new Array<Member>();
		
		for (f in new Parser(source, file).parseAll()) {
			switch f {
				case VanillaField(f):
					fields.push(f);
				case TemplateField(f, tpl):
					fields.push(f);
					switch f.kind {
						case FFun(f):
							f.expr = functionBody(tpl);
						case FVar(t, _):
							f.kind = FVar(t, generate(tpl));
						case FProp(get, set, t, _):
							f.kind = FProp(get, set, t, generate(tpl));
					}
			}
		}
		
		var file = Context.getPosInfos(pos).file;
		if (file.charAt(1) == ':' || file.charAt(0) == '/') {
			
		}
		else
			file = Sys.getCwd() + file;
		
		if (rebuild != null)
			fields.push({
				name: '___initialized',
				pos: pos,
				access: [AStatic],
				kind: FVar(null, macro {
					tink.template.Reloader.add($v{name}, $v{file}, $v{rebuild});
					true;
				})
			});
			
		if (isMain && !fields.exists(function (m) return m.name == 'main')) {
			if (Context.defined('neko')) {
				var calls = fields.filter(function (m) return m.name.startsWith('do'));
				
			}
			else fields.push({
				name: '___whoops',
				pos: pos,
				access: [AStatic],
				kind: FVar(null, pos.errorExpr('main mode is currently neko only')),
			});
		}
		
		var pack = name.split('.');
		var name = pack.pop();
		var interfaces = [];
		
		if (Context.defined('tink_lang'))
			interfaces.push('tink.Lang'.asTypePath());
			
		return {
			pos: pos,
			fields: fields,
			name: name,
			pack: pack,
			kind: TDClass(interfaces)
		}
	}
}
// #end