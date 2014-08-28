package tink.template;

import haxe.macro.Expr;
import haxe.macro.Context;

using haxe.macro.Tools;
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
	For(target:Expr, body:TExpr, ?legacy:Bool);
	While(cond:Expr, body:TExpr);
	Function(name:String, args:Array<FunctionArg>, body:TExpr);
	Switch(target:Expr, cases:Array<{ values:Array<Expr>, ?guard:Expr, expr: TExpr }>);
	Block(exprs:Array<TExpr>);
}

enum TDecl {
	VanillaField(f:Field);
	TemplateField(f:Field, expr:TExpr);
	SuperType(t:TypePath, isClass:Bool, pos:Position);
	Meta(m:Metadata);
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
		return Context.makePosition({ min: last, max: pos, file: file });
	
	function parseFull():TExpr {
		var ret = [parse()];
		while (!isNext('::end::') && !isNext('::else') && !isNext('::case') && pos < source.length)
			ret.push(parse());
		return TExpr.Block(ret);
	}

  static function parseHx(s:String, pos:Position)
    return 
      try 
        Context.parseInlineString(s, pos).transform(function (e) return switch e.expr {
          case EConst(CString(s)):
            s.formatString(e.pos);
          default: e;
    		})
      catch (e:Dynamic)
        pos.error('Invalid string "$s');

	function parseSimple():Expr
		return parseHx(until('::'), getPos());

	function parseInline():TExpr {
		var v = parseSimple();
		return
			switch v {
				case macro break, macro continue: 
					Do(v);
				default: 
					Yield(v);
			}
	}
	
	function expect(s:String) 
		if (!allow(s))
			getPos().error('expected $s');	
	
	static var ACCESSES = [for (a in Access.createAll()) a.getName().substr(1).toLowerCase() => a];

	function parseAccess() {
		var ret = [];
		var done = false;
		
		while (!done) {
			done = true;
			for (a in ACCESSES.keys())
				if (allow(a)) {
					done = false;
					ret.push(ACCESSES[a]);
					skipWhite();
				}
		}
		return ret;		
	}

	public function parseAll() {
		skipWhite();
		var ret = [];
		while (allow('::')) {
			ret.push(parseDecl());
			skipWhite();
		}
		return ret;
	}
	
	function parseDecl() 
		return
			if (allow('implements '))
					parseSuperType(false);
			else if (allow('extends '))
				parseSuperType(true);
			else {
				var meta = parseMeta();
				if (allow('this')) 
					Meta(meta);
				else {
					var field:Field = {
						pos: null,
						name: null,
						meta: meta,
						access: parseAccess(),
						kind: null
					};
					if (allow('var ')) {
						field.name = ident().sure();
						field.pos = getPos();
						skipWhite();
						var prop = 
							if (isNext('(')) 
								switch getArgs().split(',') {
									case [get, set]: 
										new Pair(get, set);
									default: 
										getPos().error('malformed field access');
								}
							else new Pair('default', 'default');
								
						skipWhite();
						
						function setKind(?t, ?e) {
							field.kind = FProp(prop.a, prop.b, t, e);
							return field;
						}
						
						if (allow('::')) 
							TemplateField(setKind(), parseToEnd());
						else 
							VanillaField(
								switch parseHx('var foo '+until('::'), getPos()) {
									case { expr: EVars([v]) }: setKind(v.type, v.expr);
									case v: v.reject();
								}
							);
					}
					else if (allow('function ')) {
						var f = parseFunction();
						field.name = f.name;
						field.pos = f.pos;
						field.kind = FFun(f.func);
						
						if (f.tpl == null) 
							VanillaField(field);
						else
							TemplateField(field, f.tpl);
					}
					else	
						getPos().error('Invalid toplevel declaration');
				}
			}	
	
	function parseSuperType(isClass:Bool) 
		return
			switch parseHx('new ' + until('::') + '()', getPos()) {
				case { expr: ENew(t, _), pos: pos }:
					SuperType(t, isClass, pos);
				default: 
					throw 'assert';
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
		var fname = 
      switch name {
        case 'new': '';
        case _: name;
      }
		var func = 
			switch parseHx('function $fname($args) $fBody', getPos()) {
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
			name: name,
			pos: getPos(),
			params: [],
		}
		
		skipWhite();
		
		if (isNext('(')) {
			var start = pos;
			var s = getArgs();
			
			var pos = getPos();
			
			ret.params = exprList(s, pos);
			ret.pos = pos;
			skipWhite();
		}
		return ret;
	}
	
	static function exprList(source:String, pos) 
		return
			switch parseHx('[$source]', pos) {
				case macro [$a{args}]:
					args;
				default: 
					throw 'assert';
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
	
	function parseToEnd() {
		var ret = parseFull();
		expect('::end::');
		return ret;
	}
	
	function finishLoop(loop:TExpr) {
		if (allow('::else::')) {
			var alt = parseToEnd();
			var tmp = MacroApi.tempName();
			var wasRun = Do(macro $i{tmp} = true);
			
			function markRun(t) 
				return
					switch t {
						case Block(exprs):
							Block([wasRun].concat(exprs));
						case v:
							Block([wasRun, v]);
					}
					
			loop = switch loop {
				case For(target, body, legacy):
					For(target, markRun(body), legacy);
				case While(cond, body):
					While(cond, markRun(body));
				case v: loop;//error?
			}
			
			loop = Block([
				Do(macro var $tmp = false),
				loop,
				If(macro !$i{tmp}, alt, null)
			]);
		}
		else expect('::end::');
		return loop;
	}
	
	function parseComplex() {
		
		var meta = parseMeta();
		
		var ret = 
			if (allow('for ')) 
				finishLoop(For(parseSimple(), parseFull()));
			else if (allow('foreach ')) 
				finishLoop(For(parseSimple(), parseFull(), true));
			else if (allow('while ')) 
				finishLoop(While(parseSimple(), parseFull()));
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
				while (allow('::elseif') || allow('::else if')) 
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
			else {
				var start = pos;
				switch ident() {
					case Success('switch'):
						var target = parseSimple();
						skipWhite();
						
						expect('::');
						var cases = [
							while (allow('case')) {
								var c = {
									values: exprList(until('::'), getPos()),
									guard: null, //TODO: implement?
									expr: parseFull(),
								};
								expect('::');
								c;
							}
						];
						expect('end::');
						Switch(target, cases);
					default:
						pos = start;
						parseInline();	
				}
			}
		
		
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
				Const(until('::', true), pos);
			}
}