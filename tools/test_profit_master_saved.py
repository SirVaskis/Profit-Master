"""Offline tests for the data-only SavedVariables reader."""

import unittest
from unittest import mock

import profit_master_saved as saved


def database(literal):
    return saved.parse_saved_variables(b"ProfitMasterDB = " + literal)["ProfitMasterDB"]


class SavedVariablesTests(unittest.TestCase):
    def test_native_shape_and_all_roots(self):
        data = b'''\xef\xbb\xbf\r\nProfitMasterDB = {
            ["version"] = 1,
            ["items"] = { [6040] = { ["name"] = "Golden Scale Bracers", ["vendorPrice"] = 1315, }, },
            ["markets"] = {},
        }
        ProfitMasterDebugDB = { ["enabled"] = false, ["entries"] = { "first", -- [1]
            "second", -- [2]
        }, }
        ProfitMasterDisenchantDB = nil
        '''
        roots = saved.parse_saved_variables(data)
        self.assertEqual(roots["ProfitMasterDB"], {
            "version": 1, "items": {6040: {"name": "Golden Scale Bracers", "vendorPrice": 1315}}, "markets": {}})
        self.assertEqual(roots["ProfitMasterDebugDB"], {"enabled": False, "entries": {1: "first", 2: "second"}})
        self.assertIsNone(roots["ProfitMasterDisenchantDB"])

    def test_empty_missing_and_nil(self):
        self.assertEqual(saved.parse_saved_variables(b"\n-- no saved variables yet\n"), {})
        self.assertEqual(database(b"{}"), {})
        self.assertIsNone(database(b"nil"))
        self.assertEqual(saved.parse_saved_variables(b"ProfitMasterDebugDB={};"), {"ProfitMasterDebugDB": {}})
        self.assertEqual(database(b"{ nil, true, false, [9]=nil }"), {1: None, 2: True, 3: False, 9: None})

    def test_tables_and_numbers(self):
        value = database(b"{ version=1; [-7]=3.5; [0.5]=.25; [4.0]=-2.5e+2; +6; 1e-3; 7.; }")
        self.assertEqual(value, {"version": 1, -7: 3.5, 0.5: .25, 4: -250.0, 1: 6, 2: .001, 3: 7.0})
        self.assertIsInstance(value[1], int)
        self.assertEqual(database(b"{[9007199254740993]=9007199254740993}"), {9007199254740993: 9007199254740993})
        self.assertEqual(database(b"{1e-9999}"), {1: 0.0})

    def test_utf8_raw_and_decimal_byte_escapes(self):
        value = database('{["raw"]="café 漢字", ["bytes"]="\\195\\169\\226\\130\\172", '
                         '["mixed"]="é\\226\\130\\172"}'.encode("utf-8"))
        self.assertEqual(value, {"raw": "café 漢字", "bytes": "é€", "mixed": "é€"})

    def test_control_and_quoted_escapes(self):
        value = database(br'''{["control"]="\a\b\f\n\r\t\v\000\127", ["quotes"]='\'"\\', ["decimal"]="\1\12\1234"}''')
        self.assertEqual(value["control"], "\a\b\f\n\r\t\v\0\x7f")
        self.assertEqual(value["quotes"], "'\"\\")
        self.assertEqual(value["decimal"], "\x01\x0c{4")

    def test_escaped_newlines(self):
        value = database(b'{["text"]="one\\\r\ntwo\\\n\rthree\\\rfour\\\nfive"}')
        self.assertEqual(value["text"], "one\ntwo\nthree\nfour\nfive")

    def test_comments_are_not_strings_or_code(self):
        value = database(b'''-- before table
            { -- before field
              x = "-- [[ not a comment ]]", -- after field
              --[=[ a comment with ]] and "quoted text" ]=]
              y = true,
              --[[ a short long comment ]]
            } -- trailing comment''')
        self.assertEqual(value, {"x": "-- [[ not a comment ]]", "y": True})

    def test_duplicate_roots_and_keys_reject(self):
        cases = (b"ProfitMasterDB={} ProfitMasterDB={}", b"ProfitMasterDB=nil ProfitMasterDB={}",
                 b'ProfitMasterDB={x=1,["x"]=2}', b"ProfitMasterDB={[1]=1,[1.0]=2}",
                 b"ProfitMasterDB={[1]=nil,1}", b"ProfitMasterDB={x=nil,x=2}",
                 b"ProfitMasterDB={[-0.0]=1,[0]=2}")
        for data in cases:
            with self.subTest(data=data), self.assertRaisesRegex(saved.SavedVariablesError, "Duplicate"):
                saved.parse_saved_variables(data)

    def test_nonstring_nonnumeric_and_boolean_keys_reject(self):
        for literal in (b"{[true]=1}", b"{[false]=1}", b"{[nil]=1}", b"{[{}]=1}"):
            with self.subTest(literal=literal), self.assertRaises(saved.SavedVariablesError):
                database(literal)

    def test_code_and_other_roots_reject_without_execution(self):
        cases = (b"OtherDB={}", b"local ProfitMasterDB={}", b"return {}", b"ProfitMasterDB=function() end",
                 b"ProfitMasterDB={os.execute('echo forbidden')}", b"ProfitMasterDB={loadfile('x')}",
                 b"ProfitMasterDB={1+2}", b"ProfitMasterDB={1/0}", b"ProfitMasterDB={0/0}",
                 b"ProfitMasterDB={false or true}", b"ProfitMasterDB={x=(1)}",
                 b"ProfitMasterDB={} print('forbidden')", b"ProfitMasterDB={true=1}")
        with mock.patch("builtins.eval", side_effect=AssertionError("eval is forbidden")), \
             mock.patch("builtins.exec", side_effect=AssertionError("exec is forbidden")), \
             mock.patch("builtins.open", side_effect=AssertionError("file access is forbidden")):
            for data in cases:
                with self.subTest(data=data), self.assertRaises(saved.SavedVariablesError):
                    saved.parse_saved_variables(data)

    def test_roots_are_tables_or_nil(self):
        for literal in (b"true", b"123", b'"string"'):
            with self.subTest(literal=literal), self.assertRaisesRegex(saved.SavedVariablesError, "table or nil"):
                database(literal)

    def test_malformed_and_nonfinite_numbers_reject(self):
        for literal in (b"{nan}", b"{inf}", b"{1e9999}", b"{-1e9999}", b"{1e}", b"{.}", b"{--comment\n+}",
                        b"{1..2}", b"{1-2}", b"{0x10}", b"{1true}"):
            with self.subTest(literal=literal), self.assertRaises(saved.SavedVariablesError):
                database(literal)

    def test_malformed_strings_and_comments_reject(self):
        for literal in (b'{"unterminated}', b'{"raw\nnewline"}', b'{"raw\rnewline"}', br'{"\256"}',
                        br'{"\999"}', br'{"\q"}', br'{"\x41"}', br'{"\z"}', b'{"\xff"}',
                        br'{"\195"}', b"{} --[[ unterminated", b"{[=[long strings are unsupported]=]}"):
            with self.subTest(literal=literal), self.assertRaises(saved.SavedVariablesError):
                database(literal)

    def test_incomplete_or_bad_table_syntax_reject(self):
        for literal in (b"{", b"{[1]=}", b"{[1=2}", b"{x 1}", b"{1 2}", b"{,}", b"{1,,2}", b"{x=1}{}"):
            with self.subTest(literal=literal), self.assertRaises(saved.SavedVariablesError):
                database(literal)

    def test_input_limit_checked_before_parsing(self):
        with mock.patch.object(saved, "MAX_INPUT_BYTES", 10):
            with self.assertRaisesRegex(saved.SavedVariablesError, "64 MiB"):
                saved.parse_saved_variables(b"x" * 11)
        with self.assertRaises(TypeError):
            saved.parse_saved_variables("ProfitMasterDB={}")
        with self.assertRaises(TypeError):
            saved.parse_saved_variables(bytearray(b"ProfitMasterDB={}"))

    def test_depth_limit(self):
        self.assertIsInstance(database(b"{" * 64 + b"}" * 64), dict)
        with self.assertRaisesRegex(saved.SavedVariablesError, "nesting"):
            database(b"{" * 65 + b"}" * 65)

    def test_node_and_token_limits(self):
        with mock.patch.object(saved, "MAX_NODES", 4):
            with self.assertRaisesRegex(saved.SavedVariablesError, "node limit"):
                database(b"{1,2}")
        with mock.patch.object(saved, "MAX_TOKEN_BYTES", 8):
            with self.assertRaisesRegex(saved.SavedVariablesError, "String token"):
                database(b'{"' + b"a" * 20 + b'"}')
        with self.assertRaisesRegex(saved.SavedVariablesError, "Number token"):
            database(b"{" + b"9" * 129 + b"}")
        with self.assertRaisesRegex(saved.SavedVariablesError, "Name token"):
            database(b"{" + b"a" * 129 + b"=1}")
        with self.assertRaisesRegex(saved.SavedVariablesError, "delimiter limit"):
            database(b"{} --[" + b"=" * 66 + b"[x]")


if __name__ == "__main__":
    unittest.main()
