# git send-email Setup: Reference

Setup that worked on macOS (Homebrew git 2.56.0, system Perl) sending through
Gmail in 2026-11. Check each step on the machine at hand rather than assuming it.

## 1. Is send-email Installed?

```bash
ls "$(git --exec-path)/git-send-email"
for m in Net::SMTP IO::Socket::SSL Authen::SASL MIME::Base64; do perl -M$m -e1 </dev/null 2>/dev/null && echo "$m ok" || echo "$m MISSING"; done
git config --show-origin --get-regexp '^sendemail\.' || echo "(no sendemail config)"
```

Homebrew's git ships `git-send-email`; the Perl modules for SMTP over TLS with
login were present in macOS's system Perl. Some Linux distributions package it
separately (`git-email` on Debian and Ubuntu).

With no `sendemail.smtpServer`, send-email falls back to a local `sendmail`,
which an ordinary Mac does not have configured.

## 2. Gmail Needs an App Password

Gmail refuses the account password over SMTP. Turn on 2-Step Verification, then
create an app password at `myaccount.google.com/apppasswords`. Google shows it
as four groups of four letters; enter it without the spaces.

## 3. Scope the Config to Personal Repos

Put the block in the include file that carries the personal identity, so work
repos neither send from the personal account nor pick up its SMTP settings:

```ini
[sendemail]
	smtpServer = smtp.gmail.com
	smtpServerPort = 587
	smtpEncryption = tls
	smtpUser = <you@gmail.com>
	from = <Your Name> <<you@gmail.com>>
```

In a chezmoi-managed setup, edit the source (`private_dot_config/git/<file>.inc`)
and apply that one target. Verify the scope from inside and outside a personal
repo:

```bash
git -C <personal-repo> config --show-origin --get-regexp '^sendemail\.'
git -C <work-repo> config --get-regexp '^sendemail\.' || echo "(none, as intended)"
```

## 4. The Password Lives in the Keychain

Do not write the app password into any file. With the `osxkeychain` credential
helper configured (`git config --show-origin --get-regexp '^credential'`),
send-email asks once, at
`Password for 'smtp://<user>%40gmail.com@smtp.gmail.com:587':`, and the Keychain
stores it. That first prompt needs a real terminal.

## 5. Prove the Path With a Self-Addressed Test

```bash
python3 -c "
import sys
s=open(sys.argv[1]).read()
s=s.replace('To: linux-xfs@vger.kernel.org\n','To: <you@gmail.com>\n',1).replace('Cc: <maintainer line>\n','',1).replace('Subject: ','Subject: [TEST, not sent to list] ',1)
head=s.split('\n\n',1)[0]
assert 'vger' not in head and '@kernel.org' not in head
open(sys.argv[2],'w').write(s)" report.eml report-TEST.eml
perl -e 'alarm 60; exec @ARGV' git send-email --dry-run --confirm=never report-TEST.eml </dev/null | grep -E 'RCPT|^To:|^Cc:|Result'
```

Then, in the user's terminal:
`git send-email --confirm=always report-TEST.eml`. Check the received copy with
Gmail's "Show original": plain text, stack trace and tables still aligned.

Only a real send proves the login. A dry run never contacts the SMTP server.
