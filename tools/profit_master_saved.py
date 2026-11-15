"""Read Profit Master SavedVariables as literal data, without executing Lua."""

import math
import re


MAX_INPUT_BYTES = 64 * 1024 * 1024
MAX_DEPTH = 64
MAX_NODES = 2_000_000
MAX_TOKEN_BYTES = 1024 * 1024
MAX_NUMBER_BYTES = 128
MAX_NAME_BYTES = 128
ALLOWED_ROOTS = frozenset(("ProfitMasterDB", "ProfitMasterDebugDB", "ProfitMasterDisenchantDB"))

_SPACE = b" \t\r\n\v\f"
_NUMBER_BYTES = b"0123456789.eE+-"
_NUMBER = re.compile(rb"[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?")
_ESCAPES = {ord("a"): 7, ord("b"): 8, ord("f"): 12, ord("n"): 10,
            ord("r"): 13, ord("t"): 9, ord("v"): 11, ord("\\"): 92,
            ord('"'): 34, ord("'"): 39}
_RESERVED = frozenset(("and", "break", "do", "else", "elseif", "end", "false", "for",
                       "function", "if", "in", "local", "nil", "not", "or", "repeat",
                       "return", "then", "true", "until", "while"))


class SavedVariablesError(ValueError):
    """The input is not supported, bounded SavedVariables literal data."""


def _name_start(byte):
    return byte == 95 or 65 <= byte <= 90 or 97 <= byte <= 122


def _name_part(byte):
    return _name_start(byte) or 48 <= byte <= 57


