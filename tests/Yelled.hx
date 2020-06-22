abstract Yelled(String) to String {
  inline function new(s)
    this = s;

  static public function buffer() {
    var parts = [];
    return {
      add: function (s:Dynamic) parts.push(Std.string(s).toUpperCase()),
      addRaw: function (s:String) parts.push(s),
      collapse: function () return new Yelled(parts.join(''))
    }
  }
}