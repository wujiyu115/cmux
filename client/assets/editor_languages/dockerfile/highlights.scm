; Minimal Dockerfile highlight captures for tree-sitter-dockerfile.

(comment) @comment

[
  (double_quoted_string)
  (single_quoted_string)
  (json_string)
] @string

(escape_sequence) @string.escape

(variable) @variable

(env_pair
  name: (unquoted_string) @property)

(label_pair
  key: (unquoted_string) @property)

(param) @attribute

(expose_port) @number

[
  "ADD"
  "ARG"
  "AS"
  "CMD"
  "COPY"
  "CROSS_BUILD"
  "ENTRYPOINT"
  "ENV"
  "EXPOSE"
  "FROM"
  "HEALTHCHECK"
  "LABEL"
  "MAINTAINER"
  "ONBUILD"
  "RUN"
  "SHELL"
  "STOPSIGNAL"
  "USER"
  "VOLUME"
  "WORKDIR"
] @keyword

[
  "NONE"
  "/tcp"
  "/udp"
] @constant.builtin

[
  "$"
  "="
] @operator

[
  "--"
  ","
  ":"
  "@"
] @punctuation
