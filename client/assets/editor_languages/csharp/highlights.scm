; Minimal C# highlight captures for tree-sitter-c-sharp.

(comment) @comment

(string_literal) @string
(string_literal_content) @string
(verbatim_string_literal) @string
(raw_string_literal) @string
(raw_string_content) @string
(character_literal) @string
(escape_sequence) @string.escape

(integer_literal) @number
(real_literal) @number

[
  "true"
  "false"
  (null_literal)
] @constant.builtin

(predefined_type) @type.builtin

[
  "abstract"
  "as"
  "async"
  "await"
  "base"
  "break"
  "case"
  "catch"
  "checked"
  "class"
  "const"
  "continue"
  "default"
  "delegate"
  "do"
  "else"
  "enum"
  "event"
  "explicit"
  "extern"
  "finally"
  "fixed"
  "for"
  "foreach"
  "get"
  "goto"
  "if"
  "implicit"
  "in"
  "init"
  "interface"
  "internal"
  "is"
  "lock"
  "namespace"
  "new"
  "not"
  "notnull"
  "operator"
  "or"
  "out"
  "override"
  "params"
  "partial"
  "private"
  "protected"
  "public"
  "readonly"
  "record"
  "ref"
  "remove"
  "required"
  "return"
  "sealed"
  "set"
  "sizeof"
  "stackalloc"
  "static"
  "struct"
  "switch"
  "throw"
  "try"
  "typeof"
  "unchecked"
  "unsafe"
  "using"
  "var"
  "virtual"
  "volatile"
  "when"
  "where"
  "while"
  "with"
  "yield"
] @keyword

(identifier) @variable
(member_access_expression
  name: (identifier) @property)
(member_binding_expression
  name: (identifier) @property)
(parameter
  name: (identifier) @variable.parameter)
(variable_declarator
  name: (identifier) @variable)

(method_declaration
  name: (identifier) @function)
(local_function_statement
  name: (identifier) @function)
(invocation_expression
  function: (identifier) @function)
(invocation_expression
  function: (member_access_expression
    name: (identifier) @function))
(constructor_declaration
  name: (identifier) @constructor)
(destructor_declaration
  name: (identifier) @constructor)

(class_declaration
  name: (identifier) @type)
(struct_declaration
  name: (identifier) @type)
(interface_declaration
  name: (identifier) @type)
(record_declaration
  name: (identifier) @type)
(enum_declaration
  name: (identifier) @type)
(namespace_declaration
  name: (qualified_name) @type)
(generic_name) @type
(type_parameter) @type

(attribute) @attribute
(attribute_list) @attribute

"this" @variable.builtin
"base" @variable.builtin

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
  "??"
  "??="
  "=>"
  "++"
  "--"
  "->"
  "+"
  "-"
  "*"
  "/"
  "%"
  "?"
  ":"
  "::"
] @operator
