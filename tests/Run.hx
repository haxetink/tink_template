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
  static function main() 
    travix.Logger.exit({
      var r = new TestRunner();
      for (c in tests)
        r.add(c);
      if (r.run()) 0
      else 500;
    });


}