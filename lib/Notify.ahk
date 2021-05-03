PleasantNotify(message, pnW, pnH, position="b r", time=5, text_pos = 8) {
    global PN_hwnd, w, h

	Notify_Destroy()
	Gui, Notify: +AlwaysOnTop +ToolWindow -SysMenu -Caption +LastFound
	PN_hwnd := WinExist()
	WinSet, ExStyle, +0x20
	WinSet, Transparent, 0

	text_width := StringWidth(message, FiraFlott, 10)
	pnW := text_width*3/2

	Gui, Notify: Color, 0x000000
	Gui, Notify: Font, cWhite s10 wRegular, FiraFlott
	Gui, Notify: Add, Text, % " x" (pnW/2 - text_width/2) " y" (text_pos) " w" (text_width+text_width/2) " h" pnH/2 , % message

	RealW := pnW +pnW/2 - text_width/2
	RealH := pnH + 25

	Gui, Notify: Show, W%RealW% H%RealH% NoActivate
	WinMove(PN_hwnd, position)
	if A_ScreenDPI = 96
		WinSet, Region,0-0 w%RealW% h%pnH% R4-4 ,%A_ScriptName%
	

	winfade("ahk_id " PN_hwnd,175,10)
	if (time <> "P")
	{
		Closetick := time*1000
		SetTimer, ByeNotify, % Closetick
	}
}

Notify_Destroy() {
	global PN_hwnd
	ByeNotify:
	SetTimer, ByeNotify, Off
    winfade("ahk_id " PN_hwnd,0,5)
    Gui, Notify: Destroy
	return
}


WinMove(hwnd,position) {
   SysGet, Mon, MonitorWorkArea
   WinGetPos,ix,iy,w,h, ahk_id %hwnd%
   x := InStr(position,"l") ? MonLeft : InStr(position,"hc") ?  (MonRight-w)/2 : InStr(position,"r") ? MonRight - w : ix
   y := InStr(position,"t") ? MonTop : InStr(position,"vc") ?  (MonBottom-h) : InStr(position,"b") ? MonBottom - h : iy
   WinMove, ahk_id %hwnd%,,x,y
}

winfade(w:="",t:=128,i:=1,d:=10) {
    w:=(w="")?("ahk_id " WinActive("A")):w
    t:=(t>255)?255:(t<0)?0:t
    WinGet,s,Transparent,%w%
    s:=(s="")?255:s ;prevent trans unset bug
    WinSet,Transparent,%s%,%w%
    i:=(s<t)?abs(i):-1*abs(i)
    while(k:=(i<0)?(s>t):(s<t)&&WinExist(w)) {
        WinGet,s,Transparent,%w%
        s+=i
        WinSet,Transparent,%s%,%w%
        sleep %d%
    }
}

StringWidth(String, Font:="", FontSize:=10)
{
	Gui StringWidth:Font, s%FontSize%, %Font%
	Gui StringWidth:Add, Text, R1, %String%
	GuiControlGet T, StringWidth:Pos, Static1
	Gui StringWidth:Destroy
	return TW
}
