; Minimal Ruby highlight captures for tree-sitter-ruby.

(comment) @comment

(string) @string
(bare_string) @string
(string_array) @string
(heredoc_body) @string
(escape_sequence) @string.escape
(character) @string
(regex) @string

(integer) @number
(float) @number

[
  (true)
  (false)
  "nil"
] @constant.builtin

[
  "BEGIN"
  "END"
  "alias"
  "and"
  "begin"
  "break"
  "case"
  "class"
  "def"
  "defined?"
  "do"
  "else"
  "elsif"
  "end"
  "ensure"
  "for"
  "if"
  "in"
  "module"
  "next"
  "not"
  "or"
  "redo"
  "rescue"
  "retry"
  "return"
  "then"
  "undef"
  "unless"
  "until"
  "when"
  "while"
  "yield"
] @keyword

[
  (file)
  (line)
] @constant.builtin

[
  (self)
  (super)
] @variable.builtin

(constant) @type
(scope_resolution
  name: (constant) @type)
(class
  name: [
    (constant)
    (scope_resolution
      name: (constant))
  ] @type)
(module
  name: [
    (constant)
    (scope_resolution
      name: (constant))
  ] @type)

(identifier) @variable
(instance_variable) @property
(class_variable) @property
(global_variable) @variable

[
  (simple_symbol)
  (delimited_symbol)
  (bare_symbol)
  (hash_key_symbol)
  (symbol_array)
] @constant

(method
  name: [
    (identifier)
    (setter)
    (operator)
  ] @function)
(singleton_method
  name: [
    (identifier)
    (setter)
    (operator)
  ] @function)
(call
  method: (identifier) @function)
(method_parameters
  (identifier) @variable.parameter)
(block_parameters
  (block_parameter
    (identifier) @variable.parameter))
(optional_parameter
  name: (identifier) @variable.parameter)

[
  "="
  "=="
  "!="
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
  "%="
  "**"
  "**="
  "=>"
  "->"
  "+"
  "-"
  "*"
  "/"
  "%"
  "?"
  ":"
  ".."
  "..."
  "::"
] @operator

(interpolation) @emphasis
