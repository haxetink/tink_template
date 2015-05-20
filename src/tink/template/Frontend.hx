package tink.template;

import tink.syntaxhub.*;

using sys.io.File;

class Frontend implements FrontendPlugin {	

	public var extensionList(default, null):Array<String>;
	public function new(extensions) 
		this.extensionList = extensions;
	
	public function extensions()
		return extensionList.iterator();
		
	public function parse(file:String, context:FrontendContext):Void {
		Generator.generate(
			new Parser(file.getContent(), file).parseAll(),
			context
		);
	}	
}