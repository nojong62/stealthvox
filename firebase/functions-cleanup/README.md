# Inactive anonymous account cleanup

Runs daily at 03:00 Asia/Seoul in project stealth-vox-3p3rq3.

An account qualifies only after 30 days since the latest of creation, sign-in and token refresh, with no email, phone, linked provider or custom claims. Existing user documents or descendants, references in other Firestore collections, custom identity mappings and application Storage objects protect the account. Any failed scan aborts before deletion. The existing Auth deletion trigger handles empty user trees.

Successful scans write a result to Firestore anonymous_cleanup_runs. Audit records are excluded from ownership checks. Per-account deletion failures are recorded and cause the scheduled run to fail; the next daily scan retries remaining accounts.

Deploy from firebase: firebase deploy --only functions:anonymous-cleanup --project stealth-vox-3p3rq3

Test: npm test

The standalone runner tool/run_anonymous_cleanup.cjs defaults to dry run and limits itself to the previously reviewed CSV; --delete explicitly enables deletion. Local audit exports contain personal information and must not be committed.

## User-designated Google accounts

The same daily job reads account_cleanup_policy/designated_google_test_accounts. Only exact emails explicitly approved by the user can qualify, with a Google provider or legacy Google mapping and 30 days since latest activity. Application data does not block this designated cleanup. Kakao links, phone numbers and privileged custom claims protect accounts. This list is not proof of Google Play Test Lab origin; similarly named new emails are never automatically included. Results are stored in designated_google_cleanup_runs.
