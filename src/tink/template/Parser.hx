package tink.template;

import haxe.macro.Expr;
import haxe.macro.Context;

using tink.CoreApi;
using tink.MacroApi;

enum TExpr {
	Const(value:String, pos:Position);
	Meta(data:Metadata, expr:TExpr);
	Yield(e:Expr);
	Do(e:Expr);
	Var(a:Array<Var>);
	Define(name:String, value:TExpr);
	If(cond:Expr, cons:TExpr, ?alt:TExpr);
	For(target:Expr, body:TExpr);
	Function(name:String, args:Array<FunctionArg>, body:TExpr);
	Block(exprs:Array<TExpr>);
}

enum TDecl {
	VanillaField(f:Field);
	TemplateField(f:Field, expr:TExpr);
}

class Parser {
	
	var pos:Int;
	var last:Int;
	var file:String;
	var source:String;	
	
	public function new(source, file) {
		this.source = source;
		this.file = file;
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
	
	function parseFull():TExpr {
		var ret = [parse()];
		while (!isNext('::end::') && !isNext('::else') && pos < source.length)
			ret.push(parse());
		return TExpr.Block(ret);
	}

	function parseSimple():Expr
		return Context.parse(until('::'), getPos());

	function parseInline():TExpr 
		return Yield(parseSimple());
	
	function expect(s:String) 
		if (!allow(s))
			getPos().error('expected $s');	
	
	static var ACCESSES = [for (a in Access.createAll()) a.getName().substr(1).toLowerCase() => a];
	
	public function parseAll() {
		skipWhite();
		var ret = [];
		while (allow('::')) {
			ret.push(parseDecl());
			skipWhite();
		}
		return ret;
	}
	
	function parseDecl() {
		var meta = parseMeta(),
			access = parseAccess();
			
		return	
			if (isNext('var ')) {
				switch Context.parseInlineString('(null : {'+until('::')+'})', getPos()) {
					case { expr: ECheckType(_, TAnonymous([f])) }:
						f.meta = meta;
						f.access = access;
						
						switch f.kind {
							case FVar(_, null), FProp(_, _, _, null): 
								VanillaField(f);
							default:
								TemplateField(f, parseToEnd());
						}
					case v: 
						v.reject('invalid variable declaration'); 
				}
			}
			else if (allow('function ')) {
				var f = parseFunction();
				var ret:Field = {
					name: f.name,
					pos: f.pos,
					meta: meta,
					access: access,
					kind: FFun(f.func),
				}
				
				if (f.tpl == null) 
					VanillaField(ret);
				else
					TemplateField(ret, f.tpl);
			}
			else 
				getPos().error('what\'s your problem man?');
	}
	
	function parseFunction() {
		var name = ident().sure();
		
		skipWhite();
		
		var args = getArgs();
		
		skipWhite();
		
		var tpl = null;
		var fBody = 
			if (allow('::')) {
				tpl = parseToEnd();
				'{}';
			}
			else 
				until('::');
		
		var func = 
			switch Context.parseInlineString('function $name($args) $fBody', getPos()) {
				case { expr: EFunction(_, f) }:
					if (tpl != null)
						f.expr = null;
					f;
				default:
					throw 'assert';
			}
		
		return {
			tpl: tpl,
			func: func,
			name: name,
			pos: getPos(),
		}
	}
	
	function skipWhite() 
		while (source.charCodeAt(pos) <= 32) pos++;
	
	static var IDENT = [for (c in '_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) c.charCodeAt(0) => true];
	
	function ident() {
		this.last = pos;
		while (IDENT[source.charCodeAt(pos)])
			pos++;
		return
			if (last == pos)
				getPos().makeFailure('identifier expected');
			else
				Success(source.substring(last, pos));
	}
	
	function parseMetaEntry():MetadataEntry {
		
		expect('@');
		
		var name = (allow(':') ? ':' : '') + ident();
		var ret = {
			pos: getPos(),
			name: name,
			params: [],
		}
		
		skipWhite();
		
		if (isNext('(')) {
			var start = pos;
			var s = getArgs();
			
			var pos = getPos();
			
			switch Context.parseInlineString('[$s]', pos) {
				case macro [$a{args}]:
					skipWhite();
					ret.pos = pos;
					ret.params = args;
				default:
					throw 'assert';
			}
		}
		return ret;
	}
	
	function getArgs() {
		var start = pos;
		var ret = '';
		do {
			until(')');
			ret = source.substring(start + 1, pos - 1);
		} while (ret.split('(').length > ret.split(')').length);		
		last = start;
		return ret;
	}
	
	function parseMeta()
		return
			[while (isNext('@')) parseMetaEntry()];
			
	function parseAccess() {
		var ret = [];
		var done = false;
		
		while (!done) {
			done = true;
			for (a in ACCESSES.keys())
				if (allow(a)) {
					skipWhite();
					done = false;
					ret.push(ACCESSES[a]);
				}
		}
		return ret;		
	}
	
	function parseToEnd() {
		var ret = parseFull();
		expect('::end::');
		return ret;
	}
	
	function parseComplex() {
		
		var meta = parseMeta();
		
		var ret = 
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
				var f = parseFunction();
				if (f.tpl == null)
					Do(EFunction(f.name, f.func).at(f.pos));
				else
					Function(f.name, f.func.args, f.tpl);
			}
			else if (isNext('var ')) {
				switch parseSimple().expr {
					case EVars([{ name: name, expr: null }]):
						Define(name, parseToEnd());
					case EVars(vars): 
						Var(vars);
					default:
						throw 'assert';
				}
			}
			else parseInline();	
		
		
		return switch meta {
			case []: ret;
			case v: Meta(v, ret);
		}
	}
	
	function parse():TExpr
		return
			if (allow('::')) 
				parseComplex();
			else {
				var pos = getPos();
				switch until('::', true).split('@L[') {
					case [ret]: Const(ret, pos);
					case parts:
						var ret = [Const(parts.shift(), pos)];
						for (part in parts) {
							var next = part.indexOf(']');
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