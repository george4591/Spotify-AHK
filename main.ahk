#MaxThreads 2

global client_id := "ad4a577db8204c61ba4ea90315de96b7"
global redirect_uri := "http:%2F%2Flocalhost:8000%2Fcallback"
global b64_client = "YWQ0YTU3N2RiODIwNGM2MWJhNGVhOTAzMTVkZTk2Yjc6MGJhZWQ4MmU0OTY2NGU5OTlmMGJhOWI3YmI1YTE4Mzk="
global defaultPlaylist
	
class Spotify {
	__New() {
		this.Util        := new Util(this)
		this.Player      := new Player(this)
		this.Playlist    := new Playlist(this)
	}
}

class Util {
	static MAX_RETRY := 3
	token_arg := {1:{1:"Content-Type", 2:"application/x-www-form-urlencoded"}, 2:{1:"Authorization", 2:"Basic " . b64_client}}


	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
		this.RefreshLoc   := "HKCU\Software\SpotifyAHK"
		this.AuthRetries  := 0 ; Count of how many times we have retried auth
		this.StartUp()
	}

	StartUp() {
		if (this.AuthRetries >= this.MAX_RETRY) {
			MsgBox, % "Spotify.ahk authorization attempt cap met, aborting"
			Spotify.Util := ""
			this         := ""
			Spotify      := ""
			return
		}
	
		RegRead, defaultPlaylist, % this.RefreshLoc, defaultPlaylist 
		If ErrorLevel = 1
		{

			RegWrite, REG_SZ, % this.RefreshLoc, defaultPlaylist, %defaultPlaylist%
		}

		RegRead, refresh, % this.RefreshLoc, refreshToken
		if (refresh) {
			this.RefreshTempToken(refresh)
		} else {
			this.auth          := ""
			paths              := {}
			paths["/callback"] := this["authCallback"].bind(this)
			server             := new HttpServer()
			server.SetPaths(paths)
			server.Serve(8000)
			Run, % "https://accounts.spotify.com/en/authorize?client_id=" . client_id . "&response_type=code&redirect_uri=" . redirect_uri . "&scope=" . scope
			loop {
				Sleep, -1
			} until (this.WebAuthDone() = true)
			this.FetchTokens()
	}
}
	
	; Timeout methods
	SetTimeout() {
		TimeOut := A_Now
		EnvAdd, TimeOut, 1, hours
		this.TimeOut := TimeOut
	}

	CheckTimeout() {
		if (this.TimeLastChecked = A_Min) {
			return
		}
		this.TimeLastChecked := A_Min
		if (A_Now > this.TimeOut) {
			RegRead, refresh, % this.RefreshLoc, refreshToken
			this.RefreshTempToken(refresh)
		}
	}
	
	GetRefreshToken(refresh) {
		refresh := this.DecryptToken(refresh)

		try {
			response := this.CustomCall("POST", "https://accounts.spotify.com/api/token?grant_type=refresh_token&refresh_token=" . refresh, this.token_arg, true)
		}
		catch E {
			if (InStr(E.What, "HTTP response code not 2xx")) {
				this.AuthRetries++
				MsgBox, % "Spotify.ahk could not get a valid refresh token from the Spotify API, retrying authorization."
				RegWrite, REG_SZ, % this.RefreshLoc, refreshToken, % "" ; Wipe the stored (bad) refresh token
				return this.StartUp() ; Retry auth and hope we get a valid refresh token this time
			}
		}

		return response
	}

	; API token operations
	RefreshTempToken(refresh) {
		Response := JSON.Load(this.GetRefreshToken(refresh))
		
		if (InStr(response, "refresh_token")) {
			this.SaveRefreshToken(response)
		}
			
		if (Response["access_token"]) {
			; If we got an access token, we can set the flag that we're authorized
			this.authState := true
			this.Token 	   := Response["access_token"] ; And store the new access token
			this.SetTimeout() ; And set when the new access token will expire
		}
		else {
			; Else if they didn't give us a new access token, something went wrong
			this.authState := false ; Set that auth is *not* complete
			this.AuthRetries++
			
			if (Response["error_description"] = "Invalid refresh token") {
				RegWrite, REG_SZ, % this.RefreshLoc, refreshToken, % "" ; Wipe the stored (bad) refresh token
				MsgBox, % "Spotify.ahk could not get a valid refresh token from the Spotify API, retrying authorization."
				return this.StartUp() ; Retry auth and hope we get a valid refresh token this time
			}
			
			Throw {"Message": Response["error_description"], "What": Response["error"], "File": A_LineFile, "Line": A_LineNumber}
			;this.StartUp() ; Call startup after wiping the stored refresh token, so we can try to get a new valid one
		}
	}

	FetchTokens() {
		if (this.fail) {
			ErrorLevel := 1
			return
		}
		if (this.authState) {
			return
		}
		AHKsock_Close(-1)
		response := this.CustomCall("POST", "https://accounts.spotify.com/api/token?grant_type=authorization_code&code=" . this.auth . "&redirect_uri=" . redirect_uri, this.token_arg, true)
		RegexMatch(response, "access_token"":""\K.*?(?="")", token)
		this.token := token
		this.SaveRefreshToken(response)
	}
	
	; Local token operations
	
	SaveRefreshToken(response) {
		RegexMatch(response, "refresh_token"":""\K.*?(?="")", response)
		if !(response) {
			return
		}
		response := this.encryptToken(response)
		RegWrite, REG_SZ, % this.RefreshLoc, RefreshToken, % response
		return
	}
	
	; API call method with auto-auth/timeout check/base URL
	
	CustomCall(method, url, HeaderArray := "", noTimeOut := false, body := "", noErr := false) {
		if !(noTimeOut) {
			this.CheckTimeout()
		}
		if !((InStr(url, "https://api.spotify.com")) || (InStr(url, "https://accounts.spotify.com/api/"))) {
			url := "https://api.spotify.com/v1/" . url
		}
		if !(HeaderArray) {
			HeaderArray :=  {1:{1:"Authorization", 2:"Bearer " . this.token}}
		}
		
		SpotifyWinHttp := ComObjCreate("WinHttp.WinHttpRequest.5.1")
		SpotifyWinHttp.Open(method, url, false)
		
		for index, SubHeaderArray in HeaderArray {
			SpotifyWinHttp.SetRequestHeader(SubHeaderArray[1], SubHeaderArray[2])
		}
		
		SpotifyWinHttp.Send(body)

		if (SpotifyWinHttp.Status > 299 && !noErr) {
			message := SpotifyWinHttp.Status . " not 2xx for request """ . method . ":" . url . """."
			MsgBox, %message%
		}
		
		return SpotifyWinHttp.ResponseText
	}
	
	; Web auth methods

	authCallback(self, ByRef req, ByRef res) {
		res.SetBodyText( req.queries["error"] ? "Error, authorization not given, the script will not function correctly without authorization." : "Authorization complete, you can close this window.")
		res.status := 200
		this.auth  := req.queries["code"]
		this.fail  := req.queries["error"]
	}

	WebAuthDone() {
		return (this.auth ? true : false)
	}
	
	; Token encryption/decryption methods
	
	EncryptToken(RefreshToken) {
		return crypt.encrypt.strEncrypt(RefreshToken, this.GetIDs(), 5, 3)
	}

	DecryptToken(RefreshToken) {
		try {
			return crypt.encrypt.strDecrypt(RefreshToken, this.GetIDs(), 5, 3)
		} catch {
			this.AuthRetries++
			MsgBox, % "Spotify.ahk could not decrypt local refresh token, retrying authorization"
			RegDelete, % this.RefreshLoc, RefreshToken
			this.StartUp()
			RegRead, RefreshToken, % this.RefreshLoc, refreshToken
			return crypt.encrypt.strDecrypt(RefreshToken, this.GetIDs(), 5, 3)
		}
	}

	GetIDs() {
		static infos := [["ProcessorID", "Win32_Service"], ["SKU", "Win32_BaseBoard"], ["DeviceID", "Win32_USBController"]]
		wmi := ComObjGet("winmgmts:")
		id  := ""
		for i, a in infos {
			wmin := wmi.execQuery("Select " . a[1] . " from " . a[2])._newEnum
			while wmin[wminf] {
				id .= wminf[a[1]]
			}
		}
		return id
	}
}

class Player {
	__New(ByRef ParentObject) {
		this.ParentObject := ParentObject
	}

	isPlaying[] {
		Get {
			return this.GetCurrentPlaybackInfo().id != ""
		}
	}

	GetArtist(ArtistID) {
		return new artist(JSON.Load(this.ParentObject.Util.CustomCall("GET", "artists/" . ArtistID)), this.ParentObject)
	}
	
	GetCurrentPlaybackInfo() {
		; Calls me/player, which returns a whole bunch of different objects
		; Translates JSON version of track objects into custom object
		Resp 		 := JSON.load(this.ParentObject.Util.CustomCall("GET", "me/player"))
		Resp.Track   := new track(Resp["item"], this.ParentObject)
		Resp.Track.genre := this.GetArtist(Resp.Track.artists[1].id).genres[1]
		return Resp.Track
	}

	SetRepeatMode(mode) {
		/*
		* Tells the API to change the repeat mode
		* Passing 3 or any other value that isn't 1/2 will turn off repeat
		*/
		return this.ParentObject.Util.CustomCall("PUT", "me/player/repeat?state=" . (mode = 1 ? "track" : (mode = 2 ? "context" : "off")))
	}

	SetShuffle(mode) {
		; Tells the API to change the shuffle mode to true/false, depending on what it it passed
		return this.ParentObject.Util.CustomCall("PUT", "me/player/shuffle?state=" . (mode ? "true" : "false"))
	}

	NextTrack() {
		return this.ParentObject.Util.CustomCall("POST", "me/player/next")
	}

	LastTrack() {
		return this.ParentObject.Util.CustomCall("POST", "me/player/previous")
	}

	PausePlayback() {
		return this.ParentObject.Util.CustomCall("PUT", "me/player/pause")
	}

	ResumePlayback() {
		return this.ParentObject.Util.CustomCall("PUT", "me/player/play")
	}
	
	PlayPause() {
		return ((this.GetCurrentPlaybackInfo()["is_playing"] = 0) ? (this.ResumePlayback()) : (this.PausePlayback()))
	}

	

}

class Playlist {
	__New(ByRef ParentObject) {
		this.ParentObject:= ParentObject
		this.userPlaylists    := this.GetPlaylists()
		this.user_id := JSON.Load(this.ParentObject.Util.CustomCall("GET", "me")).id
	}

	CreatePlaylist(name, description, public := true) {
		StringUpper, playlistName ,name,T

		headers := {1:{1:"Authorization", 2:"Bearer " . this.ParentObject.Util.token}, 2:{1:"Content-Type", 2:"application/json"}}
		body := "{""name"":""" . playlistName . """, ""description"":""" . description """, ""public"":" . public . "}"
		
		pid := JSON.Load(this.ParentObject.Util.CustomCall("POST", "users/" . this.user_id . "/playlists", headers, , body))
		this.userPlaylists := this.GetPlaylists()

		return pid
	}

	SaveToDefaultPlaylist() {
		this.ParentObject.Player.GetCurrentPlaybackInfo().Track.AddToPlaylist(defaultPlaylist, "Default")
	}

	SaveToGenreSpecificPlaylist(){
		if (this.ParentObject.Player.isPlaying == 0){
			TrayTip, Error, %message%, , 3
			return
		}

		currentSong := this.ParentObject.Player.GetCurrentPlaybackInfo()

		if(currentSong.IsSaved == 1) {
			PleasantNotify("Song already Added", 300, 30, "vc hc")
			return
		}

		if (!currentSong.genre) {
			this.SaveToDefaultPlaylist()
			return
		}

		for key, playlist in this.userPlaylists{
			if InStr(currentSong.genre, playlist.name){
				currentSong.AddToPlaylist(playlist.id, playlist.name)
				return
			}
		}

		Playlist := this.CreatePlaylist(currentSong.genre, "Playlist Made by frateleSpotify", true)
		currentSong.AddToPlaylist(Playlist.id, Playlist.name)
	}

	GetPlaylists() {
		; Gets user's playlists objects and stores them in an array
		resp 	  := JSON.Load(this.ParentObject.Util.CustomCall("GET", "me/playlists"))
		array    := []
		array.SetCapacity(resp["total"])

		loop, % Ceil(resp["total"]/50) {
			for key, playlist in JSON.load(this.ParentObject.Util.CustomCall("GET", "me/playlists?limit=50&offset=" . ((A_Index - 1 ) * 50)))["items"] {
				array.Push(new Playlist(playlist, this.ParentObject))
			}
		}

		return array
	}

	GetPlaylistSongs(PlaylistID) {
		; Gets user's songs from a specific playlist and stores them in an array
		resp      := JSON.Load(this.ParentObject.Util.CustomCall("GET", "playlists/" . PlaylistID . "/tracks"))
		array    := []
		array.SetCapacity(resp["total"])

		loop, % Ceil(resp["total"]/100) {
			for key, song in JSON.load(this.ParentObject.Util.CustomCall("GET", "playlists/" . PlaylistID . "/tracks?limit=100&offset=" . ((A_Index - 1) *100)))["items"] {
				array.Push(new track(song["track"], this.ParentObject))
			}
		}

		return array
	}

	ChangeDefaultPlaylists() {
		Gui, Add, ListView, r20 w400 gMyListView, id|name

		for index, value in this.userPlaylists {
			LV_Add("", index, value.name)
		}

		LV_ModifyCol()
		LV_ModifyCol(1, "Integer")

		; Display the window and return. The script will be notified whenever the user double clicks a row.
		Gui, Show
		return
		
		MyListView:
		MsgBox, 4, , You want this playlist to be the default playlist?
		IfMsgBox, Yes
		{
			LV_GetText(RowText, A_EventInfo)  ; Get the text from the row's first field.
			pid := usrPlaylists[RowText].id

			RegWrite, REG_SZ,HKCU, Software\SpotifyAHK, defaultPlaylist, %pid%
			MsgBox, Default playlist changed
			return
		}
		return
	}
}


class track {
	__New(ResponseTrackObj, ByRef Parent := "") {
		this.SpotifyObj := Parent
		this.json       := ResponseTrackObj
		this.id         := this.json["id"]
		this.uri        := this.json["uri"]
		this.artists    := []
		for k, v in this.json["artists"] {
			this.artists.Push(new artist(v, this.SpotifyObj))
		}
	}

	IsSaved[] {
		Get {
			return (this.SpotifyObj.Util.CustomCall("GET", "me/tracks/contains?ids=" . this.id) ~= "true" ? true : false)
		}
	}
	
	AddToPlaylist(id, name) {
		PleasantNotify("Added to: " . name , 300, 30, "vc hc")
		this.Save()
		return this.SpotifyObj.Util.CustomCall("POST", "playlists/" . id . "/tracks?uris=" . this.uri)
	}

	Save() {
		return this.SpotifyObj.Util.CustomCall("PUT", "me/tracks?ids=" . this.id)
	}
	
	UnSave() {
		return this.SpotifyObj.Util.CustomCall("DELETE", "me/tracks?ids=" . this.id)
	}
	
}

class artist {
	__New(Artistjson, ByRef Parent := "") {
		this.SpotifyObj := Parent
		this.json       := Artistjson
		this.genres     := this.json["genres"]
		this.id         := this.json["id"]
		this.name       := this.json["name"]
	}
}


#Include <AHKsock>
#Include <AHKhttp>
#Include <crypt>
#Include <json>
#Include <Notify>
