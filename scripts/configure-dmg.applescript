tell application "Finder"
    tell disk "Chill Claude"
        open
        set current view of container window to icon view
        set toolbar visible of container window to false
        set statusbar visible of container window to false
        set bounds of container window to {200, 200, 740, 500}
        set theViewOptions to icon view options of container window
        set arrangement of theViewOptions to not arranged
        set icon size of theViewOptions to 96
        set background picture of theViewOptions to file ".background:bg.png"
        set position of item "Chill Claude.app" of container window to {150, 150}
        set position of item "Applications" of container window to {390, 150}
        close
        open
        close
    end tell
end tell
