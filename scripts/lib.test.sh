#!/usr/bin/env bash
# JSON parser tests: every escape, container shape, and malformed input class
# the lib.sh parser can meet, plus the dotted-key lookups the manifests need.
# A gate only guards if the regression actually fails it.

LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.." || exit 1
source scripts/lib.sh

# positive: nested containers, escapes, types, dotted keys
json_parse '{"a":{"b.c":[1,2.5,"x\ny"]},"t":true,"n":null,"f":false,"file.md":{"sha256":"abc"}}' || { echo "PARSE FAIL: $JSON_ERROR"; exit 1; }
json_type '$.a.b.c'; expect_eq 'nested array type' "$REPLY" array
json_len '$.a.b.c'; expect_eq 'array length' "$REPLY" 3
json_get '$.a.b.c[1]'; expect_eq 'float value' "$REPLY" 2.5
json_get '$.a.b.c[2]'; expect_eq 'escape decoded' "$REPLY" $'x\ny'
json_get '$.t'; expect_eq 'true value' "$REPLY" true
json_get '$.f'; expect_eq 'false value' "$REPLY" false
json_type '$.n'; expect_eq 'null type' "$REPLY" null
json_keys '$.a'; expect_eq 'dotted key kept whole' "${REPLY_LIST[*]}" 'b.c'
json_keys '$.file.md'; expect_eq 'dotted key query' "${REPLY_LIST[*]}" 'sha256'
json_get '$.file.md.sha256'; expect_eq 'value under dotted key' "$REPLY" abc

# empty containers
json_parse '{"o":{},"e":[]}' || { echo "PARSE FAIL: $JSON_ERROR"; exit 1; }
json_keys '$.o'; expect_eq 'empty object has no keys' "${#REPLY_LIST[@]}" 0
json_len '$.e'; expect_eq 'empty array length' "$REPLY" 0
json_type '$.o'; expect_eq 'empty object type' "$REPLY" object
json_type '$.missing'; expect_status 'absent path type fails' 1 $?

# negative: each malformed input must be rejected with a reason
neg() { # <description> <input> <expected-fragment>
  if json_parse "$2"; then
    _fail "$1: accepted malformed [$2]"
    T_TOTAL=$(( T_TOTAL + 1 ))
  else
    expect_contains "$1" "$JSON_ERROR" "$3"
  fi
}
neg 'trailing comma rejected' '{"a":1,}' 'expected a string'
neg 'duplicate key rejected' '{"a":1,"a":2}' 'duplicate object key'
neg 'unterminated array rejected' '[1,2' 'unterminated array'
neg 'unterminated object rejected' '{"a"' 'expected'
neg 'trailing content rejected' '{"a":1}extra' 'trailing content'
neg 'bare literal rejected' '{"a":nope}' 'invalid literal'
neg 'unclosed string rejected' '"unclosed' 'unterminated string'
neg 'unknown escape rejected' '{"a":"\q"}' 'unknown escape'
neg 'bad unicode escape rejected' '{"a":"\u00"}' 'bad \u escape'
neg 'leading zero rejected' '{"a":01}' 'invalid number'
neg 'empty input rejected' '' 'expected a value'
neg 'missing colon rejected' '{"a" 1}' "expected ':'"

t_done
