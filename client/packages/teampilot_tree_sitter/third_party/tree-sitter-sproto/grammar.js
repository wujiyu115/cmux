/**
 * Tree-sitter grammar for sproto, the protocol description language from
 * cloudwu/sproto, following ilylia/sproto-support's `sproto.tmLanguage.json`.
 *
 * Shape of the language (validated against a real 2003VB12 home.sproto):
 *
 *   # line comment
 *   .TypeName {                    # named record type
 *       field 0 : integer          # field: name, tag, builtin type
 *       weight 2 : double          # double is a project extension
 *       x 0 : integer(2)           # integer with decimal places
 *       items 0 : *bag.BagChange   # array (*) of a qualified type
 *       counts 1 : *BuildCount()   # array keyed by a field
 *       areas 2 : *PaintAreaMap(paint_id)
 *       .Inner { ... }             # nested named type
 *   }
 *   enter_home 349 {               # protocol: name, tag, sessions
 *       request { ... }            # anonymous request body
 *       response { ... }
 *       response nil               # or a typename, or nil
 *   }
 *
 * Regenerate src/parser.c after editing:
 *   npx -y tree-sitter-cli@0.25.6 generate
 */
module.exports = grammar({
  name: 'sproto',

  word: $ => $.identifier,

  extras: $ => [/[\s\uFEFF\u2060\u200B]/],

  rules: {
    source_file: $ => repeat(choice($.comment, $.type_definition, $.protocol)),

    comment: $ => token(seq('#', /[^\n]*/)),

    type_definition: $ =>
      seq(
        '.',
        field('name', $.dotted_name),
        '{',
        repeat(choice($.comment, $.field, $.type_definition)),
        '}',
      ),

    protocol: $ =>
      seq(
        field('name', $.identifier),
        field('tag', $.number),
        '{',
        repeat(choice($.comment, $.session)),
        '}',
      ),

    // `request { ... }`, `response nil`, `request TypeName`.
    session: $ =>
      seq(
        field('kind', choice('request', 'response')),
        choice($.session_body, $.dotted_name, 'nil'),
      ),

    session_body: $ =>
      seq(
        '{',
        repeat(choice($.comment, $.field, $.type_definition)),
        '}',
      ),

    field: $ =>
      seq(
        field('name', $.identifier),
        field('tag', $.number),
        ':',
        optional('*'),
        field('type', choice($.builtin_type, $.dotted_name)),
        optional($.type_suffix),
      ),

    // `integer(2)` (decimal places), `*Type(key)` (array key), `*Type()`.
    type_suffix: $ =>
      seq(
        '(',
        optional(field('value', choice($.identifier, $.number))),
        ')',
      ),

    builtin_type: $ => choice('integer', 'string', 'boolean', 'double'),

    // Qualified type references, e.g. `home.PlayerHome`. A single token so
    // maximal munch ends at the newline: `f 0 : Type` + newline + `.Inner {`
    // cannot be misread as `Type.Inner`.
    dotted_name: $ =>
      token(/[A-Za-z_][A-Za-z0-9_]*(\.[A-Za-z_][A-Za-z0-9_]*)*/),

    identifier: $ => /[A-Za-z_][A-Za-z0-9_]*/,

    number: $ => /\d+/,
  },
});
