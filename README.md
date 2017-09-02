# Tinkerbell Template Library
[![Gitter](https://img.shields.io/gitter/room/nwjs/nw.js.svg?maxAge=2592000)](https://gitter.im/haxetink/public)

This library adds compile time support for a `haxe.Template` like string based template language. Using it, templates always end up as actual methods on Haxe classes. Think of it as a superset of Haxe, that makes concatenating strings particularly easy. It is still statically typed and supports using, macros and what not.

Be sure to also check out [hhp](https://github.com/RealyUniqueName/HHP) - a "PHP-like templating system for Haxe" - for a similar yet different approach.

## Modes

The library supports two modes:
  
1. `mtt` (Motion Twin Template): This is practically a legacy mode (although admittedly it is what I have been using for the past 2 years) aiming to be rather close to `haxe.Template` using `::` to designate template statements and allowing `foreach` loops.
2. `tt` (Tink Template): A mode designating statements between `(:` and `:)`. That's right, a template language based on smileys - how cool is that? :)

The mode is determined by template file extension.

### Custom modes

Other modes can be added like so:

```haxe
--macro tink.Template.addFlavor('ext1,ext2,ext3', 'beginStatement', 'endStatement', allowForeach)
```

While this can easily be mistaken for an opportunity to obsess over syntax, it mostly for these uses:
  
1. Use `tink_template` on other file extensions, e.g. to simply get the `mtt` syntax in `.html` files, you can do

 ```haxe 
 --macro tink.Template.addFlavor('html', '::', '::', true)
 ```
2. Use different delimiters, because they have a meaning in the language you are generating (you could have templates that create templates for example)
3. Make it a bit less tedious to consume other syntax, e.g. to parse a subset of moustache templates, you could simply do

 ```
 --macro tink.Template.addFlavor('moustache', '{{', '}}')
 ```

# Usage

With `-lib tink_template` there are three different ways to use templates:

1. template fields
2. template frontend
3. class template mixin

Let's have a look at those!

## Template fields

This approach comes down to something very similar to haxe templates. The templates are added to fields by giving them a `@:template` metadata.

### Template Resolution

When templates are specified with the `@:template` metadata, there are two possibilities:

1. `@:template`: This will look in the current package for any file matching the field name.
2. `@:template("filename.mode")`: This will look for the given file name in the current package and parse it with the mode as defined by the extension.

Note that to find the template file, `tink_template` looks into *all* classpaths. This is to give you the option to have your templates and haxe files in different folders, although it is actually suggested to keep them together.

### Basic example

Let's use the `haxe.Template` example for a comparison, first setting up our data:

```haxe
class User {
  public var name : String;
  public var age : Int;
  public function new(name,age) {
    this.name = name;
    this.age = age;    
  }
}

class Town {
  public var name : String;
  public var users : Array<User>;
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
}
```

This is the standard template to produce our output:

```html
The habitants of <em>::name::</em> are :
<ul>
::foreach users::
  <li>
    ::name:: 
    ::if (age > 18)::Grown-up::elseif (age <= 2)::Baby::else::Young::end::
  </li>
::end::
</ul>
```

With `haxe.Template` we would save in `renderTown.mtt` and add to the output per `-resource renderTown.mtt@renderTown` thus enabling us to render the template with `new haxe.Template(haxe.Resource.getString("renderTown")).execute(Town.PARIS)`.

With `tink_template`, we would do this little change:

```haxe
class Town {
  public var name : String;
  public var users : Array<User>;
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
  @:template function renderTown();// <---- this bit is new!
}
```

And now we could simply say `Town.PARIS.renderTown()` and get our html as a result. You might be a bit stumped by the fact that we're basically throwing the view and the model together. Whether or not that is good is for you to decide. You could just as easily render the template like `Views.renderTown(Town.PARIS)` after declaring this:

```haxe
class Views {
  @:template static public function renderTown(t:Town);
}
```

That would however require you to change the template like so:
  
```html
The habitants of <em>::t.name::</em> are :
<ul>
::foreach t.users::
  <li>
    ::name:: 
    ::if (age > 18)::Grown-up::elseif (age <= 2)::Baby::else::Young::end::
  </li>
::end::
</ul>
```

Why? Well, in the first case `renderTown` became a method of town and thus had access to `name` and `users`. In the second example, it needs to access them through the argument `t`, much like any normal Haxe code would. If you run this code, you may notice a compiler warning, because of the foreach loop. That's nothing to be alarmed about. We will look into this later on, when we examine the template syntax more closely.

### Template Expression Syntax

From this point forward the code samples will use the `tt` flavor, because of the clear distinction it makes between start and end of a template stament.
Special statements start with a keyword. Anything else is considered a Haxe expression and if successfully parsed is added to the output, [escaped depending on its type](#escaping).

#### Comments

Any template statement that starts and ends with an `*` is considered a comment, e.g `::* comment *::` in `mtt` mode and `(:* comment *)` in `tt` mode.

#### Not outputting

To have code that causes side effects but no ouput, you can use `(: do $expr :)`, e.g. `(: do i++ :)` which will just increment the variable as opposed to `(: i++ :)` which will also print its value prior to incrementing.

#### Conditionals

Conditionals work exactly as in `haxe.Template` as shown above: You have an `(: if $expr :)`, which can be followed by a sequence of `(: elseif $expr :)` clauses and an optional `(: else :)` and finally terminated by `(: end :)`.

#### Switch

Switch statements are quite similar to Haxe. Example:

```
(: switch fruit :)
  (: case 'kiwi', 'lemon' :) sour
  (: case 'banana' :) sweet
  (: case v :) unknown
(: end :)
```

Note that there is no `default` branch as you can use a capture-all case statement.

#### For loops

For loops look a lot like their Haxe counterpart:

```
(: for u in t.users :)
  <li>(: user(u) :)</li>
(: end :)
```

There's not much to it, really.

##### Foreach loops

For compatibility reasons, there's also support for `foreach` loops in `mtt` mode, but they are discouraged for the same reasons `with` statements in JavaScript are.

#### While loops

While loops are pretty much what you would expect them to be:

```
(: var it = t.users.iterator() :)
(: while it.hasNext() :)
  <li>(: user(it.next()) :)</li>
(: end :)
```

There are no `do while` loops, mostly because that would require a proper parser. You can emulate them this way:

```
(: var first = true :)
(: while first || actualCondition :)
  (: do first = false :)
  Body goes here
(: end :)
```

#### Loop else

All loops can have an else branch that is executed if the loop has 0 iterations.

```
(: for u in t.users :)
  <li>(: user(u) :)</li>
(: else :)
  <li>This is a ghost town</li>
(: end :)
```

#### Variables

Variables can be declared in two different ways. A variable declaration itself causes no output.

##### Template Variables

Template variables are initialized with some template code which ends with a corresponding `(: end :)`, e.g.: 

```
(: var head :)
  <head>
    <title>(: t.name :)</title>
  </head>    
(: end :)
```

Therefore `(: head :)` will now cause the output `<head><title>Paris</title></head>` (whitespace removed for convenience).

##### Plain Variables

As opposed to template variables, these are variables that are initialized to normal Haxe values and are defined as `(: var name = expr :)`. If you need a plain variable, you must always initialize it. You can use `null` if you don't have a sensible value at hand.

#### Functions

Similarly to variables, there are two types of functions.

##### Template functions

Template functions are syntactically distinguished by the fact that the argument list is followed by a ` :)` which begins the body that contains everything until the corresponding `(: end :)`.

This would be a valid template function:

```
(: function user(u:User) :)
  (: u.name :)
  (: if u.age > 18 :) Grown-up (: elseif u.age <= 2 :) Baby (: else :) Young (: end :)
(: end :)
```

##### Plain Functions

All other functions are plain functions, an example being this one:

```
(: function ageGroup(u:User)
  return 
    if (u.age > 18) 'Grown-up';
    else if (u.age <= 2) 'Baby';
    else 'Young';
:)
```

Anything until the closing delimiter is considered part of the body.

#### Expression Level Metadata

You can use expression level metadata on all expressions. It will be forwarded to the output and can be picked up by other macros later. Syntax is just like with Haxe. Example:

```html
(: @foo for i in 0...5 :)
  <li>(: @bar i :)</li>
(: end :)
```

## Template Frontend

While above we have seen a compile time alternative to `haxe.Template` with some added syntax, this approach more radical: it interprets a template as a whole standalone class. Imagine we put this in a `Views.tt` in our classpath:

```html
(: static function renderTown(t:Town) :)
  The habitants of <em>(: t.name :)</em> are :
  <ul>
  (: for u in t.users :)
    <li>
      (: u.name :)
      (: if u.age > 18 :) Grown-up (: elseif u.age <= 2 :) Baby (: else :) Young (: end :)
    </li>
  (: end :)
  </ul>
(: end :)
```

Now, just as above with the template fields, we can render our template with `Views.renderTown(Town.PARIS)`. The main advantage of this approach is that the markup and the data signature is in one single place.

### Valid top level declarations

In a standalone template, you can declare the following things:

#### Metadata

You can use arbitrary metadata like `(: @tagName(expr1, expr2) :)`. Particularly useful if you want to use `tink_lang`.

#### Import, Using, Implements and Extends

You can all those statements between the mode-specific delimiters like so:

```haxe
(: using foo.bar.Baz :)
(: import foo.bar.Baz :)
(: import foo.bar.* :)
(: import foo.bar.Baz in Frozzle :)

(: implements my.Interface<Int> :)
(: extends my.BaseClass :)
```

#### Fields

Fields work pretty much like variables and functions, except that they can have access modifiers and accessors in the case of fields. You can have template variables and plain variables and the same goes for methods. Here's an example:

```haxe
(: static var headline :)
  <h1>Important Heading</h1>
(: end :)

(: static var AGE_GROUPS = [
  { from: 18, name: 'Grown-up' },
  { from: 3, name: 'Young' },
  { from: 0, name: 'Baby' },
] :)

(: static function renderTown(t:Town) :)
  
  (: headline :)
  
  The habitants of <em>(: t.name :)</em> are :
  <ul>
  (: for user in t.users :)
    <li>
      (: user.name :)
      (: ageGroup(user) :)
    </li>
  (: end :)
  </ul>
(: end :)

(: static private function ageGroup(u:User) 
  for (group in AGE_GROUPS)
    if (u.age >= group.from) return group.name;
  throw 'unreachable';
:)
```

## Class Template Mixin

If you are uncomfortable with not having a `.hx` file for your Haxe class, or if you have a lot of plain Haxe code that it would feel silly to put into the template, you can mix a template into a class with the `@:template` metadata, which follows [the same resolution logic as for fields](#template-resolution).

However, in mixed in templates you cannot use `implements`, `extends`, `using` or `import` due to limitations in the macro API. You should write them in the `.hx` file instead.

# Escaping

With `tink_template` all values are escaped by default. To prevent double escaping and such, the work is actually pushed to the type system.

```haxe
abstract Html {
  public function new(s:String):Void;

  @:from static public function escape(s:String):Html;
  @:from static function ofMultiple(parts:Array<Html>):Html;
  
  @:from static public function of<A>(a:A):Html;
}
```

The return value of every template function and the type of every template variable is `tink.template.Html`, which is why it's not escaped a second time when inserted into another template string. You can use the constructor to convert a string without escaping it. In all other cases some sensible implicit conversion should occur.

The whole point of `ofMultiple` is that `someArray.map(templateFunction)` produces sensible output.

# Other formats

Support for other formats such as plaintext output (i.e. without the escaping) is planned.

# Philosophy

Most template engines come with a rigid philosophy. The concept of a template engine itself usually already is coupled with an imposed restriction on what a template may or may not do. Some template engines go as far as embracing logic less templates and what not.

Let's examine the motivations a bit closer:

1. Not letting the host language bleed into the template language increases the portability of the template.
2. Separation of concern is good.

The first argument may generally hold, but it evaporates in the light of Haxe's portability. The whole point of using Haxe is to not have to switch languages in the first place.

The second argument is sound. Separation of concerns is desirable for an almost unending list of reasons. 

However, strictly separating templates and logic impedes the separation also. For example with haxe templates we can observe that anything non-trivial immediately becomes difficult, requiring the calling code to provide macros, thus being forced not only to provide the data, but also operations on it, thereby having intimate knowledge on what operations are needed. Also nesting templates directly is impossible. The calling code again needs to do the nesting and at the bottom line you find yourself having a lot of what is your presentation logic in your controllers, rather than the views.

While `tink_template` makes no attempt to make it hard for you to spaghettify your views, what it really focuses on is to make it easy to put all your rendering logic into the views, keeping it out from your controllers and models. No formatting of dates, assembling of tree structures, localization or whatever else is actually a presentational concern - none of it ends up anywhere but in the view for any other reason than you wanting to single it out. In essence `tink_template` aims to make it easier for you not to spaghettify your controllers.

There is no concept of partials or macros. Just Haxe functions. The well known semantics you use for anything else. Arguments in, return value out - only the returned value happens to be HTML in some cases and you're handed a Haxe dialect with which it's easier to render. You get to decide how to separate your concerns. It's hard enough without the tool you're using trying to force its author's opinion onto you. By the way, this author thinks that templates should be descriptive and referentially transparent, as should all code, if possible. But that's your problem ;)

## Position comments

You can use `-D tink_template_pos=on|off` to toggle position comments (that allow you to identify the source in the generated HTML). The switch defaults to `on` in `-debug` mode, and `off` otherwise.
