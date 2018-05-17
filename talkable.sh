#!/bin/bash
ARGUMENTS="$*"
DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
SCRIPT_PATH="$DIR/$( basename "${BASH_SOURCE[0]}" )"
VERSION="0.0.2"
DEBUG=false

PYTHON="python"
PLIST_BUDDY="/usr/libexec/PlistBuddy"

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
NOCOLOR='\033[0m'
VERSION_REGEX='^[0-9]+.[0-9]+.[0-9]+$'

SITE_ID=""
API_KEY=""
GETSOCIAL_APP_ID=""
FRAMEWORK_VERSION=""
GETSOCIAL_VERSION=""
DEFAULT_GETSOCIAL_VERSION="0.0.9"

FRAMEWORK_NAME="TalkableSDK"
FRAMEWORK_DIR="$PROJECT_DIR/$FRAMEWORK_NAME"
FRAMEWORK_PATH="$FRAMEWORK_DIR/$FRAMEWORK_NAME.framework"
FRAMEWORK_PLIST_PATH="$FRAMEWORK_PATH/Info.plist"
TALKABLE_VERSION_URL="https://human-spider.github.io/index.html"
GETSOCIAL_VERSION_URL="https://downloads.getsocial.im/ios-installer/releases/latest.json"
FRAMEWORK_BUNDLE_ID='com.talkable.ios-sdk'
GETSOCIAL_PARAMS="--use-ui false --ignore-cocoapods true"

# Helper Functions

verbose() {
  $DEBUG && echo -e "${GREEN}Talkable: $1${NOCOLOR}"
}

warn() {
  echo -e "${YELLOW}Talkable Warning: $1${NOCOLOR}"
}

fatal() {
  echo -e "${RED}Talkable Error: $1"
  echo -e "Please refer to http://docs.talkable.com/ios_sdk.html or contact us at support@talkable.com${NOCOLOR}"
  exit 1
}

getPlistValue() {
  $PLIST_BUDDY -c "Print :$2" "$1" 2>/dev/null
}

plistBuddyExec() {
  local plistPath=$1
  cat $2 | while read -r line; do
    $PLIST_BUDDY -c "$line" "$plistPath" 2>/dev/null
  done
}

includes() {
  grep -F -o -q -s "$1"
}

getJSONValue() {
  $PYTHON -c "import sys, json; print json.load(sys.stdin)['$1']"
}

downloadFile() {
  curl -# -o "$1" "$2"
}

downloadAndUnzip() {
  local download_url=$1
  local zip_path=$2
  local unzip_dir=$3
  verbose "downloading zip from $download_url..."
  downloadFile "$zip_path" "$download_url"
  unzip -q "$zip_path" -d "$unzip_dir"
  verbose "downloaded and unzipped to $unzip_dir"
  rm -f "$zip_path"
}

# Actions

selfUpdate() {
  if [ -n "$REQUIRE_VERSION" ] && [ "$REQUIRE_VERSION" != "$VERSION" ]; then
    # Installer script was updated and relaunched, but the version is still not the desired version.
    # Don't launch self update again so we don't enter an infinite loop.
    warn "Installer could not be updated to version $REQUIRE_VERSION, is at version $VERSION instead"
    return 0
  fi

  local required_version
  local download_url

  required_version=$(echo "$TALKABLE_DATA" | getJSONValue "installer_version")
  if [ -z "$required_version" ] || [ "$VERSION" = "$required_version" ]; then
    verbose "Current installer version $VERSION satisfies requirement"
  else
    verbose "Updating installer script to version $required_version"
    download_url=$(echo "$TALKABLE_DATA" | getJSONValue "installer_url")
    if [ -z "$download_url" ]; then
      warn "Could not fetch URL to download installer update"
      return 0
    fi
    downloadFile "$SCRIPT_PATH" "$download_url"
    chmod +x "$SCRIPT_PATH"
    /bin/bash "$SCRIPT_PATH $ARGUMENTS --require-version=$required_version"
    exit 0
  fi
}

