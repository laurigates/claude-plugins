"""filterlang - see SPEC.md. Reference implementation."""
import math

KEYWORDS = {"and", "or", "not", "in", "true", "false", "null"}
OPERATORS = ["**", "==", "!=", "<=", ">=", "<", ">", "+", "-", "*", "/", "%",
             "(", ")", "[", "]", ",", "."]
FUNCTIONS = {"len": 1, "lower": 1, "upper": 1, "coalesce": None}
COMPARISONS = {"==", "!=", "<", "<=", ">", ">=", "in", "not in"}


class FilterSyntaxError(Exception):
    def __init__(self, message, column):
        super().__init__(f"{message} at column {column}")
        self.message = message
        self.column = column


class FilterEvalError(Exception):
    pass


class Tok:
    __slots__ = ("kind", "value", "text", "col")

    def __init__(self, kind, value, text, col):
        self.kind, self.value, self.text, self.col = kind, value, text, col


def tokenize(src):
    toks, i, n = [], 0, len(src)
    while i < n:
        c = src[i]
        if c in " \t\r\n":
            i += 1
            continue
        col = i + 1
        if c.isdigit() and c.isascii():
            j = i
            while j < n and src[j].isascii() and src[j].isdigit():
                j += 1
            is_float = False
            if j + 1 < n and src[j] == "." and src[j + 1].isascii() and src[j + 1].isdigit():
                is_float = True
                j += 1
                while j < n and src[j].isascii() and src[j].isdigit():
                    j += 1
            if j < n and (src[j] == "_" or (src[j].isascii() and src[j].isalpha())):
                raise FilterSyntaxError("invalid number", col)
            text = src[i:j]
            toks.append(Tok("num", float(text) if is_float else int(text), text, col))
            i = j
            continue
        if c == "_" or (c.isascii() and c.isalpha()):
            j = i
            while j < n and (src[j] == "_" or (src[j].isascii() and src[j].isalnum())):
                j += 1
            text = src[i:j]
            toks.append(Tok("kw" if text in KEYWORDS else "name", text, text, col))
            i = j
            continue
        if c in "'\"":
            j, out = i + 1, []
            while True:
                if j >= n:
                    raise FilterSyntaxError("unterminated string", col)
                d = src[j]
                if d == c:
                    j += 1
                    break
                if d == "\\":
                    if j + 1 >= n:
                        raise FilterSyntaxError("unterminated string", col)
                    e = src[j + 1]
                    simple = {"\\": "\\", "'": "'", '"': '"', "n": "\n", "t": "\t"}
                    if e in simple:
                        out.append(simple[e])
                        j += 2
                    elif e == "u":
                        hexd = src[j + 2:j + 6]
                        if len(hexd) == 4 and all(h in "0123456789abcdefABCDEF" for h in hexd):
                            out.append(chr(int(hexd, 16)))
                            j += 6
                        else:
                            raise FilterSyntaxError("invalid unicode escape", j + 1)
                    else:
                        raise FilterSyntaxError(f"invalid escape '\\{e}'", j + 1)
                    continue
                out.append(d)
                j += 1
            toks.append(Tok("str", "".join(out), src[i:j], col))
            i = j
            continue
        for op in OPERATORS:
            if src.startswith(op, i):
                toks.append(Tok("op", op, op, col))
                i += len(op)
                break
        else:
            raise FilterSyntaxError(f"unexpected character '{c}'", col)
    toks.append(Tok("end", None, "", n + 1))
    return toks


