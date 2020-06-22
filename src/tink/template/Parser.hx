package tink.template;

#if macro
import haxe.macro.Expr;
import haxe.macro.Context;
import tink.template.TplExpr;

using haxe.macro.Tools;
using tink.CoreApi;
using tink.MacroApi;
using StringTools;

class Parser {

  var pos:Int;
  var last:Int;
  var file:String;
  var source:String;

  var openTag:String;
  var closeTag:String;
  var allowForeach:Bool;

  public function new(source, file, settings:Settings) {
    this.source = source;
    this.file = file;
    this.pos = 0;
    this.last = 0;
    this.openTag = settings.openTag;
    this.closeTag = settings.closeTag;
    this.allowForeach = settings.allowForeach;
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

  public function parseFull():TplExpr {
    var ret = [];
    while (pos < source.length) {
      var start = pos;//dirty look ahead coming up!
      if (allow(openTag)) {
        if (allow('*')) {
          until('*$closeTag');
          skipWhite();
          continue;
        }
        skipWhite();
        var kw = ident();
        pos = start;
        switch kw {
          case Success('end' | 'case' | 'else' | 'elseif'):
            break;
          default:
        }
      }

      ret.push(parse());
    }
    return TplExpr.Block(ret);
  }

  static function parseHx(s:String, pos:Position)
    return
      try
        Context.parse(s, pos).transform(function (e) return switch e.expr {
          case EConst(CString(s)):
            s.formatString(e.pos);
          default: e;
        })
      catch (e:Dynamic)
        pos.error('$e in "$s"');

  function parseSimple():Expr {
    skipWhite();
    return parseHx(until(closeTag), getPos());
  }

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

    while (allow(openTag)) {

      if (allow('*')) {
        until('*$closeTag');
        skipWhite();
        continue;
      }

      skipWhite();

      ret.push(parseDecl());

      skipWhite();
    }

    return {
      pos: Context.makePosition( { min: 0, max: source.length, file: file } ),
      declarations: ret,
    }
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

          if (allow(closeTag))
            TemplateField(setKind(), parseToEnd());
          else
            VanillaField(
              switch parseHx('var foo '+until(closeTag), getPos()) {
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
                      expect(closeTag);
                      break;
                    }

                    switch ident().sure() {
                      case 'in':
                        skipWhite();
                        mode = IAsName(ident().sure());
                        skipWhite();
                        expect(closeTag);
                        break;

                      case v:
                        parts.push(v);
                        skipWhite();
                        if (allow(closeTag)) break;
                        expect('.');
                    }
                  }
                  Import(parts.join('.'), mode, getPos());

                case Success('using'):
                  var path = [ident().sure()];
                  while (allow('.'))
                    path.push(ident().sure());
                  skipWhite();
                  expect(closeTag);
                  Using(path.join('.'), getPos());

                case v:

                  parseField({ pos: null, name: null, kind: null }, v);
              }
            case access:
              parseField({ pos: null, name: null, kind: null, access: access });
          }
        case v:
          skipWhite();
          if (allow(closeTag))
            TplDecl.Meta(v);
          else
            parseField({ pos: null, name: null, kind: null, access: parseAccess(), meta: v });
      }

  function parseSuperType(isClass:Bool)
    return
      switch parseHx('new ' + until(closeTag) + '()', getPos()) {
        case { expr: ENew(t, _), pos: pos }:
          SuperType(t, isClass, pos);
        default:
          throw 'assert';
      }

  function parseType() {
    skipWhite();
    var ret = ident().sure();
    skipWhite();
    while (allow('.')) {
      ret += '.' + ident().sure();
      skipWhite();
    }
    return ret;
  }

  function parseFunction() {
    var name = ident().sure();

    var params =
      if (isNext('<')) '<' + balanced('<', '>') + '>';
      else '';

    var args = getArgs();

    skipWhite();

    var closed = allow(closeTag);
    var ret =
      if (allow(':')) ':' + parseType();
      else '';

    var tpl = null;
    var fBody =
      if (closed || allow(closeTag)) {
        tpl = parseToEnd();
        '{}';
      }
      else
        removeTrailingSemicolon(until(closeTag));

    var fname =
      switch name {
        case 'new': '';
        case _: name;
      }

    var func =
      switch parseHx('function $fname$params($args)$ret $fBody', getPos()) {
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

  function removeTrailingSemicolon(s:String) {
    s = s.rtrim();
    if (s.endsWith(';'))
      s = s.substr(0, s.length - 1);
    return s;
  }

  function skipWhite()
    while (source.charCodeAt(pos) <= 32) pos++;

  static var IDENT = [for (c in '_0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ'.split('')) c.charCodeAt(0) => true];

  function ident() {
    skipWhite();
    this.last = pos;
    while (IDENT[source.charCodeAt(pos)])
      pos++;
    return
      if (last == pos)
        getPos().makeFailure('identifier expected');
      else {
        var ret = Success(source.substring(last, pos));
        skipWhite();
        ret;
      }
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
    expectAll([openTag, 'end', closeTag]);
    //expect('${openTag}end${closeTag}');
    return ret;
  }

  function finishLoop(loop:TplExpr) {
    expect(openTag);
    skipWhite();
    return
    switch ident() {
      case Success('else'):
        expect(closeTag);
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

        Block([
          Do(macro var $tmp = false),
          loop,
          If(macro !$i{tmp}, alt, null)
        ]);
      case Success('end'):
        skipWhite();
        expect(closeTag);
        loop;
      case Success(v):
        getPos().error('unexpected identifier $v');
      case Failure(f):
        getPos().error('expected end or else here');
    }
  }

  function expectAll(tokens:Array<String>) {
    for (t in tokens) {
      skipWhite();
      expect(t);
    }
    skipWhite();
  }

  function parseComplex() {

    var meta = parseMeta();
    skipWhite();
    var start = pos;//dirty lookahead coming
    var ret =
      switch ident() {
        case Success('for'):
          finishLoop(For(parseSimple(), parseFull()));
        case Success('foreach'):
          switch allowForeach {
            case true:
              getPos().warning('foreach is discouraged');
            case false:
              getPos().error('foreach not allowed by this template flavor');
          }
          finishLoop(For(parseSimple(), parseFull(), true));
        case Success('while'):
          finishLoop(While(parseSimple(), parseFull()));
        case Success('do'):
          Do(parseSimple());
        case Success('if'):
          var cases = [],
              alt = null;

          function next()
            cases.push({
              when: parseSimple(),
              then: parseFull()
            });

          next();

          while (pos < source.length) {
            var start = pos;//one dirty look ahead coming up
            if (allow(openTag)) {
              var kw = ident();
              switch kw {
                case Success('elseif'):
                  next();
                case Success('else'):
                  switch ident() {
                    case Success('if'):
                      next();
                    case Success(v):
                      getPos().error('Unexpected identifier $v');
                    default:
                      expect(closeTag);
                      alt = parseFull();
                      break;
                  }
                default:
                  pos = start;
                  break;
              }
            }
          }

          expectAll([openTag, 'end', closeTag]);

          while (cases.length > 0)
            switch cases.pop() {
              case v:
                alt = If(v.when, v.then, alt);
            }
          alt;
        case Success('switch'):
          var target = parseSimple();
          skipWhite();

          expect(openTag);
          var cases = [];
          while (pos < source.length)
            switch ident() {
              case Success('case'):
                var src = until(closeTag);
                switch parseHx('switch _ { case $src: }', getPos()) {
                  case { expr: ESwitch(_, [c], _) } if (c.expr == null):
                    cases.push({
                      values: c.values,
                      guard: c.guard,
                      expr: parseFull(),
                    });
                    expect(openTag);
                  case e:
                    e.reject('invalid case statement: ${e.toString()}');
                }
              case Success('end'):
                expect(closeTag);
                break;
              case Success(v):
                getPos().error('Unexpected identifier $v');
              default:
                getPos().error('expected case or end');
            }
          Switch(target, cases);

        case Success('function'):
          var f = parseFunction();
          if (f.tpl == null)
            Do(f.func.asExpr(f.name, f.pos));
          else
            Function(f.name, f.func.args, f.tpl, f.func.ret);
        case Success('var'):
          pos = start;
          switch parseSimple().expr {
            case EVars([{ name: name, expr: null }]):
              Define(name, parseToEnd());
            case EVars(vars):
              Var(vars);
            default:
              throw 'assert';
          }
        default:
          pos = start;
          parseInline();
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
      if (allow(openTag))
        parseComplex();
      else {
        var pos = getPos();
        Const(collapseWhite(until(openTag, true)), pos);
      }
}
#end