downloadTalkableFramework() {
  local framework_download_needed=true
  local framework_current_version
  local download_url

  # use framework version from talkable data if not specified
  [ -z "$FRAMEWORK_VERSION" ] && FRAMEWORK_VERSION=$(echo "$TALKABLE_DATA" | getJSONValue "framework_version")

  # check if version was fetched correctly and get download url for that version
  # verify version with regex because it can contain error page HTML
  if [ ! -z "$FRAMEWORK_VERSION" ] && [[ "$FRAMEWORK_VERSION" =~ $VERSION_REGEX ]]; then
    download_url="https://talkable-downloads.s3.amazonaws.com/ios-sdk/talkable_ios_sdk_$FRAMEWORK_VERSION.zip"
  else
    FRAMEWORK_VERSION=""
    download_url="https://talkable-downloads.s3.amazonaws.com/ios-sdk/talkable_ios_sdk.zip"
  fi

  # determine if we need to download framework (not downloaded or downloaded version is different)
  if [ -f "$FRAMEWORK_PLIST_PATH" ]; then
    framework_current_version=$(getPlistValue "$FRAMEWORK_PLIST_PATH" "CFBundleVersion")
    if [ -z "$FRAMEWORK_VERSION" ] || [ "$FRAMEWORK_VERSION" = "$framework_current_version" ]; then
      verbose "Current SDK version $framework_current_version satisfies requirement"
      framework_download_needed=false
    else
      verbose "Current SDK version is $framework_current_version, requested version $FRAMEWORK_VERSION"
    fi
  else
    verbose "Downloaded SDK was not found."
  fi

  if $framework_download_needed; then
    rm -rf "$FRAMEWORK_PATH"
    downloadAndUnzip "$download_url" "$PROJECT_DIR/talkable-framework.zip" "$FRAMEWORK_DIR"
  fi
}

downloadGetSocialInstaller() {
  # check if getsocial installer version was fetched correctly
  [ -z "$GETSOCIAL_VERSION" ] && GETSOCIAL_VERSION=$(curl -s -X GET "$GETSOCIAL_VERSION_URL" | getJSONValue "version")

  if [ -z "$GETSOCIAL_VERSION" ] || [[ ! "$GETSOCIAL_VERSION" =~ $VERSION_REGEX ]]; then
    verbose "Could not fetch latest GetSocial installer version, using v$DEFAULT_GETSOCIAL_VERSION"
    GETSOCIAL_VERSION=$DEFAULT_GETSOCIAL_VERSION
  fi

  local getsocisal_download_url="https://downloads.getsocial.im/ios-installer/releases/ios-installer-$GETSOCIAL_VERSION.zip"

  #download und unzip GetSocial installer if needed
  GETSOCIAL_INSTALLER_DIR="$PROJECT_DIR/getsocial-installer-script-$GETSOCIAL_VERSION"

  if [ ! -e "$GETSOCIAL_INSTALLER_DIR/installer.py" ]; then
    verbose "Downloading GetSocial installer script..."
    rm -rf "$PROJECT_DIR"/getsocial-installer-script-*
    downloadAndUnzip "$getsocisal_download_url" "$PROJECT_DIR/getsocial-installer-script.zip" "$GETSOCIAL_INSTALLER_DIR"
  else
    verbose "GetSocial installer script v$GETSOCIAL_VERSION already downloaded"
  fi
}

