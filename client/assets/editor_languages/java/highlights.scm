; Minimal Java highlight captures for tree-sitter-java.

(line_comment) @comment
(block_comment) @comment

(string_literal) @string
(string_fragment) @string
(character_literal) @string
(escape_sequence) @string.escape

(decimal_integer_literal) @number
(hex_integer_literal) @number
(octal_integer_literal) @number
(binary_integer_literal) @number
(decimal_floating_point_literal) @number
(hex_floating_point_literal) @number

[
  (true)
  (false)
  (null_literal)
] @constant.builtin

[
  "abstract"
  "assert"
  "break"
  "byte"
  "case"
  "catch"
  "char"
  "class"
  "continue"
  "default"
  "do"
  "double"
  "else"
  "enum"
  "exports"
  "extends"
  "final"
  "finally"
  "float"
  "for"
  "if"
  "implements"
  "import"
  "instanceof"
  "int"
  "interface"
  "long"
  "module"
  "native"
  "new"
  "non-sealed"
  "open"
  "opens"
  "package"
  "permits"
  "private"
  "protected"
  "provides"
  "public"
  "record"
  "requires"
  "return"
  "sealed"
  "short"
  "static"
  "strictfp"
  "switch"
  "synchronized"
  "throw"
  "throws"
  "to"
  "transient"
  "transitive"
  "try"
  "uses"
  "volatile"
  "when"
  "while"
  "with"
  "yield"
] @keyword

(boolean_type) @type.builtin
(void_type) @type.builtin
(integral_type) @type.builtin
(floating_point_type) @type.builtin

(type_identifier) @type
(scoped_type_identifier) @type
(class_declaration
  name: (identifier) @type)
(interface_declaration
  name: (identifier) @type)
(enum_declaration
  name: (identifier) @type)
(record_declaration
  name: (identifier) @type)
(enum_constant
  name: (identifier) @constant)

(annotation) @attribute
(marker_annotation) @attribute

(this) @variable.builtin
(super) @variable.builtin

(identifier) @variable
(field_access
  field: (identifier) @property)
(formal_parameter
  name: (identifier) @variable.parameter)
(catch_formal_parameter) @variable.parameter
(spread_parameter) @variable.parameter

(method_declaration
  name: (identifier) @function)
(method_invocation
  name: (identifier) @function)
(method_reference) @function
(constructor_declaration) @constructor

(labeled_statement
  (identifier) @label)

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
  "|"
  "^"
  "~"
  "<<"
  ">>"
  ">>>"
  "+="
  "-="
  "*="
  "/="
  "%="
  "&="
  "|="
  "^="
  "<<="
  ">>="
  ">>>="
  "++"
  "--"
  "->"
  "::"
  "+"
  "-"
  "*"
  "/"
  "%"
  "?"
  ":"
] @operator
