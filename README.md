# ClojureTools

This is temporary working repo for the Windows clojure tools install. It is intended to be contributed back to the official Clojure [brew-install](https://github.com/clojure/brew-install) repo once the script is tested.

## How to test?

1. Open a PowerShell window
1. Clone the repo into your module path e.g. `C:\Users\<user>\Documents\WindowsPowerShell\Modules`
1. Navigate to a project with a `deps.edn`
1. Run `Import-Module ClojureTools`
1. Run your favorite Clojure command `clj -r` or `clj -A:rebel`

`clj` and `clojure` are both aliases for the underlying `Invoke-Clojure` function provided by the module.

If you modify the module, ensure you rerun `Import-Module ClojureTools -Force` to pick up the changes.

## Other Disclaimers

The commit history is intentionally pure garbage right now. Just taking snapshots of changes along the way, but they are by no means represenatative of how the patches will need to look for sending back to the official repo.

So far this has only been tested on PowerShell Core 6 on Windows. Will eventually test on Windows PowerShell 5.1 and PowerShell Core on Linux.
