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
	static var rebuild = null;
	static public function use(?rebuildWith:String) {
		Context.onTypeNotFound(getType);
		rebuild = rebuildWith;
	}
	
	static public function just(name:String) {
		Context.onGenerate(function (types:Array<Type>) {
			for (t in types) {
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
			}
		});
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
				case For(e, _), If(e, _, _), Yield(e), Do(e): e.pos;
				case Var([], _): Context.currentPos();
				case Block([]): Context.currentPos();
				case Var(a, _): a[0].expr.pos;
				case Function(_, _, t, _): getPos(t);
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
	
	static public function generate(t:TExpr):Expr {
		var pos = getPos(t);		
		var ret:Expr = 
			if (t == null) null;
			else switch t {
				case Const(value, pos):
					macro @:pos(pos) ret.add(tink.template.Html.raw($v{value}));
				case Yield(e):
					macro @:pos(e.pos) ret.add($e);
				case Do(e):
					e;
				case Var(vars, access):
					if (access.length > 0)
						pos.error('unexpected ' + access);
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
							
				case Function(name, args, body, access):
					if (access.length > 0)
						pos.error('unexpected ' + access);					
						
					functionBody(body).func(args, false).asExpr(name);
				case Block(exprs):
					exprs.map(generate).toBlock(pos);
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
		
		for (part in parts) {
			function add(?name, access, kind) {
				var m:Member = {
					name: if (name == null) MacroApi.tempName() else name,
					access: access,
					pos: getPos(part),
					kind: kind
				};
				m.publish();
				fields.push(m);	
			}
				
			switch part {
				case Function(name, args, body, access):
					add(name, access, FFun({
						args: args,
						ret: null,
						expr: functionBody(body)
					}));
				case Const(v, _) if (v.trim() == ''):
				case Var([v], access):
					add(v.name, access, FVar(v.type, v.expr));
				default:
					add([], FFun({
						args: [],
						ret: null,
						expr: getPos(part).errorExpr('function expected')
					}));
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