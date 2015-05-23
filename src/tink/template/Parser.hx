package tink.template;

import haxe.macro.Expr;
import haxe.macro.Context;
import tink.template.TplExpr;

using haxe.macro.Tools;
using tink.CoreApi;
using tink.MacroApi;

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
	
	function parseFull():TplExpr {
		var ret = [parse()];
		while (!isNext('::end::') && !isNext('::else') && !isNext('::case') && pos < source.length)
			ret.push(parse());
		return TplExpr.Block(ret);
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

	function parseInline():TplExpr {
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
	
	function parseField(field:Field, ?token) 
		return
			switch if (token == null) ident() else token {
				case Success('var'):
					skipWhite();
					
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
				case Success('function'):
					skipWhite();
					var f = parseFunction();
					field.name = f.name;
					field.pos = f.pos;
					field.kind = FFun(f.func);
					
					if (f.tpl == null) 
						VanillaField(field);
					else
						TemplateField(field, f.tpl);
				case Success(v):
					getPos().error('unexpected identifier $v');
				case f:
					getPos().error('Invalid toplevel declaration');	
			}
		
	
	function parseDecl() 
		return
			switch parseMeta() {
				case []:
					switch parseAccess() {
						case []:
							switch ident() {
								case Success('implements'):
									parseSuperType(false);
								case Success('extends'):
									parseSuperType(true);
								case Success('import'):
									var parts = [],
											mode = INormal;
									while (true) {
										skipWhite();
										
										if (allow('*')) {
											mode = IAll;
											skipWhite();
											expect('::');
										}
										
										switch ident().sure() {
											case 'in': 
												skipWhite();
												mode = IAsName(ident().sure());
												skipWhite();
												expect('::');
												break;
												
											case v: 
												parts.push(v);
												skipWhite();
												if (allow('::')) break;
												expect('.');
										}
									}
									Import(parts.join('.'), mode, getPos());
								
								case Success('using'):
									
									throw 'not implemented';
								
								case v:
									
									parseField({ pos: null, name: null, kind: null }, v);
							}
						case access:
							parseField({ pos: null, name: null, kind: null, access: access });
					}
				case v:
					skipWhite();
					if (allow('::'))
						TplDecl.Meta(v);
					else 
						parseField({ pos: null, name: null, kind: null, access: parseAccess(), meta: v });
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
    var params = 
		  if (isNext('<')) '<' + balanced('<', '>') + '>';
      else '';
      
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
			switch parseHx('function $fname$params($args) $fBody', getPos()) {
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
		
		var name = (allow(':') ? ':' : '') + ident().sure();
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
		
  inline function getArgs() 
    return balanced('(', ')');
  
  function balanced(open:String, close:String) {
		var start = pos;
		var ret = '';
		do {
			until(close);
			ret = source.substring(start + 1, pos - 1);
		} while (ret.split(open).length > ret.split(close).length);		
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
	
	function finishLoop(loop:TplExpr) {
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
                var src = until('::');
                switch parseHx('switch _ { case $src: }', getPos()) {
                  case { expr: ESwitch(_, [c], _) } if (c.expr == null): 
                    var ret = {
                      values: c.values,
                      guard: c.guard,
                      expr: parseFull(),
                    }
                    expect('::');
                    ret;
                  case e:
                    e.reject('invalid case statement: ${e.toString()}');
                }
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
	
	function collapseWhite(s:String) {
		return s;
		var ret = new StringBuf(),
			i = 0;
			
		while (i < s.length)
			if (s.charCodeAt(i) < 33) {
				ret.addChar(32);
				while (s.charCodeAt(i) < 33) i++; 
			}
			else ret.addChar(s.charCodeAt(i++));
			
		return ret.toString();
	}
	
	function parse():TplExpr
		return
			if (allow('::')) 
				parseComplex();
			else {
				var pos = getPos();
				Const(collapseWhite(until('::', true)), pos);
			}
}