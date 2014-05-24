package tink;

#if macro
import haxe.macro.*;
import haxe.macro.Expr;
import tink.template.Parser;

using tink.CoreApi;
using tink.MacroApi;

using sys.io.File;
using sys.FileSystem;

using StringTools;
using Lambda;
#end

class Template {
	
	#if macro	
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
	
	static var rebuild = null;
	static var active = false;

	static public var mainify(default, null) = {
		var q = new tink.priority.Queue<TypeDefinition->Bool>();
		q.after(function (_) return true, mainAsDispatch);
		q;
	}

	static public var postprocess(default, null) = {
		var q = new tink.priority.Queue<TypeDefinition->Void>();
		q.after(function (_) return true, addMain);
		q;
	}
	
	
	static function addMain(t:TypeDefinition) {
		var args = Sys.args();
		for (i in 0...args.length)
			if (args[i] == '-main') {
				if (args[i + 1] == t.pack.concat([t.name]).join('.')) {
					if (!t.fields.exists(function (f) return f.name == 'main'))
						for (f in mainify)
							if (f(t)) return;
				}
				return;
			}
	}
	
	static function mainAsDispatch(t:TypeDefinition) {
		
		for (field in t.fields)
			switch field.kind {
				case FFun(f) if (field.name.startsWith('do')):
					f.expr = macro @:pos(field.pos) {
						var tmp = (function () ${f.expr})();
						Sys.print(tmp);
					}
				default:
			}
		
		
		var init = macro @:pos(t.pos) {
			function req() {
				haxe.web.Dispatch.run(haxe.web.Request.getURI(), haxe.web.Request.getParams(), $i{t.name});
			}
			neko.Web.cacheModule(req);
			req();
		}
		
		t.fields.push({
			name: 'main',
			access: [AStatic],
			pos: t.pos,
			kind: FFun(init.func(false))
		});
		
		return true;
	}
	
	static function getType(name:String) {
		var tail = name.replace('.', '/')+'.tpl';
		for (path in Context.getClassPath()) {
			var file = path + tail;
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
				case Switch(e, _), While(e, _), For(e, _), If(e, _, _), Yield(e), Do(e): e.pos;
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
	
	static function functionBody(body:TExpr, ?withReturn:Bool):Expr {
		var pos = getPos(body);
		var body = [body];
		if (Context.defined('debug'))
			body.unshift(Const(posComment(pos), pos));
		
		var ret = macro @:pos(pos) ret.collapse();
		if (withReturn)
			ret = macro return $ret;
		
		return macro @:pos(pos) {
			var ret = new tink.template.Html();
			$a{body.map(generate)};
			$ret;
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
				case While(cond, body):
					macro @:pos(pos) 
						while ($cond) ${generate(body)};
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
				case Switch(target, cases):
					ESwitch(target, [for (c in cases) {
						guard: c.guard,
						values: c.values,
						expr: generate(c.expr),
					}], null).at(pos);
				case If(cond, cons, alt):
					macro @:pos(pos)
						if ($cond)
							${generate(cons)}
						else
							${generate(alt)};
				case For(target, body, legacy):
					var pre = macro {};
					
					if (legacy) {
						
						target = macro @:pos(target.pos) __current__ in $target;
						
						pos.warning('foreach loops are discouraged');
						
						pre = (macro __current__).bounceExpr(
							function (e:Expr) {
								var tmp = MacroApi.tempName();
								var v = EVars(
									[for (f in e.typeof().sure().getFields().sure()) 
										if (f.isPublic && f.kind.getName() == 'FVar') {
											var name = f.name;
											{
												name: f.name,
												type: null,
												expr: macro @:pos(e.pos) $i{tmp}.$name
											}
										}
									]							
								).at(e.pos);
								return macro @:pos(e.pos) @:mergeBlock {
									var $tmp = $e;
									$v;
								}
							}
						);
						
					}
					
					macro @:pos(pos)
						for ($target) {
							$pre;
							${generate(body)};
						}
							
				case Function(name, args, body):						
					functionBody(body, true).func(args, false).asExpr(name);
				case Block(exprs):
					exprs.map(generate).toBlock(pos);
			}
		
		return ret;
	}		
	
	static var cache = new Map();
	
	static function parse(file:String, name:String):TypeDefinition {
			
		var source = file.getContent();
		
		var key = name+'::'+source;
		
		if (cache[key] != null)
			return cache[key];
		
		var pos = Context.makePosition({ file: file, min: 0, max: source.length });
		
		var args = Sys.args();
		var fields = new Array<Member>();
		var superClass = null,
			interfaces = [],
			meta = [];
		
		for (f in new Parser(source, file).parseAll()) {
			switch f {
				case SuperType(t, true, pos):
					if (superClass == null)
						superClass = t;
					else
						pos.error('cannot have multiple super classes');
				case SuperType(t, false, _):
					interfaces.push(t);
				case Meta(m):
					meta = meta.concat(m);
				case VanillaField(f):
					fields.push(f);
				case TemplateField(f, tpl):
					fields.push(f);
					switch f.kind {
						case FFun(f):
							f.expr = functionBody(tpl, true);
						case FVar(t, _):
							f.kind = FVar(t, functionBody(tpl));
						case FProp(get, set, t, _):
							f.kind = FProp(get, set, t, functionBody(tpl));
					}
			}
		}
		
		for (f in fields)
			f.publish();
		
		var file = Context.getPosInfos(pos).file;
		if (file.charAt(1) != ':' && file.charAt(0) != '/') 
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
			
		var ret:TypeDefinition = {
			pos: pos,
			fields: fields,
			meta: meta,
			name: name,
			pack: pack,
			kind: TDClass(superClass, interfaces)
		};	
		
		for (p in postprocess)
			p(ret);
			
		return ret;
	}
	#end
}