class Parser:
    def __init__(self, src):
        self.toks = tokenize(src)
        self.pos = 0

    def peek(self, k=0):
        return self.toks[min(self.pos + k, len(self.toks) - 1)]

    def next(self):
        t = self.toks[self.pos]
        self.pos += 1
        return t

    def is_(self, kind, value=None, k=0):
        t = self.peek(k)
        return t.kind == kind and (value is None or t.value == value)

    def fail(self, t):
        if t.kind == "end":
            raise FilterSyntaxError("unexpected end of input", t.col)
        raise FilterSyntaxError(f"unexpected token '{t.text}'", t.col)

    def expect(self, kind, value):
        t = self.next()
        if t.kind != kind or t.value != value:
            self.fail(t)
        return t

    def parse(self):
        node = self.p_or()
        if not self.is_("end"):
            self.fail(self.peek())
        return node

    def p_or(self):
        left = self.p_and()
        while self.is_("kw", "or"):
            self.next()
            left = ("or", left, self.p_and())
        return left

    def p_and(self):
        left = self.p_not()
        while self.is_("kw", "and"):
            self.next()
            left = ("and", left, self.p_not())
        return left

    def p_not(self):
        if self.is_("kw", "not"):
            self.next()
            return ("not", self.p_not())
        return self.p_cmp()

    def cmp_op(self):
        t = self.peek()
        if t.kind == "op" and t.value in ("==", "!=", "<", "<=", ">", ">="):
            return t.value, 1
        if t.kind == "kw" and t.value == "in":
            return "in", 1
        if t.kind == "kw" and t.value == "not" and self.is_("kw", "in", 1):
            return "not in", 2
        return None, 0

    def p_cmp(self):
        left = self.p_add()
        op, width = self.cmp_op()
        if op is None:
            return left
        self.pos += width
        right = self.p_add()
        op2, _ = self.cmp_op()
        if op2 is not None:
            raise FilterSyntaxError("comparison operators cannot be chained", self.peek().col)
        return ("cmp", op, left, right)

    def p_add(self):
        left = self.p_mul()
        while self.is_("op", "+") or self.is_("op", "-"):
            op = self.next().value
            left = ("bin", op, left, self.p_mul())
        return left

    def p_mul(self):
        left = self.p_unary()
        while self.is_("op", "*") or self.is_("op", "/") or self.is_("op", "%"):
            op = self.next().value
            left = ("bin", op, left, self.p_unary())
        return left

    def p_unary(self):
        if self.is_("op", "-"):
            self.next()
            return ("neg", self.p_unary())
        return self.p_pow()

    def p_pow(self):
        base = self.p_postfix()
        if self.is_("op", "**"):
            self.next()
            return ("bin", "**", base, self.p_unary())
        return base

    def p_postfix(self):
        node = self.p_primary()
        while self.is_("op", "."):
            self.next()
            t = self.next()
            if t.kind != "name":
                self.fail(t)
            node = ("get", node, t.value)
        return node

    def p_primary(self):
        t = self.next()
        if t.kind in ("num", "str"):
            return ("lit", t.value)
        if t.kind == "kw" and t.value in ("true", "false", "null"):
            return ("lit", {"true": True, "false": False, "null": None}[t.value])
        if t.kind == "name":
            if self.is_("op", "("):
                return self.p_call(t)
            return ("field", t.value)
        if t.kind == "op" and t.value == "(":
            node = self.p_or()
            self.expect("op", ")")
            return node
        if t.kind == "op" and t.value == "[":
            items = []
            if self.is_("op", "]"):
                self.next()
                return ("list", items)
            while True:
                items.append(self.p_or())
                if self.is_("op", ","):
                    self.next()
                    continue
                self.expect("op", "]")
                return ("list", items)
        self.fail(t)

    def p_call(self, name_tok):
        name = name_tok.value
        if name not in FUNCTIONS:
            raise FilterSyntaxError(f"unknown function '{name}'", name_tok.col)
        self.next()  # (
        args = []
        if self.is_("op", ")"):
            self.next()
        else:
            while True:
                args.append(self.p_or())
                if self.is_("op", ","):
                    self.next()
                    continue
                self.expect("op", ")")
                break
        arity = FUNCTIONS[name]
        if arity is None and not args:
            raise FilterSyntaxError(f"{name}() takes at least 1 argument", name_tok.col)
        if arity is not None and len(args) != arity:
            raise FilterSyntaxError(f"{name}() takes exactly {arity} argument", name_tok.col)
        return ("call", name, args)


