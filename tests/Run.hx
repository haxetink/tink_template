package ;

import haxe.unit.*;

using tink.CoreApi;

#if flash
private typedef Sys = flash.system.System;
#end
class Run {
  static var tests:Array<TestCase> = [
    new SimpleTest()
  ];
  static function main() {  
    #if js//works for nodejs and browsers alike
    var buf = [];
    TestRunner.print = function (s:String) {
      var parts = s.split('\n');
      if (parts.length > 1) {
        parts[0] = buf.join('') + parts[0];
        buf = [];
        while (parts.length > 1)
          untyped console.log(parts.shift());
      }
      buf.push(parts[0]);
    }
    #end  
    
    var r = new TestRunner();
    for (c in tests)
      r.add(c);
    if (!r.run())
      Sys.exit(500);
  }

}