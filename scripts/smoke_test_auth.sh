#!/usr/bin/env bash
# Live test of authentication and ownership on the deployed API.
# Needs .env.test (git-ignored): POOL, CLIENT, API, ALICE_PW, BOB_PW (two admin-created test users).
set -euo pipefail
cd "$(dirname "$0")/.."
set -a; . ./.env.test; set +a

tok() { aws cognito-idp initiate-auth --client-id "$CLIENT" --auth-flow USER_PASSWORD_AUTH \
  --auth-parameters "USERNAME=$1,PASSWORD=$2" --query AuthenticationResult.AccessToken --output text; }
code() { curl -s -o /dev/null -w "%{http_code}" "$@"; }
check() { if [ "$2" = "$3" ]; then echo "PASS  $1 ($3)"; else echo "FAIL  $1 (expected $2, got $3)"; FAILED=1; fi; }
FAILED=0

TA=$(tok alice@example.com "$ALICE_PW"); TB=$(tok bob@example.com "$BOB_PW")

check "no token"                    401 "$(code "${API}notes")"
check "forged unsigned token"       401 "$(code -H 'Authorization: Bearer eyJhbGciOiJub25lIn0.eyJzdWIiOiJ4In0.' "${API}notes")"
ID=$(curl -s -X POST "${API}notes" -H "Authorization: Bearer $TA" -H 'content-type: application/json' \
  -d '{"title":"smoke","body":"alice only"}' | python -I -c "import sys,json;print(json.load(sys.stdin)['id'])")
check "alice reads her note"        200 "$(code -H "Authorization: Bearer $TA" "${API}notes/$ID")"
check "bob reads alice's note"      404 "$(code -H "Authorization: Bearer $TB" "${API}notes/$ID")"
check "bob deletes alice's note"    404 "$(code -X DELETE -H "Authorization: Bearer $TB" "${API}notes/$ID")"
check "alice's note still there"    200 "$(code -H "Authorization: Bearer $TA" "${API}notes/$ID")"
check "alice deletes her note"      204 "$(code -X DELETE -H "Authorization: Bearer $TA" "${API}notes/$ID")"
exit $FAILED
