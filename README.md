# Tinkerbell Template Library

This library adds support for a `haxe.Template` like string based template language.

Usage is as simple as `-lib tink_template` which will allow all `*.tpl` in your classpaths to be parsed. 
This is accomplished with a `haxe.macro.Context.onTypeNotFound` hook. Therefore the templates are transformed to true Haxe classes at compile time on demand, which gets you the added benefit of type safety and reduces any runtime overload involved in parsing / interpreting the template files. All the while the syntax is quite similar to the original.

### Introduction

Generally speaking, tink templates are meant to become true classes and therefore must declare functions rather than just a hunk of markup. Also the syntax is generally closer to Haxe, rather than having a different language. At expression level, it is a superset of Haxe in fact.

Let's use the `haxe.Template` example for a comparison, first setting up our data:

```
class User {
    var name : String;
    var age : Int;
    public function new(name,age) {
        this.name = name;
        this.age = age;    
    }
}

class Town {
  var name : String;
  var users : Array<User>;
  public function new( name ) {
    this.name = name;
    users = new Array();
  }
  public function addUser(u) {
    users.push(u);
  }
  static public var PARIS = {
  var town = new Town("Paris");
    town.addUser(new User("Marcel", 88));
    town.addUser(new User("Julie", 15));
    town.addUser(new User("Akambo", 2));
    town;
  }
```

This is the standard template to produce our output:

```
The habitants of <em>::name::</em> are :
<ul>
::foreach users::
  <li>
    ::name:: 
    ::if (age > 18)::Grown-up::   (age <= 2)::Baby::else::Young::end::
  </li>
::end::
</ul>
```

which we would save in `sample.mtt` and add to the output per `-resource sample.mtt@my_sample` thus enabling us to render the template with `new haxe.Template(haxe.Resource.getString("my_sample")).execute(Town.PARIS)`.

With `tink_template` we would instead put the following content into `View.tpl` in our class path:

```
::static function town(t:Town)::
  The habitants of <em>::t.name::</em> are :
  <ul>
    ::for u in t.users::
      <li>
        ::u.name::
        ::if u.age > 18::Grown-up::elseif u.age <= 2::Baby::else::Young::end::
      </li>
    ::end::
  </ul>
::end::
```

And then when compiling with `-lib tink_template` we could render the template with `View.town(Town.PARIS)`.

As you can see, the for loop looks more like a Haxe loop. Parentheses can be omitted in flow statements. And generally the content is wrapped in a function. A static one at that, which we later use to render the template. That means that we can also do things like this:

```
::static function user(u:User)::
  ::u.name::
  ::if u.age > 18::Grown-up::elseif u.age <= 2::Baby::else::Young::end::
::end::

::static function town(t:Town)::
  The habitants of <em>::t.name::</em> are :
  <ul>
    ::for u in t.users::
      <li>::user(u)::</li>
    ::end::
  </ul>
::end::
```

Allowing us now to render a single `User` with `View.user(someUser)`. Notice how the template itself calls one function from another. Awesome.

### Incompatibilites

Effectively, this leads to the following incompatibilities to `haxe.Template`:

1. Tink templates always have to be embedded in functions.
2. There are no template macros, because you can just use normal (or template) functions.
3. The encouraged loop syntax is different in that it requires a variable instead of importing all fields of the current iteration into the local context. 
4. Tink templates are type checked, so certain code doesn't necessarily compile although that should be easy to fix.

## Template syntax

As with `haxe.Template` all logic is contained between pairs of `::`. Not that it's pretty, but it's compatible. Alternative syntax will be added in the future.

### Expressions

Special expressions start with a keyword. All other expressions are added to the output. Output is escaped depending on its type.

#### Not outputting

To have code that causes side effects but no ouput, you can use `::do $expr::`, e.g. `::do i++::` which will just increment the variable as opposed to `::i++::` which will also print its value.

#### Conditionals

Conditionals work exactly as in `haxe.Template` you have an `::if $expr::`, which can be followed by a sequence of `::elseif $expr` clauses (note that `::else if $expr::` is also valid) and an optional `::else::` clause, as seen in the above example, i.e. `::if u.age > 18::Grown-up::elseif u.age <= 2::Baby::else::Young::end::`.

#### Switch

Switch statements are quite similar to Haxe but don't support guard clauses yet. Example:

```
::switch fruit::
  ::case 'kiwi', 'lemon':: sour
  ::case 'banana':: sweet
  ::case v:: unknown
::end::
```

