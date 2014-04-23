package tink.template;

#if (js && nodejs)

import haxe.io.*;
import js.Node;

using tink.CoreApi;
using StringTools;

class Reloader implements tink.Lang {
	var name:String = _;
	var file:String = _;
	var params:String = _;
	var port = Std.string(Std.random(10000) + 3001);
	var server:NodeChildProcess = spawn('haxe', ['--wait', port], { cwd: './' });
	var compiling = false;
	
	public function new() 
		js.Node.fs.watch(
			file, 
			{ interval: 500, persistent: false }, 
			function(_, _) compile()
		);
	
	function compile() {
		if (compiling)
			return;
		compiling = true;
		var file = 'tmp_$port.js';
		var invocation = spawn('haxe', ['--connect', port, params, '-js', file, '--macro', 'tink.Template.just("$name")']);
		
		var out = readAll(invocation.stdout),
			err = readAll(invocation.stderr),
			code = exitCode(invocation);
		
		var result = 
			out >> function (out:BytesData) {
				return err >> function (err:BytesData) {
					return code.map() => function (code:Int) {//TODO: find out why >> won't work here
						return {
							out: out,
							err: err,
							code: code,
						};
					}
				};
			}
		
		trace('\n"$name" changed. Recompiling ... [${DateTools.format(Date.now(), "%H:%M:%S")}]');
		result.handle() => @do { compiling = false; };
		result.handle() => @do switch _ {
			case Success(data) if (data.code == 0):
				trace('  Success');
				js.Node.fs.readFile(file, function (err, data) {
					var source:String = data.toString('utf8');
					var end = '})()';					
					var pos = source.lastIndexOf(end);
					
					js.Node.fs.unlink(file, function (_) {});
					
					source = [
						'$name = ',
						source.substr(0, pos),
						'\nreturn $$template;\n',
						source.substr(pos)
					].join('');
					
					try
						js.Lib.eval(source)
					catch (e:Dynamic) {
						trace('  Error while loading template: '+e);
					}
				});
			case Success(data):
				trace('  Compilation Error: ');
				trace(data.err.toString('utf8'));
			case Failure(error):
				trace('  Fatal Error: '+error);
		}
	}
	
	static function exitCode(p:NodeEventEmitter) {
		var ret = Future.trigger();
		p.on('exit') => @do(code)
			ret.trigger(code);
		return ret.asFuture();
	}
	
	static function readAll(r:NodeEventEmitter):Surprise<BytesData, Error> {
		var ret = Future.trigger();
		var buf = [];
		
		r.on('data') => buf.push;
		r.on('error') => @do(error) ret.trigger(Failure(Error.withData('IO error', error)));
		r.on('end') => @do ret.trigger(Success(BytesData.concat(buf)));
		
		return ret.asFuture();
	}
	
	static public function add(name, file, params:String) 
		new Reloader(name, file, params);
	
	static function spawn(cmd:String, params:Array<String>, options = [cwd = './']) 
		return js.Node.child_process.spawn(cmd, params, options);
}
#else
	#error 
#end