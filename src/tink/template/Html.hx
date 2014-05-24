package tink.template;

abstract Html(String) {
	
	public inline function new(s:String) this = s;
	
	@:from static public function escape(s:String):Html {
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
		return new Html(ret);
	}		
	@:from static function ofMultiple(parts:Array<Html>):Html 
		return new Html(parts.join(''));
		
	@:from static public function of<A>(a:A):Html
		return escape(Std.string(a));
		
	static public function buffer():HtmlBuffer 
		return new HtmlBuffer();
}

abstract HtmlBuffer(Array<Html>) {
	public inline function new() this = [];
	
	public function collapse():Html
		return this;
	
	@:to public inline function toString():String
		return this.join('');
	
	public inline function add(b:Html)
		this.push(b);
		
}