def tname(v):
    if v is None:
        return "null"
    if isinstance(v, bool):
        return "boolean"
    if isinstance(v, (int, float)):
        return "number"
    if isinstance(v, str):
        return "string"
    if isinstance(v, list):
        return "list"
    return "unknown"


def truthy(v):
    return v is not None and v is not False


def is_num(v):
    return isinstance(v, (int, float)) and not isinstance(v, bool)


def equal(a, b):
    ta, tb = tname(a), tname(b)
    if ta != tb:
        return False
    if ta == "list":
        return len(a) == len(b) and all(equal(x, y) for x, y in zip(a, b))
    return a == b


def binop(op, a, b):
    if op == "+":
        if is_num(a) and is_num(b):
            return a + b
        if (isinstance(a, str) and isinstance(b, str)) or (isinstance(a, list) and isinstance(b, list)):
            return a + b
    elif is_num(a) and is_num(b):
        if op == "-":
            return a - b
        if op == "*":
            return a * b
        if op == "/":
            if b == 0:
                raise FilterEvalError("division by zero")
            return a / b
        if op == "%":
            if b == 0:
                raise FilterEvalError("division by zero")
            return a % b
        if op == "**":
            if a == 0 and b < 0:
                raise FilterEvalError("division by zero")
            try:
                r = a ** b
            except OverflowError:
                raise FilterEvalError("number too large") from None
            if isinstance(r, complex):
                raise FilterEvalError("invalid power")
            return r
    raise FilterEvalError(f"cannot apply '{op}' to {tname(a)} and {tname(b)}")


def compare(op, a, b):
    if op == "==":
        return equal(a, b)
    if op == "!=":
        return not equal(a, b)
    if op in ("in", "not in"):
        if b is None:
            r = False
        elif isinstance(b, list):
            r = any(equal(a, x) for x in b)
        elif isinstance(b, str):
            if not isinstance(a, str):
                raise FilterEvalError("'in' requires a string on the left")
            r = a in b
        else:
            raise FilterEvalError("'in' requires a list or string on the right")
        return r if op == "in" else not r
    if a is None or b is None:
        return False
    if not ((is_num(a) and is_num(b)) or (isinstance(a, str) and isinstance(b, str))):
        raise FilterEvalError(f"cannot compare {tname(a)} and {tname(b)}")
    return {"<": a < b, "<=": a <= b, ">": a > b, ">=": a >= b}[op]


def ev(node, rec):
    kind = node[0]
    if kind == "lit":
        return node[1]
    if kind == "field":
        return rec.get(node[1]) if isinstance(rec, dict) else None
    if kind == "get":
        base = ev(node[1], rec)
        return base.get(node[2]) if isinstance(base, dict) else None
    if kind == "list":
        return [ev(x, rec) for x in node[1]]
    if kind == "or":
        return truthy(ev(node[1], rec)) or truthy(ev(node[2], rec))
    if kind == "and":
        return truthy(ev(node[1], rec)) and truthy(ev(node[2], rec))
    if kind == "not":
        return not truthy(ev(node[1], rec))
    if kind == "neg":
        v = ev(node[1], rec)
        if not is_num(v):
            raise FilterEvalError(f"cannot negate {tname(v)}")
        return -v
    if kind == "bin":
        return binop(node[1], ev(node[2], rec), ev(node[3], rec))
    if kind == "cmp":
        return compare(node[1], ev(node[2], rec), ev(node[3], rec))
    if kind == "call":
        name, args = node[1], node[2]
        if name == "coalesce":
            for a in args:
                v = ev(a, rec)
                if v is not None:
                    return v
            return None
        v = ev(args[0], rec)
        if name == "len":
            if isinstance(v, (str, list)):
                return len(v)
            raise FilterEvalError("len() requires a string or list")
        if not isinstance(v, str):
            raise FilterEvalError(f"{name}() requires a string")
        return v.lower() if name == "lower" else v.upper()
    raise AssertionError(kind)


def compile_expr(source):
    tree = Parser(source).parse()
    return lambda record: ev(tree, record)


def evaluate(source, record):
    return compile_expr(source)(record)
