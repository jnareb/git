#!/bin/sh

test_description='git-send-email'
. ./test-lib.sh

PROG='git send-email'
test_expect_success \
    'prepare reference tree' \
    'echo "1A quick brown fox jumps over the" >file &&
     echo "lazy dog" >>file &&
     git add file
     GIT_AUTHOR_NAME="A" git commit -a -m "Initial."'

test_expect_success \
    'Setup helper tool' \
    '(echo "#!/bin/sh"
      echo shift
      echo for a
      echo do
      echo "  echo \"!\$a!\""
      echo "done >commandline"
      echo "cat > msgtxt"
      ) >fake.sendmail
     chmod +x ./fake.sendmail
     git add fake.sendmail
     GIT_AUTHOR_NAME="A" git commit -a -m "Second."'

test_expect_success 'Extract patches' '
    patches=`git format-patch -n HEAD^1`
'

test_expect_success 'Send patches' '
     git send-email --from="Example <nobody@example.com>" --to=nobody@example.com --smtp-server="$(pwd)/fake.sendmail" $patches 2>errors
'

cat >expected <<\EOF
!nobody@example.com!
!author@example.com!
EOF
test_expect_success \
    'Verify commandline' \
    'diff commandline expected'

cat >expected-show-all-headers <<\EOF
0001-Second.patch
(mbox) Adding cc: A <author@example.com> from line 'From: A <author@example.com>'
Dry-OK. Log says:
Server: relay.example.com
MAIL FROM:<from@example.com>
RCPT TO:<to@example.com>,<cc@example.com>,<author@example.com>,<bcc@example.com>
From: Example <from@example.com>
To: to@example.com
Cc: cc@example.com, A <author@example.com>
Subject: [PATCH 1/1] Second.
Date: DATE-STRING
Message-Id: MESSAGE-ID-STRING
X-Mailer: X-MAILER-STRING
In-Reply-To: <unique-message-id@example.com>
References: <unique-message-id@example.com>

Result: OK
EOF

test_expect_success 'Show all headers' '
	git send-email \
		--dry-run \
		--from="Example <from@example.com>" \
		--to=to@example.com \
		--cc=cc@example.com \
		--bcc=bcc@example.com \
		--in-reply-to="<unique-message-id@example.com>" \
		--smtp-server relay.example.com \
		$patches |
	sed	-e "s/^\(Date:\).*/\1 DATE-STRING/" \
		-e "s/^\(Message-Id:\).*/\1 MESSAGE-ID-STRING/" \
		-e "s/^\(X-Mailer:\).*/\1 X-MAILER-STRING/" \
		>actual-show-all-headers &&
	diff -u expected-show-all-headers actual-show-all-headers
'

test_done
