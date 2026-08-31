; Minimal Kotlin highlight captures for tree-sitter-kotlin.

(line_comment) @comment
(multiline_comment) @comment

(string_literal) @string
(string_content) @string
(character_literal) @string
(character_escape_seq) @string.escape
(interpolated_identifier) @variable

[
  (integer_literal)
  (hex_literal)
  (bin_literal)
  (long_literal)
  (unsigned_literal)
  (real_literal)
] @number

[
  "true"
  "false"
  "null"
] @constant.builtin

[
  "abstract"
  "actual"
  "annotation"
  "as"
  "as?"
  "break"
  "by"
  "catch"
  "class"
  "companion"
  "constructor"
  "continue"
  "crossinline"
  "data"
  "delegate"
  "do"
  "dynamic"
  "else"
  "enum"
  "expect"
  "external"
  "field"
  "file"
  "final"
  "finally"
  "for"
  "fun"
  "get"
  "if"
  "import"
  "in"
  "infix"
  "init"
  "inline"
  "inner"
  "interface"
  "internal"
  "is"
  "lateinit"
  "noinline"
  "object"
  "open"
  "operator"
  "out"
  "override"
  "package"
  "param"
  "private"
  "property"
  "protected"
  "public"
  "receiver"
  "return"
  "sealed"
  "set"
  "setparam"
  "suspend"
  "tailrec"
  "typealias"
  "val"
  "value"
  "var"
  "vararg"
  "when"
  "where"
  "while"
] @keyword

(property_modifier) @keyword
(reification_modifier) @keyword

(type_identifier) @type
(user_type) @type
(class_declaration
  (type_identifier) @type)
(class_parameter
  (simple_identifier) @variable.parameter)

[
  "this"
  "super"
] @variable.builtin

(identifier) @variable
(simple_identifier) @variable
(parameter
  (simple_identifier) @variable.parameter)
(property_declaration
  (variable_declaration
    (simple_identifier) @property))
(import_header
  (identifier) @type)

(function_declaration
  (simple_identifier) @function)
(constructor_invocation) @constructor
(annotation) @attribute
(label) @label

[
  "="
  "=="
  "!="
  "<"
  ">"
  "<="
  ">="
  "&&"
  "||"
  "!"
  "&"
  "+="
  "-="
  "*="
  "/="
  "%="
  "++"
  "--"
  "->"
  "?:"
  "::"
  ".."
  "+"
  "-"
  "*"
  "/"
  "%"
  ":"
] @operator
