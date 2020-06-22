package tink.template;

abstract PlainBuf(StringBuf) {
  public inline function new()
    this = new StringBuf();

  public inline function add(v:Dynamic)
    this.add(v);

  public inline function addRaw(s:String)
    this.add(s);

  public inline function collapse()
    return this.toString();
}