# filterlang - specification

`filterlang` is a small expression language used to filter JSON records.
Implement it in `filterlang.py` (Python 3.13, standard library only).

## Python API

    evaluate(source: str, record: dict) -> value
    compile_expr(source: str) -> callable(record: dict) -> value
    class FilterSyntaxError(Exception)   # .message: str, .column: int
    class FilterEvalError(Exception)

`compile_expr` parses once; the returned callable can be applied to many
records. `evaluate(s, r)` is equivalent to `compile_expr(s)(r)`. The whole
source is parsed before anything is evaluated, so a syntax error is reported
even if evaluation would never reach the offending part.

`str(FilterSyntaxError)` is exactly `"<message> at column <column>"`. Columns
are 1-based character offsets into the whole source (a newline is one
character; there are no line numbers). `str(FilterEvalError)` is exactly its
message.

Values are `null` (Python `None`), booleans, numbers (Python `int`/`float`),
strings and lists.

## Lexical structure

* Whitespace (space, tab, CR, LF) separates tokens and is otherwise ignored.
* **Numbers**: one or more digits, optionally followed by `.` and one or more
  digits. Without a fraction the value is an `int`, with one a `float`. A
  number immediately followed by a letter or `_` (e.g. `12abc`) is the error
  `invalid number` at the column of the number's first digit.
* **Strings**: delimited by `'` or `"`; the other quote character may appear
  unescaped inside. Escapes: `\\ \' \" \n \t` and `\uXXXX` (exactly four hex
  digits). A backslash followed by any other character is the error
  `invalid escape '\X'` (X being that character); `\u` not followed by four hex
  digits is `invalid unicode escape`. Both are reported at the column of the
  backslash. A string with no closing quote is `unterminated string` at the
  column of the opening quote.
* **Names**: `[A-Za-z_][A-Za-z0-9_]*`. The keywords `and or not in true false
  null` are case-sensitive; `AND` is an ordinary name.
* **Operators / punctuation**: `( ) [ ] , . == != < <= > >= + - * / % **`
* Any other character (including a lone `=` or `!`) is the error
  `unexpected character 'C'` at its column.

## Grammar and precedence (lowest to highest)

| Level | Operators | Associativity |
|-------|-----------|---------------|
| 1 | `or` | left |
| 2 | `and` | left |
| 3 | `not` (prefix) | may repeat: `not not x` |
| 4 | `== != < <= > >= in`, `not in` | **non-associative** |
| 5 | `+ -` | left |
| 6 | `* / %` | left |
| 7 | unary `-` (prefix) | may repeat |
| 8 | `**` | right |
| 9 | postfix `.name`, function call | left |

`**` binds tighter than a unary minus on its left (`-2 ** 2` is `-4`) and its
right operand may itself start with unary minus (`2 ** -1` is `0.5`).
Comparisons cannot be chained: in `a < b < c` (or `x in y == true`) the second
comparison operator is the error `comparison operators cannot be chained` at
that operator's column.

Primaries: number, string, `true`, `false`, `null`, a name (field reference), a
parenthesised expression, a list literal `[e1, e2, ...]` (possibly empty, no
trailing comma), or a function call `name(args...)`.

Syntax errors not covered above:

* the input ends where more is required: `unexpected end of input` at column
  `len(source) + 1` (this includes empty or all-whitespace source);
* any other token where it is not allowed: `unexpected token 'T'` where T is the
  token's exact source text, at the token's first column.

## Names, fields and functions

A name evaluates to `record[name]`; `.key` on a value that is a dict yields
`value[key]`. A missing key, or `.key` applied to anything that is not a dict,
yields `null` - never an error.

A name immediately followed by `(` is a function call. Functions:

| Function | Arguments | Result |
|----------|-----------|--------|
| `len(x)` | exactly 1 | length of a string or list; anything else is an evaluation error `len() requires a string or list` |
| `lower(s)` / `upper(s)` | exactly 1 | case-converted string; non-string: `lower() requires a string` (resp. `upper()`) |
| `coalesce(a, ...)` | at least 1 | first argument that is not `null` (or `null`); later arguments are **not evaluated** |

Unknown function names are the syntax error `unknown function 'f'`, and a wrong
argument count is the syntax error `f() takes exactly 1 argument` (for
`coalesce`: `coalesce() takes at least 1 argument`); both at the column of the
function name.

## Semantics

* **Truthiness**: `null` and `false` are falsy; every other value - including
  `0`, `""` and `[]` - is truthy.
* `and`, `or` short-circuit (the right operand is not evaluated when the left
  decides the result) and always produce a boolean. `not x` is the boolean
  negation of the truthiness of x.
* `==` / `!=`: deep equality. Numbers compare by value (`1 == 1.0`). Booleans
  are not numbers (`true == 1` is false). Values of different types are simply
  unequal.
* `< <= > >=`: if either operand is `null` the result is `false`. Otherwise both
  operands must be numbers, or both strings (compared by code point);
  anything else is the evaluation error `cannot compare A and B` where A/B are
  the type names `null boolean number string list`.
* `x in y`: y a list - membership using `==` semantics; y a string - x must be a
  string, substring test (otherwise `'in' requires a string on the left`);
  y `null` - `false`; anything else - `'in' requires a list or string on the right`.
  `x not in y` is exactly `not (x in y)`.
* `+`: number+number adds; string+string and list+list concatenate. `- * / % **`
  require numbers. Otherwise: `cannot apply 'OP' to A and B`. Booleans are not
  numbers.
* `/` is true division (always a float). `%` is floored modulo (result has the
  sign of the divisor). `*`, `+`, `-`, `%` and `**` on two ints give an int,
  except that `**` with a negative int exponent gives a float.
  Division, modulo, or `0 ** negative` with a zero divisor/base: `division by zero`.
* Unary `-` requires a number: `cannot negate A`.
