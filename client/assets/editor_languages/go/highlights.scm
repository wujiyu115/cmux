; Minimal Go highlight captures for tree-sitter-go.

(comment) @comment

(interpreted_string_literal) @string
(raw_string_literal) @string
(escape_sequence) @string.escape

(int_literal) @number
(float_literal) @number
(imaginary_literal) @number
(rune_literal) @number

[
  (true)
  (false)
  (nil)
  (iota)
] @constant.builtin

[
  "break"
  "case"
  "chan"
  "const"
  "continue"
  "default"
  "defer"
  "else"
  "fallthrough"
  "for"
  "func"
  "go"
  "goto"
  "if"
  "import"
  "interface"
  "map"
  "package"
  "range"
  "return"
  "select"
  "struct"
  "switch"
  "type"
  "var"
] @keyword

(type_identifier) @type
(type_spec
  name: (type_identifier) @type)
(type_alias
  name: (type_identifier) @type)
(struct_type) @type
(interface_type) @type
(map_type) @type
(channel_type) @type
(pointer_type) @type
(func_literal) @function
(function_type) @type

(package_identifier) @type

(identifier) @variable
(field_identifier) @property
(parameter_declaration
  name: (identifier) @variable.parameter)
(var_spec
  name: (identifier) @variable)

(label_name) @label

(function_declaration
  name: (identifier) @function)
(method_declaration
  name: (field_identifier) @function)
(call_expression
  function: (identifier) @function)
(call_expression
  function: (selector_expression
    field: (field_identifier) @function))
(binary_expression
  operator: _ @operator)
(unary_expression
  operator: _ @operator)

[
  "="
  ":="
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
  "&^"
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
  "&^="
  "++"
  "--"
  "<-"
  "+"
  "-"
  "*"
  "/"
  "%"
] @operator
