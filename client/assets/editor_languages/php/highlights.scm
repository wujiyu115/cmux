; Minimal PHP highlight captures for tree-sitter-php.

(comment) @comment

(string) @string
(string_content) @string
(heredoc) @string
(heredoc_body) @string
(nowdoc) @string
(nowdoc_body) @string
(escape_sequence) @string.escape

(integer) @number
(float) @number

[
  (boolean)
  "null"
] @constant.builtin

(cast_type) @type.builtin
(primitive_type) @type.builtin

[
  "abstract"
  "and"
  "array"
  "as"
  "break"
  "case"
  "catch"
  "class"
  "clone"
  "const"
  "continue"
  "declare"
  "default"
  "do"
  "echo"
  "else"
  "elseif"
  "enum"
  "exit"
  "extends"
  "final"
  "finally"
  "fn"
  "for"
  "foreach"
  "function"
  "global"
  "goto"
  "if"
  "implements"
  "include"
  "include_once"
  "instanceof"
  "insteadof"
  "interface"
  "list"
  "match"
  "namespace"
  "new"
  "or"
  "print"
  "private"
  "protected"
  "public"
  "readonly"
  "require"
  "require_once"
  "return"
  "static"
  "switch"
  "throw"
  "trait"
  "try"
  "unset"
  "use"
  (var_modifier)
  "while"
  "xor"
  "yield"
  "yield from"
] @keyword

[
  "self"
  "parent"
] @variable.builtin

(name) @variable
(variable_name) @variable
(dynamic_variable_name) @variable

(simple_parameter
  name: (variable_name) @variable.parameter)
(property_element
  (variable_name) @property)

(function_definition
  name: (name) @function)
(method_declaration
  name: (name) @function)
(function_call_expression
  function: (name) @function)
(function_call_expression
  function: (qualified_name
    (name) @function))
(scoped_call_expression
  name: (name) @function)
(member_call_expression
  name: (name) @function)
(object_creation_expression
  (name) @constructor)
(object_creation_expression
  (qualified_name
    (name) @constructor))

(class_declaration
  name: (name) @type)
(interface_declaration
  name: (name) @type)
(trait_declaration
  name: (name) @type)
(enum_declaration
  name: (name) @type)
(namespace_name
  (name) @type)
(class_constant_access_expression
  (name) @constant)

(attribute) @attribute

(named_label_statement) @label

(binary_expression
  operator: _ @operator)
(unary_op_expression
  operator: _ @operator)
(augmented_assignment_expression
  operator: _ @operator)
(error_suppression_expression) @operator

[
  "="
  "=="
  "==="
  "!="
  "!=="
  "<"
  ">"
  "<="
  ">="
  "<=>"
  "&&"
  "||"
  "!"
  "&"
  "|"
  "^"
  "~"
  "<<"
  ">>"
  "+="
  "-="
  "*="
  "/="
  ".="
  "%="
  "**"
  "**="
  "++"
  "--"
  "=>"
  "->"
  "?->"
  "??"
  "??="
  "."
  "+"
  "-"
  "*"
  "/"
  "%"
  "?"
  ":"
] @operator
