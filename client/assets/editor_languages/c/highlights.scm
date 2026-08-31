; Minimal C highlight captures for tree-sitter-c.

(comment) @comment

(string_literal) @string
(char_literal) @string
(escape_sequence) @string.escape
(system_lib_string) @string
(number_literal) @number

[
  (true)
  (false)
  (null)
  "NULL"
  "nullptr"
] @constant.builtin

(enumerator
  name: (identifier) @constant)

(preproc_directive) @keyword
(preproc_ifdef
  name: (identifier) @constant)
(preproc_arg) @string

[
  "auto"
  "break"
  "case"
  "const"
  "constexpr"
  "continue"
  "default"
  "do"
  "else"
  "enum"
  "extern"
  "for"
  "goto"
  "if"
  "inline"
  "noreturn"
  "register"
  "restrict"
  "return"
  "sizeof"
  "static"
  "struct"
  "switch"
  "thread_local"
  "typedef"
  "union"
  "volatile"
  "asm"
  "alignas"
  "alignof"
  "_Alignas"
  "_Alignof"
  "_Atomic"
  "_Generic"
  "_Noreturn"
  "defined"
] @keyword

[
  "long"
  "short"
  "signed"
  "unsigned"
] @type.builtin

(primitive_type) @type.builtin
(type_identifier) @type
(sized_type_specifier) @type.builtin
(struct_specifier
  name: (type_identifier) @type)
(enum_specifier
  name: (type_identifier) @type)
(type_definition
  declarator: (type_identifier) @type)

(identifier) @variable
(field_identifier) @property
(statement_identifier) @label
(parameter_declaration
  declarator: (identifier) @variable.parameter)

(function_declarator
  declarator: (identifier) @function)
(call_expression
  function: (identifier) @function)
(call_expression
  function: (field_expression
    field: (field_identifier) @function))

(binary_expression
  operator: _ @operator)
(unary_expression
  operator: _ @operator)
(assignment_expression
  operator: _ @operator)
(update_expression
  operator: _ @operator)
(field_expression
  operator: _ @operator)

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
  "++"
  "--"
  "->"
  "?"
  ":"
  "+"
  "-"
  "*"
  "/"
  "%"
] @operator
