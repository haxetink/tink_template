package tink.template;

#if macro
import haxe.macro.Expr;
import tink.syntaxhub.*;

using sys.io.File;
using sys.FileSystem;
using tink.MacroApi;

class Frontend implements FrontendPlugin {

  public var extensionList(default, null):Array<String>;
  var settings:Settings;
  public function new(extensions, settings) {
    this.extensionList = extensions;
    this.settings = settings;
  }

  public function extensions()
    return extensionList.iterator();

  public function parseField(file:String, m:Member) {
    if (!file.exists())
      m.pos.error('Unknown file $file');

    function parse(t, withReturn)
      return
        Generator.functionBody(
          parserFor(file).parseFull(),
          t,
          withReturn
        );

    m.kind =
      switch m.kind {
        case FVar(t, null):
          if (t == null)
            t = TYPE;
          FVar(t, parse(t, false));
        case FProp(get, set, t, null):
          if (t == null)
            t = TYPE;
          FProp(get, set, t, parse(t, false));
        case FFun({ expr: null }):
          var f = Reflect.copy(m.getFunction().sure());
          f.expr = parse(f.ret, true);
          FFun(f);
        case FVar(_, { pos: pos }) | FProp(_, _, _, { pos: pos }) | FFun({ expr: { pos: pos}}):
          pos.error('@:template does not permit expression here');
      }
  }
  static var TYPE = macro : tink.template.Html;
  public function parseFields(file:String, c:ClassBuilder) {
    for (d in parserFor(file).parseAll().declarations)
      switch d {
        case VanillaField(f):
          c.addMember(f).publish();

        case TemplateField(f, expr):
          Generator.finalizeField(f, expr);
          c.addMember(f).publish();
        case Meta(m):
          for (m in m)
            c.target.meta.add(m.name, m.params, m.pos);
        case SuperType(_, isClass, pos):
          pos.error((if (isClass) 'extends' else 'implements') + ' not allowed in @:template templates');
        case Import(_, _, pos):
          pos.error('import not allowed in @:template templates');
        case Using(_, pos):
          pos.error('using not allowed in @:template templates');
      }
  }

  function parserFor(file:String)
    return new Parser(file.getContent(), file, settings);

  public function parse(file:String, context:FrontendContext):Void {
    Generator.generate(
      parserFor(file).parseAll(),
      context
    );
  }
}
#end