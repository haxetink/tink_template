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
	static function use() {
		var frontends = [
			new Frontend(['mtt'], '::', '::'),
			new Frontend(['stache'], '{{', '}}'),
			//new Frontend(['smile'], '(:', ':)'),
		];
		
		for (f in frontends)
			SyntaxHub.frontends.whenever(f);
			
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
			
			function addTemplate(m:Member, ?name:String) {
				if (name == null)
					name = m.name;
					
				switch FrontendContext.seekFile(c.target.pack, name, frontends) {
					case []:
						m.pos.error('what?');
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
					//case Success({ params: [macro $i{name}] }):
					case Success({ params: v }):
						v[2].reject('Too many arguments');
					case Failure(_):
				}
			
			return changed;
		});
	}
}
#end