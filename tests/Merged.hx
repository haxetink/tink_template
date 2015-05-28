package;

@:template('Example.mtt')
@:tink
class Merged {
	//@:template static public function frame(title, scripts:Array<String>, stylesheets:Array<String>, content);
	@:template static public function frame(_ = { title: _, scripts: [], stylesheets: [], content: _});
}