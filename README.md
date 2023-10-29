🚧 Screen Space Reflection render feature for Unity Universal RP. 
==========

![Build](https://github.com/alexmalyutindev/unity-upm-template/actions/workflows/publish.yml/badge.svg)
![Release](https://img.shields.io/github/v/release/alexmalyutindev/unity-upm-template)

Overview
--------

![Preview](Pictures/Preview_001.jpg)

Installation
------------
Find the manifest.json file in the Packages folder of your project and add a line to `dependencies` field:

* `"com.alexmalyutindev.urp-ssr": "https://github.com/alexmalyutindev/urp-ssr.git"`

Or, you can add this package using PackageManager `Add package from git URL` option:

* `https://github.com/alexmalyutindev/urp-ssr.git`

TODOs
-----
- [ ] Change blit method to `CoreUtils.DrawFullScreen`
- [ ] Add temporal reprojection to reduce noise

License
-------
This project is MIT License - see the [LICENSE](LICENSE) file for details
