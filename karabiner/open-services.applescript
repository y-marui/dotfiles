-- Open the front application's standard Services submenu without activating another app.
tell application "System Events"
    set frontProcess to first application process whose frontmost is true
    tell frontProcess
        if not (exists menu bar 1) then error "The front application has no menu bar."
        -- Item 1 is the Apple menu; item 2 is the application menu.
        set appMenu to menu bar item 2 of menu bar 1
        click appMenu
        repeat with menuTitle in {"サービス", "Services"}
            if exists menu item (contents of menuTitle) of menu 1 of appMenu then
                set servicesItem to menu item (contents of menuTitle) of menu 1 of appMenu
                if not enabled of servicesItem then error "Services is unavailable in this context."
                select servicesItem
                -- Expand the highlighted submenu; do not run a service.
                key code 124
                return
            end if
        end repeat
        error "No Japanese or English Services menu was found."
    end tell
end tell