Note that there is no `default` branch as you can use a capture-all case statement.

#### For loops

For loops look a lot like their Haxe counterpart, as seen in the example above:

```
::for u in t.users::
  <li>::user(u)::</li>
::end::
```

There's not much to it, really.

##### Foreach loops

For compatibility reasons, there's also support for foreach loops, but they are discouraged.

#### While loops

While loops are pretty much what you would expect them to be:

```
::var it = t.users.iterator()::
::while it.hasNext()::
  <li>::user(it.next())::</li>
::end::
```

There are no `do while` loops, mostly because that would require a proper parser. You can emulate them this way:

```
::var first = true::
::while first || actualCondition::
	::do first = false::
	Body goes here
::end::
```

#### Loop else

All loops can have an else branch that is executed if the loop has 0 iterations.

```
::for u in t.users::
  <li>::user(u)::</li>
::else::
  <li>This is a ghost town</li>
::end::
```

#### Variables

Variables can be declared in two different ways. A variable declaration itself causes no output.

##### Template Variables

Template variables are initialized with some template code which ends with a corresponding `::end::`, e.g.: 

```
::var head::
	<head>
		<title>::t.name::</title>
	</head>		
::end::
```

Therefore `::head::` will now cause the output `<head><title>Paris</title></head>` (whitespace removed for convenience).

##### Plain Variables

As opposed to template variables, these are variables that are initialized to normal Haxe values and are defined as `::var name = expr::`. If you need a plain variable, you must always initialize it. You can use `null` if you don't have a sensible value at hand.

#### Functions

Similarly to variables, there are two types of functions.

##### Template functions

Template functions are syntactically distinguished by the fact that the argument list is followed by a `::` which begins the body that contains everything until the corresponding `::end::`.

This would be a valid template function:

```
::function user(u:User)::
  ::u.name::
  ::if u.age > 18::Grown-up::elseif u.age <= 2::Baby::else::Young::end::
::end::
```

##### Plain Functions

All other functions are plain functions, an example being this one:

```
::function ageGroup(u:User)
  return 
    if (u.age > 18) 'Grown-up';
    else if (u.age <= 2) 'Baby';
    else 'Young';
::
```

#### Metadata

You can use expression level metadata on all expressions. It will be forwarded to the output and can be picked up by other macros later. Syntax is just like with Haxe. Example:

```
::@foo for i in 0...5::
  <li>::@bar i::</li>
::end::
```

### Member declarations

Member declarations work exactly like variable and function declarations, only they can have the common access modifiers (`static`, `private`, ...). Note that by default, all members are `public` and you must declare them `private` explicitly (seems fair for templates, no?).

At the top level, you may only have member declarations. And whitespace.

## Escaping

With `tink_template` all values are escaped by default. To prevent double escaping and such, the work is actually pushed to the type system.

```
abstract Html {
  static public function fragment(raw:String):Html;
  
  @:from static public function escape(s:String):Html;
  @:from static function ofMultiple(parts:Array<Html>):Html;
  @:from static function ofAny<A>(a:A):Html;
}
```

The return value of every template function and the type of every template variable is `tink.template.Html`, which is why it's not escaped a second time when inserted into another template string. You can use `Html.fragment` to convert a string without escaping it. In all other cases some sensible implicit conversion should occur.

The whole point of `ofMultiple` is that `someArray.map(templateFunction)` produces sensible output.

### Other formats

....

## Entrypoints

Templates can act as entrypoints (e.g. `-main` class), in which case a number of things is going to happen under the default assumption that you want to write a web app using SPOD and `haxe.web.Dispatch`. If you want a different behavior, you can register a handler with `tink.Template.mainify` that generates a different `main` method and returns `true` if you want to prevent any other default behavior.

Since `Dispatch` does not do any printing, any template functions eligible for dispatch (e.g. prefixed with `do`) will be adjusted to not return but rather print the result.

If no main function is present, it will be generated so that:

1. If you're using SPOD, then code is generated to initialize the db connection.
2. The main function dispatches onto the current class object.

You can just provide your own main function if you prefer.

Also, if you wish to instantiate the template class and dispatch onto instance methods, here's how you could do that:

```
::function new() {
  
}::
::function doFoo() {
}::
::static function doDefault(d:haxe.web.Dispatch) {
  d.dispatch(new ThisClass());
}::
```












