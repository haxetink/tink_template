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
  
  @:template static function test<T:Object>( conf : TListingConf<T>, iterable : Iterable<T> );
	static var conf	= {
    fields : [
      ELCounter,
      ELID
    ]
  }

  function testIssue13() {
    var it = [ for ( i in 0...10 ) { var o = new MyObj(); o.id = i; o; } ];
		assertTrue( test( conf, it ).toString().length > 0);
  }
  
}

enum EListingField<T:Object> {
	ELCounter;
	ELID;
}

typedef TListingConf<T:Object> = {
	fields : Array<EListingField<T>>
}

#if js
@:native('Blargh') // yup
#end
class Object {
	public var id : Int;
	public function new(){}
}

class MyObj extends Object {
	public var name	: String;
	public function new() super();  
}