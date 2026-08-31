; Minimal C++ highlight captures for tree-sitter-cpp.

(comment) @comment

(string_literal) @string
(raw_string_literal) @string
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
  "alignas"
  "alignof"
  "asm"
  "break"
  "case"
  "catch"
  "class"
  "co_await"
  "co_return"
  "co_yield"
  "compl"
  "concept"
  "const"
  "consteval"
  "constexpr"
  "constinit"
  "continue"
  "decltype"
  "default"
  "delete"
  "do"
  "else"
  "enum"
  "explicit"
  "extern"
  "final"
  "for"
  "friend"
  "goto"
  "if"
  "inline"
  "mutable"
  "namespace"
  "new"
  "noexcept"
  "noreturn"
  "operator"
  "override"
  "private"
  "protected"
  "public"
  "register"
  "requires"
  "restrict"
  "return"
  "sizeof"
  "static"
  "static_assert"
  "struct"
  "switch"
  "template"
  "thread_local"
  "throw"
  "try"
  "typedef"
  "typename"
  "union"
  "using"
  "virtual"
  "volatile"
  "while"
  "_Alignas"
  "_Alignof"
  "_Atomic"
  "_Generic"
  "_Noreturn"
  "defined"
] @keyword

[
  "and"
  "and_eq"
  "bitand"
  "bitor"
  "not"
  "not_eq"
  "or"
  "or_eq"
  "xor"
  "xor_eq"
] @operator

[
  "long"
  "short"
  "signed"
  "unsigned"
] @type.builtin

(primitive_type) @type.builtin
(sized_type_specifier) @type.builtin
(placeholder_type_specifier) @type.builtin
(auto) @type.builtin
(decltype) @type.builtin
(type_identifier) @type
(struct_specifier
  name: (type_identifier) @type)
(class_specifier
  name: (type_identifier) @type)
(enum_specifier
  name: (type_identifier) @type)
(type_definition
  declarator: (type_identifier) @type)
(namespace_identifier) @type
(dependent_name) @type

(identifier) @variable
(field_identifier) @property
(statement_identifier) @label
(namespace_alias_definition
  name: (namespace_identifier) @type)
(parameter_declaration
  declarator: (identifier) @variable.parameter)

(operator_name) @operator
(destructor_name) @function
(function_declarator
  declarator: (identifier) @function)
(call_expression
  function: (identifier) @function)
(call_expression
  function: (field_expression
    field: (field_identifier) @function))
(template_function
  name: (identifier) @function)
(template_method
  name: (field_identifier) @function)

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
  "->*"
  ".*"
  "?"
  ":"
  "::"
  "+"
  "-"
  "*"
  "/"
  "%"
] @operator
