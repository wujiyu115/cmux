/**
 * Tree-sitter grammar for TD, the MongoDB type-check DSL described by
 * wuji115/vscode-td's `syntaxes/td.tmLanguage`.
 *
 * Shape of the language (validated against a real 2003VB12 schema/role.td):
 *
 *   # line comment
 *   User (1) {              # block: name, optional (tag), { body }
 *     name string           # field: name + type
 *     age number            # primitives: number / integer / string / boolean / any
 *     tags [string]         # array type
 *     friends <User, 2>     # map type; values may nest (<a, <b, [c]>>)
 *     address (2) {         # nested block
 *       city string
 *     }
 *   }
 *   PostureMap <integer, PostureItem>   # top-level named type without a body
 *   SearchPoints [integer]
 *
 * Regenerate src/parser.c after editing:
 *   npx -y tree-sitter-cli@0.25.6 generate
 */
module.exports = grammar({
  name: 'td',

  word: $ => $.identifier,

  extras: $ => [/[\s\uFEFF\u2060\u200B]/],

  rules: {
    source_file: $ => repeat(choice($.comment, $.type_definition, $.type_alias)),

    comment: $ => token(seq('#', /[^\n]*/)),

    type_definition: $ =>
      seq(
        field('name', $.identifier),
        optional(field('tag', $.type_tag)),
        '{',
        repeat(choice($.comment, $.type_definition, $.field)),
        '}',
      ),

    // Top-level named type without a body, e.g. `PostureMap <integer, X>`
    // or `SearchPoints [integer]`.
    type_alias: $ => seq(field('name', $.identifier), field('value', $._type)),

    field: $ => seq(field('name', $.identifier), field('type', $._type)),

    _type: $ =>
      choice(
        $.primitive_type,
        $.identifier,
        $.type_tag,
        $.array_type,
        $.type_reference,
      ),

    primitive_type: $ => choice('number', 'integer', 'string', 'boolean', 'any'),

    type_tag: $ => seq('(', field('value', choice($.identifier, $.number)), ')'),

    array_type: $ => seq('[', optional($._type), ']'),

    type_reference: $ => seq('<', commaSep1(choice($._type, $.number)), '>'),

    identifier: $ => /[A-Za-z_][A-Za-z0-9_.]*/,

    number: $ => /\d+/,
  },
});

function commaSep1(rule) {
  return seq(rule, repeat(seq(',', rule)));
}
