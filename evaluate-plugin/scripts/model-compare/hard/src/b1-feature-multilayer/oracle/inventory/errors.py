"""Domain error hierarchy.

Every error raised out of the service layer is an ``InventoryError``. The API
layer relies on ``code``, ``status`` and ``field`` to build the error envelope.
"""


class InventoryError(Exception):
    code = "inventory_error"
    status = 500

    def __init__(self, message, *, field=None):
        super().__init__(message)
        self.message = message
        self.field = field

    def to_dict(self):
        body = {"code": self.code, "message": self.message}
        if self.field is not None:
            body["field"] = self.field
        return body


class ValidationError(InventoryError):
    """A request value is missing, malformed or out of range."""

    code = "validation_error"
    status = 400


class NotFoundError(InventoryError):
    code = "not_found"
    status = 404


class ConflictError(InventoryError):
    """The request is well-formed but conflicts with current state."""

    code = "conflict"
    status = 409


class InvalidCursorError(ValidationError):
    code = "invalid_cursor"
