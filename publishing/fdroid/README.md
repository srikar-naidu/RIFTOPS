# F-Droid submission

This recipe is a draft until fdroiddata CI and an F-Droid reviewer validate the
full Godot source build.

1. Confirm the public `v1.0.0` tag contains the Fastlane metadata.
2. Sign in to GitLab, open an issue in
   <https://gitlab.com/fdroid/rfp/-/issues/new>, and paste the title and body
   from [RFP.md](RFP.md).

Reviewers will audit every bundled license and binary-looking asset, run the
isolated build, and may ask for recipe changes or a direct fdroiddata merge
request. Inclusion is discretionary and commonly takes weeks.

Run `bash publishing/fdroid/validate.sh` for the quick local checks. The
multi-hour source build is intentionally left to fdroiddata CI or a reviewer.
