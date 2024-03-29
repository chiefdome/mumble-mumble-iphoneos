Mumble for iOS (iPhone, iPod touch and iPad)
============================================

This is the source code of Mumble (a gaming-focused social
voice chat utility) for iOS-based devices.

The desktop version of Mumble runs on Windows, Mac OS X, Linux
and various other Unix-like systems. Visit its website at:

 <http://mumble.info/>

Building it
===========

To build this you need the iOS 4.0 SDK from Apple and an
Intel Mac (or equivalent :)) running Mac OS X 10.6 (or later).

Before starting your build, you will need to check out the
required submodules:

        $ git submodule init
        $ git submodule update

Then it's time to checkout MumbleKit's dependencies:

        $ cd MumbleKit
        $ git submodule init
        $ git submodule update

This will fetch known "working" snapshot of the required submodules
for MumbleKit. (CELT, Speex, Protocol Buffers for Objective C and
OpenSSL)

Then it's time to generate MumbleKit's Xcode project file. For this
you'll need CMake 2.8.3 (or 2.8.2 with patches, see MumbleKit's
README for more information). To generate MumbleKit.xcodeproj, do:

        $ cmake -G Xcode . -DIOS_BUILD=1

Once this is done, you should be able to open up the Xcode
project file for Mumble (Mumble.xcodeproj) in the root of
the source tree and hit Cmd-B to build!
