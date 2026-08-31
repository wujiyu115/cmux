; Minimal Swift highlight captures for tree-sitter-swift.

(comment) @comment
(multiline_comment) @comment

(line_string_literal) @string
(multi_line_string_literal) @string
(raw_string_literal) @string
(str_escaped_char) @string.escape

[
  (integer_literal)
  (hex_literal)
  (oct_literal)
  (bin_literal)
  (real_literal)
] @number

[
  "true"
  "false"
  "nil"
] @constant.builtin

[
  "actor"
  "as"
  "as!"
  "as?"
  "associatedtype"
  "async"
  "await"
  "borrowing"
  "break"
  "case"
  "class"
  "continue"
  "convenience"
  "deinit"
  "didSet"
  "do"
  "dynamic"
  "enum"
  "extension"
  "fallthrough"
  "fileprivate"
  "final"
  "for"
  "func"
  "get"
  "guard"
  "if"
  "import"
  "in"
  "indirect"
  "infix"
  "init"
  "inout"
  "internal"
  "is"
  "lazy"
  "let"
  "mutating"
  "nonmutating"
  "open"
  "operator"
  "optional"
  "override"
  "package"
  "postfix"
  "precedencegroup"
  "prefix"
  "private"
  "protocol"
  "public"
  "repeat"
  "required"
  "return"
  "self"
  "set"
  "some"
  "static"
  "struct"
  "subscript"
  "super"
  "switch"
  "try"
  "typealias"
  "unowned"
  "var"
  "weak"
  "while"
  "willSet"
] @keyword

[
  (catch_keyword)
  (default_keyword)
  (throw_keyword)
  (where_keyword)
  (throws)
  (else)
] @keyword

(type_identifier) @type
(user_type) @type
(class_declaration
  name: (type_identifier) @type)
(protocol_declaration
  name: (type_identifier) @type)
(typealias_declaration
  name: (type_identifier) @type)
(metatype) @type

(simple_identifier) @variable
(identifier) @variable
(parameter
  name: (simple_identifier) @variable.parameter)
(property_declaration
  (pattern
    (simple_identifier) @property))
(navigation_suffix
  (simple_identifier) @property)

(function_declaration
  name: (simple_identifier) @function)
(protocol_function_declaration
  name: (simple_identifier) @function)
(init_declaration) @constructor
(call_expression
  (simple_identifier) @function)
(attribute) @attribute
(statement_label) @label

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
  "++"
  "--"
  "->"
  "??"
  "..."
  "..<"
  "+"
  "-"
  "*"
  "/"
  "%"
  "?"
  ":"
] @operator
