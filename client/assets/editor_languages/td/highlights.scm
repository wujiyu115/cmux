; TD (MongoDB type-check DSL, per wujiyu115/vscode-td) highlight captures.
; Visual mapping follows vscode-td's td.tmLanguage: type words take the
; keyword color, field names stay unstyled (its `normal.td`), tags take a
; constant color, and brackets are plain punctuation.

(comment) @comment

; Primitive types: number / integer / string / boolean / any.
(primitive_type) @keyword

; Type names: `Misc { ... }`, `PostureMap <integer, X>`.
(type_definition
  name: (identifier) @keyword)

(type_alias
  name: (identifier) @keyword)

; Named type references in field / array / map positions: `mount Fashion`.
(field
  type: (identifier) @keyword)

(array_type
  (identifier) @keyword)

(type_reference
  (identifier) @keyword)

; Tag values: `User (1) { ... }`, `status (enum)`.
(type_tag
  value: (identifier) @constant)

(type_tag
  value: (number) @constant)

; Map arity numbers: `friends <User, 2>`.
(type_reference
  (number) @number)

["{" "}" "[" "]" "<" ">" "(" ")"] @punctuation

[","] @punctuation
