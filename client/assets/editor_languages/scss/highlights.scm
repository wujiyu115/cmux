; Minimal SCSS highlight captures for tree-sitter-scss.

(comment) @comment
(js_comment) @comment

(tag_name) @tag

(class_name) @type
(id_name) @type

(property_name) @property
(feature_name) @property
(attribute_name) @tag.attribute

(function_name) @function

(string_value) @string

(variable) @variable

[
  (integer_value)
  (float_value)
] @number
(color_value) @constant

(at_keyword) @keyword
(keyword_query) @keyword
(selector_query) @keyword
(important) @keyword

(nesting_selector) @operator
(universal_selector) @operator

(interpolation) @emphasis

[
  "~"
  ">"
  "+"
  "-"
  "*"
  "/"
  "="
  "^="
  "|="
  "~="
  "$="
  "*="
  "%"
] @operator
