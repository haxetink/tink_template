package tink.template;

import haxe.macro.Expr;
import haxe.macro.Context;

using tink.MacroApi;

enum TExpr {
	Const(value:String, pos:Position);
	Yield(e:Expr);
	Do(e:Expr);
	Var(a:Array<Var>);
	If(cond:Expr, cons:TExpr, ?alt:TExpr);
	For(target:Expr, body:TExpr);
	Function(name:String, args:Array<FunctionArg>, body:TExpr);
	Block(exprs:Array<TExpr>);
}

class Parser {
	
	var pos:Int;
	var last:Int;
	var file:String;
	var source:String;
	
	// static var templates:Map<String, String>;
	// static var cache = new Map<String, CacheEntry>();
	
	// static function buildEntry(name:String, pos:Position):CacheEntry {
	// 	var path = templates[name];
	// 	var source = path.getContent();
		
	// 	Context.registerModuleDependency(Context.getLocalClass().get().module, path);
		
	// 	var hx = null,
	// 		expr = new Parser(source, path).parseFull();
			
	// 	var ret = {
	// 		source: source,
	// 		path: path,
	// 		dependencies: deps,
	// 		expr: expr,
	// 		hx: function () {
	// 			// return Generator.generate(expr, ['__v0']);
	// 			if (hx == null) {
	// 				if (Context.defined('just_template')) 
	// 					trace('generating $name');
	// 				hx = Generator.generate(expr, ['__v0']);
	// 			}
	// 			return hx;
	// 		}
	// 	}
	// 	cache[name] = ret;
	// 	return ret;		
	// }
	
	// static function getTemplate(name:String, pos:Position):CacheEntry
	// 	if (!templates.exists(name))
	// 		return pos.error('No template found for $name');
	// 	else {
	// 		if (cache.exists(name)) {
	// 			for (dep in cache[name].dependencies)
	// 				if (dep.path.stat().mtime.getTime() > dep.mtime)
	// 					return buildEntry(name, pos);
	// 			// trace('CACHEHIT');
	// 			// trace(cache[name].dependencies);
	// 			if (deps != null)
	// 				deps = deps.concat(cache[name].dependencies);
	// 			return cache[name];
	// 		}
	// 		else return buildEntry(name, pos);
	// 	}

	// static var deps:CacheDependencies;
	// static public function process(name, templates, type:ComplexType, pos) {	
	// 	Parser.templates = templates;
	// 	type.toType().sure();		

	// 	deps = [];
		
	// 	var info = getTemplate(name, pos);
	// 	var ret =
	// 		macro @:pos(pos) function (__v0:$type):view.Html {
	// 			var ret = new view.Html();
	// 			${Generator.splat('__v0', pos)};
	// 			${info.hx()};
	// 			return ret.collapse();
	// 		};
	// 	deps = null;
		
	// 	return ret.getFunction().sure();
	// }
	
	public function new(source, file) {
		this.source = source;
		this.file = file;
		// if (deps != null)
		// 	deps.push({ path: file, mtime: file.stat().mtime.getTime() });//TODO: cache mtimes somehow
		this.pos = 0;
		this.last = 0;
	}

	function isNext(s) 
		return source.substr(pos, s.length) == s;
		
	function allow(s:String)
		return 
			if (isNext(s)) {
				pos += s.length;
				true;
			}
			else false;
	
	function until(s:String, ?orEnd = false):String {
		this.last = pos;
		var nu = source.indexOf(s, pos);
		return 
			if (nu == -1)
				if (orEnd) {
					var ret = source.substring(pos);
					pos = source.length;
					ret;
				}
				else {
					pos = source.length;
					getPos().error('expected $s near "${source.substr(this.last, 100)}"');
				}
			else {
				var ret = source.substring(pos, nu);
				if (orEnd)
					pos = nu;
				else
					pos = nu + s.length;
				ret;
			}
	}
	
	function getPos()
		return Context.makePosition({
			min: last,
			max: pos,
			file: file
		});
	
	public function parseFull():TExpr {
		var ret = [parse()];
		while (!isNext('::end::') && !isNext('::else') && pos < source.length)
			ret.push(parse());
		return TExpr.Block(ret);
	}

	function parseSimple():Expr
		return Context.parse(until('::'), getPos());

	function parseInline():TExpr {
		return Yield(parseSimple());
		// var raw = parseSimple();
		// return 
		// 	switch raw {
		// 		// case macro $i{name} if (name.startsWith('tpl_')):
		// 		// 	Include(getTemplate(name.substr(4), raw.pos), false);
		// 		// case macro $i{name}.source if (name.startsWith('tpl_')):
		// 		// 	Const(getTemplate(name.substr(4), raw.pos).source, raw.pos);
		// 		default:
		// 			Yield(raw);
		// 	}
	}
	
	function expect(s:String) 
		if (!allow(s))
			getPos().error('expected $s');	
		
	function parse():TExpr
		return
			if (allow('::')) {
				if (allow('for ')) {
					var target = parseSimple();
					var body = parseFull();
					expect('::end::');
					For(target, body);
				}
				else if (allow('*')) {
					until('*::');
					Block([]);
				}
				else if (allow('do ')) 
					Do(parseSimple());
				else if (allow('if ')) {
					var cases = [],
						alt = null;
					function next()
						cases.push({
							when: parseSimple(),
							then: parseFull()
						});
					next();
					while (allow('::elseif')) 
						next();
					if (allow('::else::'))
						alt = parseFull();
					expect('::end::');
					
					while (cases.length > 0)
						switch cases.pop() {
							case v: 
								alt = If(v.when, v.then, alt);
						}
					alt;
				}
				else if (allow('function ')) {
					var func = Context.parse('function ${until("::")} {}', getPos()),
						body = parseFull();
					
					expect('::end::');
					switch func.expr {
						case EFunction(name, f):
							Function(name, f.args, body);
						default:
							throw 'assert';
					}
				}
				else if (allow('var ')) {
					pos-=4;
					switch parseSimple().expr {
						case EVars(vars): 
							Var(vars);
						default:
							throw 'assert';
					}
				}
				else parseInline();
			}
			else {
				var pos = getPos();
				switch until('::', true).split('@{') {
					case [ret]: Const(ret, pos);
					case parts:
						var ret = [Const(parts.shift(), pos)];
						for (part in parts) {
							var next = part.indexOf('}');
							if (next == -1)
								pos.error('unclosed localization expression: ${part.substr(0, 20)}');
							ret.push(
								switch Context.parse(part.substr(0, next), pos) {
									case macro $i{name}:
										Yield(macro @:pos(pos) locale.$name());
									case macro $i{name}($a{args}):
										Yield(macro @:pos(pos) locale.$name($a{args}));
									case e:
										e.reject();
								}
							);
							
							ret.push(Const(part.substr(next + 1), pos));
						}
						Block(ret);
				}
			}
}