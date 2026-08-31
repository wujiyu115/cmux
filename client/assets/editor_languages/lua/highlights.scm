; Minimal Lua highlight captures for tree-sitter-lua.

(identifier) @variable

(function_declaration
  name: (identifier) @function)
(function_declaration
  name: (dot_index_expression
    field: (identifier) @function))
(function_declaration
  name: (method_index_expression
    method: (identifier) @function))

(function_call
  name: (identifier) @function)
(function_call
  name: (dot_index_expression
    field: (identifier) @function))
(function_call
  name: (method_index_expression
    method: (identifier) @function))

(parameters
  (identifier) @variable.parameter)

(field
  name: (identifier) @property)

(dot_index_expression
  field: (identifier) @property)

(variable_list
  (attribute
    (identifier) @attribute))

(label_statement) @label

(break_statement) @keyword

[
  (nil)
  (true)
  (false)
  (vararg_expression)
] @constant.builtin

(number) @number
(comment) @comment
(hash_bang_line) @comment
(string) @string
(escape_sequence) @string.escape

(binary_expression
  operator: _ @operator)

(unary_expression
  operator: _ @operator)

[
  "="
  "and"
  "not"
  "or"
] @operator

[
  "do"
  "else"
  "elseif"
  "end"
  "for"
  "function"
  "global"
  "goto"
  "if"
  "in"
  "local"
  "repeat"
  "return"
  "then"
  "until"
  "while"
] @keyword
