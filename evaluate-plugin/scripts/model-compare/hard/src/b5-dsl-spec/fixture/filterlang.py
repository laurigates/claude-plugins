"""filterlang - see SPEC.md."""


class FilterSyntaxError(Exception):
    pass


class FilterEvalError(Exception):
    pass


def compile_expr(source):
    raise NotImplementedError


def evaluate(source, record):
    return compile_expr(source)(record)
