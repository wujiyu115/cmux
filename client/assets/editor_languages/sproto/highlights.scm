; sproto (cloudwu/sproto protocol DSL, per ilylia/sproto-support) captures.
; Visual mapping follows sproto.tmLanguage.json: request/response are
; constants, protocol names functions, type names entity.name scopes, builtin
; types storage/keywords, tags constant.numeric. Field names stay unstyled
; (the reference leaves them plain).

(comment) @comment

; Session keywords: `request { ... }`, `response nil`.
"request" @constant
"response" @constant
"nil" @constant

; Protocol definition: `enter_home 349 { ... }`.
(protocol
  name: (identifier) @function)

(protocol
  tag: (number) @number)

; Named record types: `.PlayerHome { ... }`, `.home.Inner { ... }`.
(type_definition
  name: (dotted_name) @type)

; Session typename references: `request Foo`, `response home.Bar`.
(session
  (dotted_name) @type)

; Field tags: `errcode 0 : integer`.
(field
  tag: (number) @number)

; Builtin field types: integer / string / boolean / double.
(builtin_type) @keyword

; Type references in field position: `home.PlayerHome`, `*bag.BagChange`.
(field
  type: (dotted_name) @type)

; Suffix values: `integer(2)` decimal places, `*Plough(uuid)` array key.
; The key name takes the string color (sproto-support styles it as a string).
(type_suffix
  value: (identifier) @string)

(type_suffix
  value: (number) @number)

["{" "}" "(" ")"] @punctuation

["." ":" "*"] @punctuation