class _Parser:
    def __init__(self, data, allowed_roots):
        self.data = data
        self.pos = 3 if data.startswith(b"\xef\xbb\xbf") else 0
        self.nodes = 0
        self.allowed_roots = allowed_roots

    def fail(self, message):
        raise SavedVariablesError(f"{message} at byte {self.pos}")

    def node(self):
        self.nodes += 1
        if self.nodes > MAX_NODES:
            self.fail("SavedVariables node limit exceeded")

    def space(self):
        data, length = self.data, len(self.data)
        while self.pos < length:
            if data[self.pos] in _SPACE:
                self.pos += 1
            elif data.startswith(b"--", self.pos):
                self.pos += 2
                # Lua long comments are data-safe too; scan without copying.
                start = self.pos
                if self.pos < length and data[self.pos] == 91:
                    end = self.pos + 1
                    while end < length and data[end] == 61:
                        if end - start > MAX_DEPTH:
                            self.fail("Long-comment delimiter limit exceeded")
                        end += 1
                    if end < length and data[end] == 91:
                        close = b"]" + b"=" * (end - start - 1) + b"]"
                        end = data.find(close, end + 1)
                        if end < 0:
                            self.fail("Unterminated long comment")
                        self.pos = end + len(close)
                        continue
                while self.pos < length and data[self.pos] not in (10, 13):
                    self.pos += 1
            else:
                return

    def expect(self, byte, message):
        self.space()
        if self.pos >= len(self.data) or self.data[self.pos] != byte:
            self.fail(message)
        self.pos += 1

    def name(self):
        start = self.pos
        if start >= len(self.data) or not _name_start(self.data[start]):
            self.fail("Expected a field or root name")
        self.pos += 1
        while self.pos < len(self.data) and _name_part(self.data[self.pos]):
            self.pos += 1
            if self.pos - start > MAX_NAME_BYTES:
                self.fail("Name token limit exceeded")
        return self.data[start:self.pos].decode("ascii")

    def string(self):
        data, start = self.data, self.pos
        quote = data[self.pos]
        self.pos += 1
        value = bytearray()
        while self.pos < len(data):
            if self.pos - start > MAX_TOKEN_BYTES:
                self.fail("String token limit exceeded")
            byte = data[self.pos]
            self.pos += 1
            if byte == quote:
                try:
                    return value.decode("utf-8")
                except UnicodeDecodeError:
                    self.fail("Saved string is not valid UTF-8")
            if byte in (10, 13):
                self.fail("Unescaped newline in saved string")
            if byte != 92:
                value.append(byte)
                continue
            if self.pos >= len(data):
                self.fail("Unterminated string escape")
            escaped = data[self.pos]
            self.pos += 1
            if escaped in _ESCAPES:
                value.append(_ESCAPES[escaped])
            elif 48 <= escaped <= 57:
                decimal = escaped - 48
                for _ in range(2):
                    if self.pos >= len(data) or not 48 <= data[self.pos] <= 57:
                        break
                    decimal = decimal * 10 + data[self.pos] - 48
                    self.pos += 1
                if decimal > 255:
                    self.fail("Decimal string escape exceeds one byte")
                value.append(decimal)
            elif escaped in (10, 13):
                if self.pos < len(data) and data[self.pos] in (10, 13) and data[self.pos] != escaped:
                    self.pos += 1
                value.append(10)
            else:
                self.fail("Unsupported saved string escape")
        self.fail("Unterminated saved string")

    def number(self):
        start = self.pos
        while self.pos < len(self.data) and self.data[self.pos] in _NUMBER_BYTES:
            self.pos += 1
            if self.pos - start > MAX_NUMBER_BYTES:
                self.fail("Number token limit exceeded")
        token = self.data[start:self.pos]
        if not _NUMBER.fullmatch(token):
            self.fail("Invalid numeric literal")
        if b"." not in token and b"e" not in token.lower():
            return int(token)
        value = float(token)
        if not math.isfinite(value):
            self.fail("Nonfinite numeric literal")
        return value

    def value(self, depth):
        self.space()
        if self.pos >= len(self.data):
            self.fail("Expected a literal value")
        self.node()
        byte = self.data[self.pos]
        if byte == 123:
            return self.table(depth + 1)
        if byte in (34, 39):
            return self.string()
        if byte in _NUMBER_BYTES:
            return self.number()
        word = self.name()
        if word == "true":
            return True
        if word == "false":
            return False
        if word == "nil":
            return None
        self.fail("Executable expressions are not SavedVariables literal data")

    def table(self, depth):
        if depth > MAX_DEPTH:
            self.fail("Saved table nesting limit exceeded")
        self.pos += 1
        result, array_index = {}, 1
        self.space()
        while self.pos < len(self.data) and self.data[self.pos] != 125:
            byte = self.data[self.pos]
            if byte == 91:
                self.pos += 1
                key = self.value(depth)
                if isinstance(key, bool) or not isinstance(key, (str, int, float)):
                    self.fail("Saved table keys must be strings or numbers")
                self.expect(93, "Expected closing key bracket")
                self.expect(61, "Expected table field assignment")
            else:
                start = self.pos
                name = self.name() if _name_start(byte) else None
                self.space()
                if name is not None and self.pos < len(self.data) and self.data[self.pos] == 61:
                    if name in _RESERVED:
                        self.fail("Reserved word cannot be a named table key")
                    self.pos += 1
                    key = name
                else:
                    self.pos = start
                    key = array_index
                    array_index += 1
                self.node()
            if key in result:
                self.fail("Duplicate saved table key")
            result[key] = self.value(depth)
            self.space()
            if self.pos >= len(self.data):
                self.fail("Unterminated saved table")
            if self.data[self.pos] in (44, 59):
                self.pos += 1
                self.space()
            elif self.data[self.pos] != 125:
                self.fail("Expected a literal table field separator")
        self.expect(125, "Unterminated saved table")
        return result

    def parse(self):
        result = {}
        self.space()
        while self.pos < len(self.data):
            name = self.name()
            if name not in self.allowed_roots:
                self.fail("Unexpected SavedVariables root")
            if name in result:
                self.fail("Duplicate SavedVariables root")
            self.expect(61, "Expected root assignment")
            value = self.value(0)
            if value is not None and not isinstance(value, dict):
                self.fail("SavedVariables root must be a table or nil")
            result[name] = value
            self.space()
            if self.pos < len(self.data) and self.data[self.pos] == 59:
                self.pos += 1
                self.space()
        return result


def parse_saved_variables(data: bytes, *, allowed_roots=ALLOWED_ROOTS) -> dict:
    """Return allowed roots as dictionaries (including empty tables) or None.

    Missing roots are omitted. Explicit nil table values are represented by None;
    duplicate assignments are rejected even when the first value was nil. Strings
    are decoded as UTF-8 after Lua byte escapes, without lossy replacement.
    """
    if not isinstance(data, bytes):
        raise TypeError("SavedVariables input must be bytes")
    if len(data) > MAX_INPUT_BYTES:
        raise SavedVariablesError("SavedVariables input exceeds the 64 MiB limit")
    return _Parser(data, frozenset(allowed_roots)).parse()
