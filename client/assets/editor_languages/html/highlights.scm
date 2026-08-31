; Minimal HTML highlight captures for tree-sitter-html.

(comment) @comment

(doctype) @keyword

(tag_name) @tag

(attribute_name) @tag.attribute

(attribute_value) @string
(quoted_attribute_value) @string

[
  "<"
  ">"
  "</"
  "/>"
] @punctuation

[
  "="
] @operator
