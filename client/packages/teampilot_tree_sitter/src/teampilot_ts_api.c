#include "teampilot_ts_api.h"

// Provided by each vendored grammar's generated parser (parser.c).
extern const TSLanguage *tree_sitter_json(void);
extern const TSLanguage *tree_sitter_dart(void);
extern const TSLanguage *tree_sitter_yaml(void);
extern const TSLanguage *tree_sitter_markdown(void);
extern const TSLanguage *tree_sitter_python(void);
extern const TSLanguage *tree_sitter_rust(void);
extern const TSLanguage *tree_sitter_tsx(void);
extern const TSLanguage *tree_sitter_bash(void);
extern const TSLanguage *tree_sitter_xml(void);
extern const TSLanguage *tree_sitter_toml(void);
extern const TSLanguage *tree_sitter_css(void);
extern const TSLanguage *tree_sitter_lua(void);
extern const TSLanguage *tree_sitter_c(void);
extern const TSLanguage *tree_sitter_cpp(void);
extern const TSLanguage *tree_sitter_java(void);
extern const TSLanguage *tree_sitter_go(void);
extern const TSLanguage *tree_sitter_c_sharp(void);
extern const TSLanguage *tree_sitter_php(void);
extern const TSLanguage *tree_sitter_ruby(void);
extern const TSLanguage *tree_sitter_kotlin(void);
extern const TSLanguage *tree_sitter_swift(void);
extern const TSLanguage *tree_sitter_sql(void);
extern const TSLanguage *tree_sitter_html(void);
extern const TSLanguage *tree_sitter_scss(void);

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_json(void) {
  return tree_sitter_json();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_dart(void) {
  return tree_sitter_dart();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_yaml(void) {
  return tree_sitter_yaml();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_markdown(void) {
  return tree_sitter_markdown();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_python(void) {
  return tree_sitter_python();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_rust(void) {
  return tree_sitter_rust();
}

// The `tsx` grammar is a superset that also parses .ts / .js / .jsx.
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_typescript(void) {
  return tree_sitter_tsx();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_bash(void) {
  return tree_sitter_bash();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_xml(void) {
  return tree_sitter_xml();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_toml(void) {
  return tree_sitter_toml();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_css(void) {
  return tree_sitter_css();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_lua(void) {
  return tree_sitter_lua();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_c(void) {
  return tree_sitter_c();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_cpp(void) {
  return tree_sitter_cpp();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_java(void) {
  return tree_sitter_java();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_go(void) {
  return tree_sitter_go();
}

// The upstream symbol is tree_sitter_c_sharp; the pack id is `csharp`.
FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_csharp(void) {
  return tree_sitter_c_sharp();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_php(void) {
  return tree_sitter_php();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_ruby(void) {
  return tree_sitter_ruby();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_kotlin(void) {
  return tree_sitter_kotlin();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_swift(void) {
  return tree_sitter_swift();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_sql(void) {
  return tree_sitter_sql();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_html(void) {
  return tree_sitter_html();
}

FFI_PLUGIN_EXPORT const TSLanguage *tp_ts_language_scss(void) {
  return tree_sitter_scss();
}
