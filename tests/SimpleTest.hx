package ;

using tink.CoreApi;
using StringTools;
using haxe.Json;

@:tink class SimpleTest extends Base {
	function testMisc() {
		Example.print('foo');
		var lines = [for (line in Example.test().toString().split('\n'))
			switch line.trim() {
				case '':
				case v: v;
			}
		];
		assertEquals(["foo 15","14","4","3","2","1","&lt;3","yes!!","-1"].join('##'), lines.join('##'));
	}	
	
	function testSmile() {
		assertEquals(Example.print('foo'), Example2.print('foo'));
	}
	
	function testStache() {
		assertEquals(Example.print('foo'), Example3.print('foo'));
	}
	
	function testMerge() {
		assertEquals(Example.print('foo'), Merged.print('foo'));
		assertEquals(Example.print('foo'), Merged.print('foo'));
		
		var frame = Merged.frame({
			title: 'Hello World', 
			content: 'Hello, Hello!'
		});
		
		
		var title = ~/<title>(.*)<\/title>/;
		assertTrue(title.match(frame));
		assertEquals('Hello World', title.matched(1));
	}
}