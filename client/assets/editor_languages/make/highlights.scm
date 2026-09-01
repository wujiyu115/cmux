; Minimal Makefile highlight captures for tree-sitter-make.

(comment) @comment

(string) @string

(escape) @string.escape

(variable_assignment
  name: (word) @variable)

(define_directive
  name: (word) @variable)

(variable_reference
  (word) @variable)

(automatic_variable) @variable.builtin

(targets
  (word) @function)

(function_call
  function: _ @function.builtin)

(shell_function
  function: _ @function.builtin)

[
  "define"
  "else"
  "endef"
  "endif"
  "export"
  "ifdef"
  "ifndef"
  "ifeq"
  "ifneq"
  "include"
  "-include"
  "sinclude"
  "override"
  "private"
  "undefine"
  "unexport"
  "vpath"
  "VPATH"
] @keyword

[
  "!="
  "+="
  "::="
  ":="
  "?="
  "="
] @operator

[
  "&:"
  "::"
  ":"
  ";"
] @punctuation
