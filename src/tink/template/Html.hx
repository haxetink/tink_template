package tink.template;

abstract HtmlFragment(String) to String {
	public inline function new(s) this = s;
	public inline function toString():String
		return this;
	@:to public function toHtml():Html
		return cast [this];
	
	@:from static inline function fromHtml(html:Html)
		return new HtmlFragment(html.toString());
		
	@:from static inline function fromString(s:String) 
		return new HtmlFragment(Html.escape(s));
		
	@:from static inline function fromAny<A>(v:A):HtmlFragment
		return fromString(Std.string(v));	
}
	
abstract Html(Array<String>) {
	public inline function new() this = [];	
	
	public function collapse():HtmlFragment
		return new HtmlFragment(toString());
	
	@:to public inline function toString():String
		return this.join('');
	
	public inline function add(b:HtmlFragment)
		this.push(b);
		
	static public inline function fragment(s:String)
		return new HtmlFragment(s);
	
	static public inline function of<A>(value:A)
		return @:privateAccess HtmlFragment.fromAny(value);
	
	// @:from static function ofSingle(f:HtmlFragment)
	
	static public function escape(s:String) {
		if (s == null) return null;
		s = Std.string(s);
		var start = 0,
			pos = 0,
			max = s.length;
		var ret = '';
		
		inline function flush(?entity:String) 
			ret += 
				if (entity == null)
					s.substr(start);
				else
					s.substring(start, (start = pos) - 1) + entity;
		
		while (pos < max) 
			switch s.charAt(pos++) {
				case '"': flush('&quot;');
				case '<': flush('&lt;');
				case '>': flush('&gt;');
				case '&': flush('&amp;');
			}
		flush();
		return ret;
	}

}