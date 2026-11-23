#!/bin/bash
# Get page id
if [ -z "$1" ]
then
  echo "Need confluence page id."
  exit 1
fi

# Get file name
if [ -z "$2" ]
then
  echo "Need file name."
  exit 1
fi

TOKEN="~~~"
BASE_URL="https://confluence.tde.sktelecom.com"
PAGE_ID="$1"
FILE_NAME="$2"
COOKIE_FILE=$(mktemp)
chmod 600 "$COOKIE_FILE"

curl -sS -L \
  -c "$COOKIE_FILE" \
  -b "$COOKIE_FILE" \
  -H "Authorization: Bearer ${TOKEN}" \
  -H "X-Atlassian-Token: no-check" \
  -w '\nHTTP_CODE=%{http_code}\n' \
  -o "${FILE_NAME}.pdf" \
  "${BASE_URL}/spaces/flyingpdf/pdfpageexport.action?pageId=${PAGE_ID}"

unset TOKEN
rm -f "$COOKIE_FILE"

#file "${PAGE_ID}.pdf"
