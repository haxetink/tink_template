package;

@:template('Example.mtt')
@:tink
class Merged {
  @:template static public function frame(_ = { title: _, scripts: [], stylesheets: [], content: _});
  @:template('../tests/frame.mtt') static public function sameFrame(_ = { title: _, scripts: [], stylesheets: [], content: _});
}