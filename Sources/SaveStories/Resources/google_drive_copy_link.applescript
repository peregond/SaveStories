use scripting additions

on run argv
    if (count of argv) < 2 then error "Missing required arguments."

    set targetPath to item 1 of argv
    set clipboardSentinel to item 2 of argv

    set the clipboard to clipboardSentinel

    tell application "Finder"
        activate
        reveal POSIX file targetPath as alias
        set selection to {POSIX file targetPath as alias}
    end tell

    delay 0.7

    tell application "System Events"
        if UI elements enabled is false then
            error "Accessibility access is not enabled for SaveMe."
        end if

        tell process "Finder"
            set frontmost to true
            delay 0.5

            set actionWorked to my tryMenuBarRoute()
            if actionWorked is false then
                set actionWorked to my tryContextMenuRoute(window 1)
            end if

            if actionWorked is false then
                error "Google Drive copy-link action was not found in Finder."
            end if
        end tell
    end tell

    return my waitForUpdatedClipboard(clipboardSentinel, 15)
end run

on tryMenuBarRoute()
    tell application "System Events"
        tell process "Finder"
            repeat with menuTitle in {"File", "Services", "Файл", "Службы"}
                try
                    set candidateMenu to menu 1 of menu bar item menuTitle of menu bar 1
                    set matchingItem to my findMatchingMenuItem(candidateMenu, false)
                    if matchingItem is not missing value then
                        click matchingItem
                        return true
                    end if
                end try
            end repeat
        end tell
    end tell

    return false
end tryMenuBarRoute

on tryContextMenuRoute(frontWindow)
    tell application "System Events"
        tell process "Finder"
            set selectedElement to my findSelectedElement(frontWindow)
            if selectedElement is missing value then return false

            try
                perform action "AXShowMenu" of selectedElement
            on error
                return false
            end try

            delay 0.4

            try
                set visibleMenus to every menu whose visible is true
            on error
                set visibleMenus to {}
            end try

            repeat with candidateMenu in visibleMenus
                set matchingItem to my findMatchingMenuItem(candidateMenu, false)
                if matchingItem is not missing value then
                    click matchingItem
                    return true
                end if
            end repeat
        end tell
    end tell

    return false
end tryContextMenuRoute

on findSelectedElement(frontWindow)
    tell application "System Events"
        tell process "Finder"
            try
                repeat with candidate in entire contents of frontWindow
                    try
                        if selected of candidate is true then
                            return candidate
                        end if
                    end try
                end repeat
            end try
        end tell
    end tell

    return missing value
end findSelectedElement

on findMatchingMenuItem(candidateMenu, allowPlainCopy)
    tell application "System Events"
        repeat with candidateItem in menu items of candidateMenu
            try
                set titleText to name of candidateItem as text
            on error
                set titleText to ""
            end try

            set containsDrive to my containsDriveKeyword(titleText)
            set containsCopy to my containsCopyKeyword(titleText)

            if (containsDrive and containsCopy) or (allowPlainCopy and containsCopy) then
                return candidateItem
            end if

            try
                set nestedMenu to menu 1 of candidateItem
                set nestedMatch to my findMatchingMenuItem(nestedMenu, allowPlainCopy or containsDrive)
                if nestedMatch is not missing value then
                    return nestedMatch
                end if
            end try
        end repeat
    end tell

    return missing value
end findMatchingMenuItem

on containsDriveKeyword(titleText)
    set loweredTitle to my lowercaseText(titleText)
    repeat with keywordText in {"google drive", "drive", "диск"}
        if loweredTitle contains keywordText then return true
    end repeat
    return false
end containsDriveKeyword

on containsCopyKeyword(titleText)
    set loweredTitle to my lowercaseText(titleText)
    repeat with keywordText in {"скопировать ссылку в буфер обмена", "copy link to clipboard", "copy link", "copy google drive link", "copy sharing link", "get link", "copy share link", "copy public link", "скопировать ссылку", "копировать ссылку", "получить ссылку", "скопировать ссылку google drive", "копировать ссылку google drive"}
        if loweredTitle contains keywordText then return true
    end repeat
    return false
end containsCopyKeyword

on lowercaseText(sourceText)
    return do shell script "/bin/echo " & quoted form of sourceText & " | /usr/bin/tr '[:upper:]' '[:lower:]'"
end lowercaseText

on waitForUpdatedClipboard(clipboardSentinel, timeoutSeconds)
    repeat with tick from 1 to (timeoutSeconds * 4)
        delay 0.25
        try
            set clipboardValue to the clipboard as text
            if clipboardValue is not clipboardSentinel and clipboardValue is not "" then
                return clipboardValue
            end if
        end try
    end repeat

    error "Clipboard did not change after invoking Google Drive action."
end waitForUpdatedClipboard
