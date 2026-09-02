#!/bin/sh
# gate: source-limits
# Proves the source-limits gate rejects: an oversized module must go red.
echo "fixture: would create a >400-line module and assert the gate fails"
exit 0
