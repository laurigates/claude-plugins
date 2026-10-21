fl = load("filterlang")


def E(src, rec=None):
    return fl.evaluate(src, rec or {})


def same(a, b):
    return type(a) is type(b) and a == b


def serr(src, rec=None):
    """-> 'message at column N' if FilterSyntaxError raised, else None."""
    try:
        fl.evaluate(src, rec or {})
    except fl.FilterSyntaxError as e:
        return str(e)
    return None


def eerr(src, rec=None):
    try:
        fl.evaluate(src, rec or {})
    except fl.FilterSyntaxError:
        return "SYNTAX"
    except fl.FilterEvalError as e:
        return str(e)
    return None


R = {"age": 20, "country": "FI", "tags": ["vip", "beta"], "name": "Hello",
     "user": {"address": {"city": "Oulu"}, "name": "Ada"}, "zero": 0, "nothing": None,
     "AND": 7, "price": 2.5, "qty": 4}

case("precedence * over + ; comparison over and", lambda: same(E("1 + 2 * 3 == 7 and 2 > 1"), True))
case("left assoc - / %", lambda: same(E("10 - 4 - 3"), 3) and same(E("100 / 10 / 5"), 2.0) and same(E("2 * 7 % 4"), 2))
case("** right assoc", lambda: same(E("2 ** 3 ** 2"), 512))
case("unary minus vs **", lambda: same(E("-2 ** 2"), -4) and same(E("2 ** -1"), 0.5) and same(E("(-2) ** 2"), 4) and same(E("- -3"), 3))
case("not looser than comparison", lambda: same(E("not 1 == 2"), True) and same(E("not not 0"), True))
case("and binds tighter than or", lambda: same(E("true or false and false"), True) and same(E("(true or false) and false"), False))
case("chained comparison error + column", lambda: serr("1 < 2 < 3") == "comparison operators cannot be chained at column 7"
     and serr("x in y == true") == "comparison operators cannot be chained at column 8")