addTalkableFrameworkToProject() {
  #verify we have all dependencies
  [ ! -f "$FRAMEWORK_PLIST_PATH" ] && fatal "Talkable SDK could not be downloaded"
  [ ! -e "$GETSOCIAL_INSTALLER_DIR/installer.py" ] && fatal "GetSocial installer script could not be downloaded"

  if getPlistValue "$PROJECT_FILE_PATH/project.pbxproj" | includes "$FRAMEWORK_NAME"; then
    verbose "SDK already added to $PROJECT_FILE_PATH"
    return 0
  fi

  PYTHON_SCRIPT="
import sys
sys.path.insert(0, \"$GETSOCIAL_INSTALLER_DIR\")
sys.path.insert(0, \"$GETSOCIAL_INSTALLER_DIR/openstep_parser\")
sys.path.insert(0, \"$GETSOCIAL_INSTALLER_DIR/pbxproj\")
from pbxproj.pbxextensions import *
from pbxproj import XcodeProject
project = XcodeProject.load(\"$PROJECT_FILE_PATH/project.pbxproj\")
added_files = project.add_file(
  \"$FRAMEWORK_PATH\",
  parent=project.get_or_create_group('Frameworks'),
  force=False,
  file_options=FileOptions(weak=False, embed_framework=True))
if len(added_files) > 0: project.save()
"

  #add Talkable SDK to project
  verbose "Adding SDK to XCode Project file: $PROJECT_FILE_PATH"
  $PYTHON -c "$PYTHON_SCRIPT"
  if getPlistValue "$PROJECT_FILE_PATH/project.pbxproj" | includes "$FRAMEWORK_NAME"; then
    verbose "SDK added to $PROJECT_FILE_PATH"
  else
    fatal "SDK could not be added to $PROJECT_FILE_PATH"
  fi
}

configureInfoPlist() {
  local url_scheme_name="tkbl-$SITE_ID"
  local infoplist_full_path="$PROJECT_DIR/$INFOPLIST_FILE"

  #add Talkable URL Scheme to info.plist
  if getPlistValue "$infoplist_full_path" "CFBundleURLTypes" | includes "$url_scheme_name"; then
    verbose "URL Scheme $url_scheme_name already exists in $infoplist_full_path"
  else
    verbose "Adding URL scheme $url_scheme_name to $infoplist_full_path"
    plistBuddyExec "$infoplist_full_path" << EOF
Add :CFBundleURLTypes array
Add :CFBundleURLTypes:0 dict
Add :CFBundleURLTypes:0:CFBundleURLName string $FRAMEWORK_BUNDLE_ID
Add :CFBundleURLTypes:0:CFBundleTypeRole string Editor
Add :CFBundleURLTypes:0:CFBundleURLSchemes array
Add :CFBundleURLTypes:0:CFBundleURLSchemes:0 string $url_scheme_name
EOF
  fi

  #add Talkable Query Scheme to info.plist
  if getPlistValue "$infoplist_full_path" "LSApplicationQueriesSchemes" | includes "$url_scheme_name"; then
    verbose "Query Scheme $url_scheme_name already exists in $infoplist_full_path"
  else
    verbose "Adding Query Scheme $url_scheme_name to $infoplist_full_path"
    plistBuddyExec "$infoplist_full_path" << EOF
Add :LSApplicationQueriesSchemes array
Add :LSApplicationQueriesSchemes:0 string $url_scheme_name
EOF
  fi
}

callGetSocialInstaller() {
  $PYTHON $GETSOCIAL_INSTALLER_DIR/installer.py --app-id $GETSOCIAL_APP_ID $GETSOCIAL_PARAMS --debug $( $DEBUG && echo 'true' || echo 'false' )
}

cleanUp() {
  rm -f "$PROJECT_DIR/frameworks.zip"
}

# Parse Arguments

while [ "$1" != "" ]; do
  PARAM=$( echo "$1" | awk -F= '{print $1}' )
  VALUE=$( echo "$1" | awk -F= '{print $2}' )
  case $PARAM in
      --site-id | -s)
          SITE_ID=$VALUE
          ;;
      --api-key | -k)
          API_KEY=$VALUE
          ;;
      --version | -v)
          FRAMEWORK_VERSION=$VALUE
          ;;
      --getsocial-app-id | -g)
          GETSOCIAL_APP_ID=$VALUE
          ;;
      --require-version)
          REQUIRE_VERSION=$VALUE
          ;;
      --debug)
          DEBUG=true
          ;;
      *)
          fatal "unknown parameter \"$PARAM\""
          ;;
  esac
  shift
done

[ -z "$SITE_ID" ] && fatal "--site-id param is mandatory"
[ -z "$API_KEY" ] && fatal "--api-key param is mandatory"

# Fetch version data and GetSocial App ID from Talkable

TALKABLE_DATA=$(curl -s -X GET "$TALKABLE_VERSION_URL") #this request will call Talkable API and contain site ID and API key

[ -z "$GETSOCIAL_APP_ID" ] && GETSOCIAL_APP_ID=$(echo "$TALKABLE_DATA" | getJSONValue "getsocial_app_id")
[ -z "$GETSOCIAL_APP_ID" ] && fatal "Could not fetch GetSocial App ID"

verbose "Site ID: $SITE_ID, API Key: $API_KEY, GetSocial App ID: $GETSOCIAL_APP_ID"

selfUpdate

# Perform the installation

downloadTalkableFramework
downloadGetSocialInstaller
addTalkableFrameworkToProject
configureInfoPlist
callGetSocialInstaller
cleanUp
