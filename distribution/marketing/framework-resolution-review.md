# FolderSail capture framework architecture resolution

Actual screenshot-only run `35704231504`, public source `cf0a37af546da190b69521b50a268a73b4b3a53f`, retained the decisive registration observation in artifact **10683089185**, `FolderSail-real-product-screenshots` (58539 ZIP bytes). Original files remain unchanged at `/private/tmp/foldersail-capture-35704231504-review/artifact/marketing-capture.json` and the neighboring JSON files; original job log is `/private/tmp/foldersail-capture-35704231504-review/capture-job.log`.

The framework query returned two registrations:

| Full name | Architecture | Original requirement matcher |
| --- | --- | --- |
| Microsoft.WindowsAppRuntime.2_2.4.0.0_x64__8wekyb3d8bbwe | X64 | true |
| Microsoft.WindowsAppRuntime.2_2.4.0.0_x86__8wekyb3d8bbwe | X86 | false |

Both are Microsoft-published frameworks with status `Ok`. The x64 name, version, publisher and full name are exactly the original qualified framework. Capture incorrectly required the unfiltered query count to equal one. This was not a deserialized property failure.

The original installed qualifier filters its query with `Test-FileQuayFrameworkRegistration` before checking resolved registrations. Capture now uses that same original helper, with the original qualifier's property-bearing requirement shape (`PSCustomObject`) restored from capture's JSON hashtable. This retains the helper's publisher check. Capture still requires exactly one compatible registration with the exact original full name; missing, only-x86, duplicate-compatible and foreign registrations fail. The raw observation continues to retain all returned candidates. Fresh-install preflight, supplied framework hash, app payload, original package/source binding, activation/input, native capture and cleanup rules are unchanged. No remoting/module import change is made.

Verification:

- The checked fixture retains the original diagnostic observation at `fixtures/framework-registration-35704231504.json`.
- The actual production Install-operation test reproduced the original refusal with those x64+x86 fields before the repair.
- Nine focused Install-operation cases now pass: valid, serialized, original x64+x86, only-x86, absent, foreign full name, wrong required name, wrong publisher and ten duplicate compatible registrations. Tests retain exact refusal/no activation and original cleanup ordering; a separate actual diagnostic matcher error remains secondary.
- Whitespace checks pass. No unrelated suite, application build or qualification was repeated.

The failed run has no screenshot or app activation. Its owned app/profile/demo/certificate/private-key/temp cleanup and native display restoration passed. A fresh Windows screenshot-only run remains required; the qualified Store package is unchanged.