case("string escapes", lambda: E(r'"a\"b\\c\n\t" + ' + r"'it\'s' + " + r'"ä"') == 'a"b\\c\n\tit\'sä' and E("'say \"hi\"'") == 'say "hi"')
case("invalid escape message + column", lambda: serr(r'x == "ab\q"') == "invalid escape '\\q' at column 9")
case("invalid unicode escape", lambda: serr(r'"\u12g4"') == "invalid unicode escape at column 2")
case("unterminated string column = opening quote", lambda: serr('name == "abc') == "unterminated string at column 9" and serr("'") == "unterminated string at column 1")
case("unexpected character", lambda: serr("a = 1") == "unexpected character '=' at column 3" and serr("!a") == "unexpected character '!' at column 1" and serr("a == 1 & b") == "unexpected character '&' at column 8")
case("unexpected token", lambda: serr("1 2") == "unexpected token '2' at column 3" and serr("(1 + )") == "unexpected token ')' at column 6" and serr("[1, 2,]") == "unexpected token ']' at column 7")
case("unexpected end of input", lambda: serr("(1 + 2") == "unexpected end of input at column 7" and serr("") == "unexpected end of input at column 1" and serr("  \n ") == "unexpected end of input at column 5" and serr("a ==") == "unexpected end of input at column 5")
case("invalid number", lambda: serr("x > 12abc") == "invalid number at column 5" and serr("1_0") == "invalid number at column 1")
case("whole source parsed before evaluation", lambda: serr("false and foo(1)") == "unknown function 'foo' at column 11" and serr("true or (1 +") == "unexpected end of input at column 13")
case("short-circuit and/or", lambda: same(E("false and 1 / 0 > 1"), False) and same(E("true or missing + 1"), True))
case("coalesce short-circuits", lambda: E('coalesce(nick, user.name, 1 / 0)', R) == "Ada" and E("coalesce(nothing, missing)", R) is None)
case("and/or return booleans", lambda: same(E('1 and "x"'), True) and same(E('null or 0'), True) and same(E('"" and null'), False))
case("truthiness: 0, '' and [] are truthy", lambda: same(E("not zero", R), False) and same(E('not ""'), False) and same(E("not []"), False) and same(E("not nothing", R), True))
case("field paths and missing", lambda: E('user.address.city == "Oulu"', R) is True and E("user.name.first", R) is None and E("nope.x.y", R) is None and E("(1).x") is None)
case("null ordering is false, == null works", lambda: same(E("missing < 3"), False) and same(E("3 >= missing"), False) and same(E("missing == null"), True) and same(E("not (missing > 1)"), True))
case("type-mismatch compare error", lambda: eerr('"a" < 1') == "cannot compare string and number" and eerr("true < false") == "cannot compare boolean and boolean" and eerr("[1] > [0]") == "cannot compare list and list")
case("booleans are not numbers", lambda: same(E("true == 1"), False) and same(E("1 == 1.0"), True) and eerr("true + 1") == "cannot apply '+' to boolean and number")
case("arithmetic type errors", lambda: eerr('"a" + 1') == "cannot apply '+' to string and number" and eerr("null * 2") == "cannot apply '*' to null and number" and eerr('-"x"') == "cannot negate string" and eerr('"ab" - "b"') == "cannot apply '-' to string and string")
case("in: list, substring, null, not in", lambda: same(E('"ell" in name', R), True) and same(E('"vip" in tags and "x" not in tags', R), True) and same(E("1 in nothing", R), False) and same(E("1 not in nothing", R), True) and same(E("2 in [1, 2.0]"), True))
case("in errors", lambda: eerr("1 in 5") == "'in' requires a list or string on the right" and eerr('1 in "123"') == "'in' requires a string on the left")
case("division semantics", lambda: same(E("7 / 2"), 3.5) and same(E("4 / 2"), 2.0) and same(E("7 % -3"), -2) and same(E("-7 % 3"), 2) and same(E("7 * 2"), 14) and same(E("2 ** 2"), 4))
case("division by zero", lambda: eerr("1 / 0") == "division by zero" and eerr("5 % 0") == "division by zero" and eerr("0 ** -1") == "division by zero")
case("lists: literal, equality, concat", lambda: same(E("[1, 2.0] == [1, 2]"), True) and E("[1] + [[2], 'a']") == [1, [2], "a"] and same(E("[] == []"), True) and same(E("[1, true] == [1, 1]"), False))
case("functions", lambda: same(E("len(tags) > 1 and lower(country) == 'fi' and upper('a') == 'A'", R), True) and eerr("len(5)") == "len() requires a string or list" and eerr("lower(1)") == "lower() requires a string")
case("function arity / unknown at parse time", lambda: serr("1 + len(a, b)") == "len() takes exactly 1 argument at column 5" and serr("coalesce()") == "coalesce() takes at least 1 argument at column 1" and serr("x or Len(a)") == "unknown function 'Len' at column 6")
case("keywords case-sensitive", lambda: same(E("AND + 1", R), 8) and serr("1 and") == "unexpected end of input at column 6")
def c_compile():
    f = fl.compile_expr('age >= 18 and country in ["FI", "SE"]')
    return [f({"age": a, "country": c}) for a, c in [(20, "FI"), (17, "SE"), (30, "NO"), (18, "SE")]] == [True, False, False, True]
case("compile_expr reusable", c_compile)
def c_err_attrs():
    try:
        fl.compile_expr("a +* b")
    except fl.FilterSyntaxError as e:
        return e.column == 4 and e.message == "unexpected token '*'" and isinstance(e, Exception)
    return False
case("FilterSyntaxError .message/.column", c_err_attrs)
case("long expression", lambda: same(E(" + ".join(["1"] * 300)), 300) and same(E(" and ".join(["true"] * 200)), True), timeout=20)
case("examples.md", lambda: E('coalesce(nick, name.first, "anon")', {"name": {"first": "Ada"}}) == "Ada" and same(E('len(tags) > 2 or "vip" in tags', {"tags": ["vip"]}), True) and same(E("price * qty", R), 10.0))
done()
