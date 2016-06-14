package tink;

#if macro
import tink.macro.ClassBuilder;
import haxe.macro.Context;
import tink.syntaxhub.*;
import tink.template.*;

using tink.MacroApi;
using haxe.io.Path;
using sys.FileSystem;
using sys.io.File;

class Template {
  static var frontends = new Map();
  static function addFlavor(extensions:String, openTag:String, closeTag:String, ?allowForeach:Bool = false) {
    
    var f = new Frontend(extensions.split(','), {
      openTag : openTag, 
      closeTag : closeTag, 
      allowForeach : allowForeach
    });
    
    var list = f.extensionList.copy();
    
    list.sort(Reflect.compare);
    
    var id = list.join('_');
    
    SyntaxHub.frontends.whenever(f, 'tink.Template::$id');
    
    frontends[id] = f;
  }
  
  static function use() {
      
    SyntaxHub.classLevel.before('tink.lang.', function (c:ClassBuilder) {
      var changed = false;
      function addDependency(file:String) {
        Context.registerModuleDependency(
          Context.getLocalModule(),
          file
        );
        changed = true;
      }
      
      if (c.target.meta.has(':template')) {
          
        for (tag in c.target.meta.get())
          switch tag {
            case { name: ':template', params: [], pos: pos }:
              
              switch FrontendContext.seekFile(c.target.pack, c.target.name, frontends) {
                case []:
                  Context.warning('No template found', pos);//A warning will do, because a compiler error should occur down the road
                case results:
                  for (result in results) {
                    result.plugin.parseFields(result.file, c);
                    addDependency(result.file);
                  }
              }
              
            case { name: ':template', params: v, pos: pos }:
              var base = Context.getPosInfos(pos).file.directory().addTrailingSlash();
              for (file in v) {
                
                function parse(file:String) {
                  if (!file.exists())
                    pos.error('File not found: $file');
                    
                  var match = file.extension();
                  for (p in frontends)
                    for (ext in p.extensions())
                      if (ext == match) {
                        p.parseFields(file, c);
                        addDependency(file);
                        return;
                      }
                      
                  pos.error('No parser found for: $file');
                }
                
                parse(Path.join([base, file.getString().sure()]));
              }
              
            default:
          }
        
      }
      
      function addTemplate(m:Member, ?name:String, ?plugins:Iterable<Frontend>) {
        if (name == null)
          name = m.name;
          
        if (plugins == null)
          plugins = frontends;
          
        switch FrontendContext.seekFile(c.target.pack, name, plugins) {
          case []:
            m.pos.error('Failed to find template $name');
          case v:
            v[0].plugin.parseField(v[0].file, m);
            addDependency(v[0].file);
        }        
      }
      
      for (member in c)
        switch member.extractMeta(':template') {
          case Success( { params: [] } ):
            addTemplate(member);
          case Success({ params: [macro $i{name}] }):
            addTemplate(member, name);
          case Success({ params: [v] }):
            var name = v.getString().sure();
            
            var plugins:Iterable<Frontend> = 
              switch name.extension() {
                case '' | null:
                  frontends;
                case ext:
                  name = name.withoutExtension();
                  [for (f in frontends) for (e in f.extensions()) if (e == ext) f];
              }
  
            addTemplate(member, name, plugins);
            
          case Success({ params: v }):
            v[2].reject('Too many arguments');
          case Failure(_):
        }
      
      return changed;
    });
  }
}
#end