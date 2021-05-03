global client_id := "ad4a577db8204c61ba4ea90315de96b7"
global redirect_uri := "http:%2F%2Flocalhost:8000%2Fcallback"
global b64_client = "YWQ0YTU3N2RiODIwNGM2MWJhNGVhOTAzMTVkZTk2Yjc6MGJhZWQ4MmU0OTY2NGU5OTlmMGJhOWI3YmI1YTE4Mzk="
global MAX_RETRY := 3

class Util {
	
	;static RefreshLoc   := "HKCU\Software\SpotifyAHK"
	;static AuthRetries  := 0 ; Count of how many times we have retried auth
		

		__New(ByRef ParentObject) {
			this.ParentObject := ParentObject
			this.RefreshLoc   := "HKCU\Software\SpotifyAHK"
			this.AuthRetries  := 0 ; Count of how many times we have retried auth
			this.StartUp()
		}

		StartUp() {
			if (this.AuthRetries >= MAX_RETRY) {
				MsgBox, % "Spotify.ahk authorization attempt cap met, aborting"
				Spotify.Util := ""
				this         := ""
				Spotify      := ""
				return
			}
		

			RegRead, defaultPlaylist, % this.RefreshLoc, defaultPlaylist 
			msgbox, % defaultPlaylist
			If ErrorLevel = 1
			{

				RegWrite, REG_SZ, % this.RefreshLoc, defaultPlaylist, %defaultPlaylist%
			}

				
			RegRead, refresh, % this.RefreshLoc, refreshToken
			msgbox, % refresh
			
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
		
		; API token operations
		
		RefreshTempToken(refresh) {
			refresh := this.DecryptToken(refresh)
			arg := {1:{1:"Content-Type", 2:"application/x-www-form-urlencoded"}, 2:{1:"Authorization", 2:"Basic " . b64_client}}
			
			try {
				response := this.CustomCall("POST", "https://accounts.spotify.com/api/token?grant_type=refresh_token&refresh_token=" . refresh, arg, true)
			}
			catch E {
				if (InStr(E.What, "HTTP response code not 2xx")) {
					this.AuthRetries++
					MsgBox, % "Spotify.ahk could not get a valid refresh token from the Spotify API, retrying authorization."
					RegWrite, REG_SZ, % this.RefreshLoc, refreshToken, % "" ; Wipe the stored (bad) refresh token
					return this.StartUp() ; Retry auth and hope we get a valid refresh token this time
				}
			}

			Response := JSON.Load(response)
			
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
			arg := {1:{1:"Content-Type", 2:"application/x-www-form-urlencoded"}, 2:{1:"Authorization", 2:"Basic " . b64_client}}
			response := this.CustomCall("POST", "https://accounts.spotify.com/api/token?grant_type=authorization_code&code=" . this.auth . "&redirect_uri=" . redirect_uri, arg, true)
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


class SpotifyClient {
	static client_id := "ad4a577db8204c61ba4ea90315de96b7"
	static redirect_uri := "http:%2F%2Flocalhost:8000%2Fcallback"
	static b64_client := "YWQ0YTU3N2RiODIwNGM2MWJhNGVhOTAzMTVkZTk2Yjc6MGJhZWQ4MmU0OTY2NGU5OTlmMGJhOWI3YmI1YTE4Mzk="
	static default_playlist
}

class User
{
	__New() {
		MsgBox, % Util.CustomCall("GET", "me")
	}
}

Util.StartUp()
user := new User

#Include <AHKsock>
#Include <AHKhttp>
#Include <crypt>
#Include <json>
#Include <Notify>