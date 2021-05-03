#Include %A_ScriptDir%
#Include main.ahk
global errorIcon := 3
global ShuffleMode
global RepeatMode := 0
spoofy := new Spotify

Menu, Tray, Add  ; Creates a separator line.
Menu, Tray, Add, Change default playlist, MenuHandler  ; Creates a new menu item.
return
#NoEnv  ; Recommended for performance and compatibility with future AutoHotkey releases.
; #Warn  ; Enable warnings to assist with detecting common errors.
SendMode Input  ; Recommended for new scripts due to its superior speed and reliability.
SetWorkingDir %A_ScriptDir%  ; Ensures a consistent starting directory.

; Music
; CapsLock::Shift
Numpad4::
spoofy.Player.LastTrack()
return

Numpad5::Media_Play_Pause

Numpad6::
spoofy.Player.NextTrack()
return 

Numpad2::Volume_Down
Numpad8::Volume_Up

F3::
spoofy.Playlist.SaveToGenreSpecificPlaylist()
return

F4::
spoofy.Playlist.SaveToDefaultPlaylist()
return

F6::
ShuffleMode := !ShuffleMode
spoofy.Player.SetShuffle(ShuffleMode) ; Swap the shuffle mode of the player
return 

F7::
RepeatMode := RepeatMode + (RepeatMode = 0 ? 1 : (RepeatMode = 1 ? 1 : (RepeatMode = 2 ? 1 : -2)))
spoofy.Player.SetRepeatMode(RepeatMode) ; Cycle through the three repeat modes (1-2, 2-3, 3-1)
return 


; CHROME 
^!s::
  Send ^c
  Send ^t
  Send ^v
  Send {Enter}
Return

MenuHandler:
spoofy.Playlist.ChangeDefaultPlaylists()
return