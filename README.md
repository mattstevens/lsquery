# lsquery

A command line tool to query the Launch Services database on your Mac.

    Usage: lsquery <options>

    Queries the Launch Services database for matching application bundles.

    Options:
      -h, --help                 Show this help message and exit
      -b, --bundleid <bundleid>  Search for the given bundle identifier
      -u, --url <url>            Search for handlers of the given URL
      -a  --find-all             Show all matching bundles
          --version              Show the version and exit

This tool was originally written to assist with a quirk of Launch Services: When searching for an application by bundle ID, URL, document type, etc if multiple bundles with the same CFBundleIdentifier and CFBundleVersion as the default application are present on the system, Launch Services will effectively pick one at random. For example, say you have a build of your application in your Debug folder and another from last week in your Release folder. You make a change to push notification or URL handling in your debug version and go to test it, but your change doesn't seem to be working. Or sometimes it is and sometimes it isn't. This is because Launch Services is sometimes picking the debug version you just built, and sometimes the old release version, and sometimes the version in ~/Downloads that you downloaded from your server and forgot about.

To make the system consistently use the bundle you intend you can either increase its CFBundleVersion to be greater than that of all other copies on the system, or remove all other copies with the same bundle version. I prefer to remove all the other options and this tool assists with finding them. I have found it to be more accurate than querying Spotlight since Launch Services can be aware of copies that Spotlight isn't.


    $ lsquery -a -b net.codeworkshop.WhateverApp
    *1.0: /Users/matt/Library/Developer/Xcode/DerivedData/WhateverApp/Build/Products/Release/WhateverApp.app
     1.0: /Users/matt/Library/Developer/Xcode/DerivedData/WhateverApp/Build/Products/Debug/WhateverApp.app

    Warning: Multiple bundles found with version 1.0.
    The result of Launch Services queries for this application will be undefined.
