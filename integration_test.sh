#!/bin/bash
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

RED='\033[0;31m'
GREEN='\033[0;32m'
NOCOLOR='\033[0m'

PLIST_BUDDY="/usr/libexec/PlistBuddy"

export PROJECT_DIR="$DIR/demo"
export PROJECT_FILE_PATH="$PROJECT_DIR/Test.xcodeproj"
export PROJECT_NAME="Test"
export TARGET_NAME="Test"
export INFOPLIST_FILE="$PROJECT_NAME/Info.plist"

fatal() {
  echo -e "${RED}Error: $1${NOCOLOR}"
  exit 1
}

includes() {
  grep -F -o -q -s "$1"
}

exists() {
  ls $1 1>/dev/null 2>/dev/null
}

performTest() {
  bash "$PROJECT_DIR/talkable.sh" -s=badger -k=mushroom -g=F8899676O7EZt --debug=true

  exists "$PROJECT_DIR/getsocial-installer-script-*/installer.py" || fatal "GetSocial installer script was not downloaded"
  [ -d "$PROJECT_DIR/TalkableSDK/TalkableSDK.framework" ] || fatal "TalkableSDK was not downloaded"
  [ -d "$PROJECT_DIR/GetSocial/GetSocial.framework" ] || fatal "GetSocial SDK was not downloaded"
  [ ! -e "$PROJECT_DIR/frameworks.zip" ] || fatal "Temporary ZIP file $PROJECT_DIR/frameworks.zip was not removed"

  $PLIST_BUDDY -c "Print" "$PROJECT_FILE_PATH/project.pbxproj" | includes "TalkableSDK/TalkableSDK.framework" || fatal "Talkable Framework was not added to the project"
  $PLIST_BUDDY -c "Print" "$PROJECT_FILE_PATH/project.pbxproj" | includes "GetSocial/GetSocial.framework" || fatal "GetSocial Framework was not added to the project"

  $PLIST_BUDDY -c "Print :CFBundleURLTypes" "$PROJECT_DIR/$INFOPLIST_FILE" | includes "tkbl-" || fatal "Talkable URL Scheme was not added"
  $PLIST_BUDDY -c "Print :CFBundleURLTypes" "$PROJECT_DIR/$INFOPLIST_FILE" | includes "getsocial-" || fatal "GetSocial URL Scheme was not added"

  $PLIST_BUDDY -c "Print :LSApplicationQueriesSchemes" "$PROJECT_DIR/$INFOPLIST_FILE" | includes "tkbl-" || fatal "Talkable Query Scheme was not added"
  $PLIST_BUDDY -c "Print :LSApplicationQueriesSchemes" "$PROJECT_DIR/$INFOPLIST_FILE" | includes "kakaokompassauth" || fatal "GetSocial Query Schemes were not added"

  $PLIST_BUDDY -c "Print :com.talkable.ios-sdk.site_slug" "$PROJECT_DIR/$INFOPLIST_FILE" | includes "badger" || fatal "Talkable Site ID was not set"
  $PLIST_BUDDY -c "Print :com.talkable.ios-sdk.api_key" "$PROJECT_DIR/$INFOPLIST_FILE" | includes "mushroom" || fatal "Talkable API Key not set"
  $PLIST_BUDDY -c "Print :im.getsocial.sdk.AppId" "$PROJECT_DIR/$INFOPLIST_FILE" | includes "F8899676O7EZt" || fatal "GetSocial App ID not set"

  cd "$PROJECT_DIR" && xcodebuild clean build CODE_SIGN_IDENTITY="" CODE_SIGNING_REQUIRED=NO || fatal "Project could not be built"

  echo -e "${GREEN}Installation completed successfully${NOCOLOR}"
}

rm -rf "$PROJECT_DIR"
unzip "$DIR/demo.zip" -d "$DIR"
cp "$DIR/talkable.sh" "$PROJECT_DIR/talkable.sh"
cd "$PROJECT_DIR" || exit 1

performTest
performTest # second run to test behavior when everything is already downloaded and configured

rm -rf "$PROJECT_DIR"
