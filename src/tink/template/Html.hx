package tink.template;

import tink.HtmlString;
import tink.htmlstring.HtmlBuffer as Buf;

abstract Html(HtmlString) from HtmlString to HtmlString {

  public inline function new(s:String) this = new HtmlString(s);

  @:from static public function escape(s:String):Html
    return (s:HtmlString);

  @:to public inline function toString():String
    return this;

  @:from static function ofMultiple(parts:Array<Html>):Html
    return new Html(parts.join(''));

  @:from static public function of<A>(a:A):Html
    return escape(Std.string(a));

  static public function buffer():HtmlBuffer
    return new HtmlBuffer();
}

abstract HtmlBuffer(Buf) {
  public inline function new()
    this = new Buf();

  public inline function collapse():Html
    return this.toHtml();

  @:to public inline function toString():String
    return this.toString();

  public inline function add(b:Html)
    this.add(b);

  public inline function addRaw(s:String)
    this.addRaw(s);

}