Talkable iOS SDK Installer

Usage:

1. Put the script into project root folder
2. Add a Run Script phase to the XCode project, move it before the 'Compile Sources' phase
3. Add the following code to the new Run Script phase:

`$PROJECT_DIR/talkable.sh -s=your_site_id -k=your_api_key --debug=true`

