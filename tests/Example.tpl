::implements tink.Lang::

::@:foo(1, 2, 3) static function print(title)::
<html>
	<head>
		<title>::title::</title>
	</head>
	<body>
		<h1>YO!</h1>
		<p>This mah template, yo!</p>
		::function dup(x) return x * 2::
		<ol>
			::for i in 0...3::
				<li>::dup(i)::</li>
			::end::
		</ol>
		
		::foreach ['fooo', 'bar']::
			::length::
		::end::
	</body>
</html>
::end::

::static function test()::
	::var x = 15::
	::while x > 1::
		::switch x::
			::case 14:: ::x = 4::
			::case v:: ::--x::
		::end::
	::end::
	::while false::
	::else::
		yes!!
	::end::
	::while x > 0::
		::x = -1::
	::else::
		no!!
	::end::
	
::end::

::static function main() {
	trace(test());
}::

::static function doUser(u:Db.User)::
	
::end::

::static function doDefault()::
<html>
	<head>
		<title>Test</title>
	</head>
	<body>
		<h1>Welcome</h1>
		<p>This is awesome</p>
	</body>
</html>
::end::

::static function doFoo()::
::end::

::static var foo = 5::