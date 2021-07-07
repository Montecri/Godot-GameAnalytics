# Changelog

All notable changes will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/).

## 2020-10-14: API v2 - Plugin v1.0

### TBA

## 2018-04-27

### Changed

- Improved OS version detection for Android (correct version required by GameAnalytics). Pending to do the same for iOS once I have access to Apple stuff

- Clean queue and remove queue cache file on error 400 (BAD REQUEST), since the way to recover is to generate a new, correct, event ayway and the old, broken, events, if left in the queue, will only contribute to longer upload time

- Converting "platform" and "os_version" variables to lower case, since this appear to be required by GameAnalytics (refusing events otherwise)


## 2018-04-24

### Added

- Saving events to file for reloading in next try in case of unsuccessful posting to GameAnalytics (no internet connection available, etc)
