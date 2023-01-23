#!/bin/zsh

#region security

assert_apple_id() {

	local appmail=$(security find-generic-password -a $USER -s appmail -w 2>/dev/null)
	local apppass=$(security find-generic-password -a $USER -s apppass -w 2>/dev/null)

	printf "\r\033[93m%s\033[00m" "CHECKING APPLE CREDENTIALS, PLEASE BE PATIENT"
	brew install robotsandpencils/made/xcodes &>/dev/null

	correct() {
		export XCODES_USERNAME="$appmail"
		export XCODES_PASSWORD="$apppass"
		expect <<-EOD
			log_user 0
			set timeout 8
			spawn xcodes install --latest
			expect {
				-re {.*(E|e)rror.*} { exit 1 }
				-re {.*(L|l)ocked.*} { exit 1 }
				-re {.*(P|p)assword.*} { exit 1 }
				timeout { exit 0 }
			}
		EOD
	}

	if ! correct; then
		security delete-generic-password -s appmail &>/dev/null
		security delete-generic-password -s apppass &>/dev/null
		printf "\r\033[91m%s\033[00m\n\n" "APPLE CREDENTIALS NOT IN KEYCHAIN OR INCORRECT"
		printf "\r\033[92m%s\033[00m\n" "security add-generic-password -a \$USER -s appmail -w username"
		printf "\r\033[92m%s\033[00m\n\n" "security add-generic-password -a \$USER -s apppass -w password"
		return 1
	fi

	return 0

}

assert_executor() {

	local is_root=$([[ $EUID = 0 ]] && echo "true" || echo "false")

	if [[ "$is_root" == "true" ]]; then
		printf "\r\033[91m%s\033[00m\n\n" "EXECUTING THIS SCRIPT AS ROOT IS NOT ADMITTED"
		return 1
	fi

	return 0

}

assert_password() {

	local account=$(security find-generic-password -a $USER -s account -w 2>/dev/null)
	local correct=$(sudo -k ; echo "$account" | sudo -S -v &>/dev/null && echo "true" || echo "false")

	if [[ "$correct" == "false" ]]; then
		security delete-generic-password -s account &>/dev/null
		printf "\r\033[91m%s\033[00m\n\n" "ACCOUNT PASSWORD NOT IN KEYCHAIN OR INCORRECT"
		printf "\r\033[92m%s\033[00m\n\n" "security add-generic-password -a \$USER -s account -w password"
		return 1
	fi

	return 0

}

handle_security() {

	# Verify version
	if [[ ${"$(sw_vers -productVersion)":0:2} != "13" ]]; then
		printf "\r\033[91m%s\033[00m\n\n" "CURRENT MACOS VERSION (${version:0:4}) IS NOT SUPPORTED"
		return 1
	fi

	# Output message
	printf "\r\033[93m%s\033[00m" "CHANGING SECURITY, PLEASE FOLLOW THE MESSAGES"

	# Handle functions
	allowed() { osascript -e 'tell application "System Events" to log ""' &>/dev/null }
	capable() { osascript -e 'tell application "System Events" to key code 60' &>/dev/null }
	granted() { ls "$HOME/Library/Messages" &>/dev/null }
	display() {
		heading=$(basename "$ZSH_ARGZERO" | cut -d . -f 1)
		osascript <<-EOD &>/dev/null
			tell application "${TERM_PROGRAM//Apple_/}"
				display alert "$heading" message "$1" as informational giving up after 10
			end tell
		EOD
	}

	while ! allowed; do
		display "You have to tap the OK button to continue."
		tccutil reset AppleEvents &>/dev/null
	done

	while ! capable; do
		display "You have to add your current terminal application to accessibility. When it's done, close the System Settings application to continue."
		open -W "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility"
	done

	while ! granted; do
		display "You have to add your current terminal application to full disk access. When it's done, close the System Settings application to continue."
		open -W "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles"
	done

}

#endregion

#region services

change_default_browser() {

	# Handle parameters
	local browser=${1:-safari}

	# Update dependencies
	brew install defaultbrowser

	# Change browser
	local factors=(brave chrome chromium firefox safari vivaldi)
	[[ ${factors[*]} =~ $browser ]] || return 1
	defaultbrowser "$browser" && osascript <<-EOD
		tell application "System Events"
			try
				tell application process "CoreServicesUIAgent"
					tell window 1
						tell (first button whose name starts with "use") to perform action "AXPress"
					end tell
				end tell
			end try
		end tell
	EOD

}

change_dock_items() {

	# Handle parameters
	local factors=("${@}")

	# Remove everything
	defaults write com.apple.dock persistent-apps -array

	# Append items
	for element in "${factors[@]}"; do
		local content="<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$element"
		local content="$content</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
		defaults write com.apple.dock persistent-apps -array-add "$content"
	done

}

expand_archive() {

	# Handle parameters
	local archive=${1}
	local deposit=${2:-.}
	local subtree=${3:-0}

	# Expand archive
	if [[ -n $archive && ! -f $deposit && $subtree =~ ^[0-9]+$ ]]; then
		mkdir -p "$deposit"
		if [[ $archive = http* ]]; then
			curl -L "$archive" | tar -zxf - -C "$deposit" --strip-components=$((subtree))
		else
			tar -zxf "$archive" -C "$deposit" --strip-components=$((subtree))
		fi
		printf "%s" "$deposit"
	fi

}

expand_pattern() {

	local pattern=${1}
	local expanse=${2:-0}

	# Expand pattern
	printf "%s" $(/bin/zsh -c "find $pattern -maxdepth $expanse" 2>/dev/null | sort -r | head -1)

}

expand_version() {

    local payload=${1}
    local default=${2:-0.0.0.0}

	# Update dependencies
    brew install grep
    brew upgrade grep

	# Expand version
    local starter=$(expand_pattern "$payload/*ontents/*nfo.plist")
    local version=$(defaults read "$starter" CFBundleShortVersionString 2>/dev/null)
    echo "$version" | ggrep -oP "[\d.]+" || echo "$default"

}

update_chromium_extension() {

	# Handle parameters
	local payload=${1}

	# Update extension
	if [[ -d "/Applications/Chromium.app" ]]; then
		if [[ ${payload:0:4} == "http" ]]; then
			local address="$payload"
			local package=$(mktemp -d)/$(basename "$address")
		else
			local version=$(defaults read "/Applications/Chromium.app/Contents/Info" CFBundleShortVersionString)
			local address="https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3"
			local address="${address}&prodversion=${version}&x=id%3D${payload}%26installsource%3Dondemand%26uc"
			local package=$(mktemp -d)/${payload}.crx
		fi
		curl -LA "mozilla/5.0" "$address" -o "$package" || return 1
		defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
		if [[ $package = *.zip ]]; then
			local storage="/Applications/Chromium.app/Unpacked/$(echo "$payload" | cut -d / -f5)"
			local present=$([[ -d "$storage" ]] && echo "true" || echo "false")
			expand_archive "$package" "$storage" 1
			if [[ "$present" == "false" ]]; then
				osascript <<-EOD
					set checkup to "/Applications/Chromium.app"
					tell application checkup
						activate
						reopen
						delay 4
						open location "chrome://extensions/"
						delay 2
						tell application "System Events"
							key code 48
							delay 2
							key code 49
							delay 2
							key code 48
							delay 2
							key code 49
							delay 2
							key code 5 using {command down, shift down}
							delay 2
							keystroke "$storage"
							delay 2
							key code 36
							delay 2
							key code 36
						end tell
						delay 2
						quit
						delay 2
					end tell
					tell application checkup
						activate
						reopen
						delay 4
						open location "chrome://extensions/"
						delay 2
						tell application "System Events"
							key code 48
							delay 2
							key code 49
						end tell
						delay 2
						quit
						delay 2
					end tell
				EOD
			fi
		else
			osascript <<-EOD
				set checkup to "/Applications/Chromium.app"
				tell application checkup
					activate
					reopen
					delay 4
					open location "file:///$package"
					delay 4
					tell application "System Events"
						key code 125
						delay 2
						key code 49
					end tell
					delay 6
					quit
					delay 2
				end tell
			EOD
		fi
	fi

}

update_jetbrains_plugin() {

	# Handle parameters
	local pattern=${1}
	local element=${2}

	# Update dependencies
	brew install grep jq
	brew upgrade grep jq

	# Update plugin
	local deposit=$(expand_pattern "$HOME/*ibrary/*pplication*upport/*/*$pattern*")
	if [[ -d $deposit ]]; then
		local checkup=$(expand_pattern "/*pplications/*${pattern:0:5}*/*ontents/*nfo.plist")
		local version=$(defaults read "$checkup" CFBundleVersion | ggrep -oP "[\d.]+" | cut -d . -f -3)
		autoload is-at-least
		for i in {1..3}; do
			for j in {0..19}; do
				local address="https://plugins.jetbrains.com/api/plugins/$element/updates?page=$i"
				local maximum=$(curl -LA "mozilla/5.0" "$address" | jq ".[$j].until" | tr -d '"' | sed "s/\.\*/\.9999/")
				local minimum=$(curl -LA "mozilla/5.0" "$address" | jq ".[$j].since" | tr -d '"' | sed "s/\.\*/\.9999/")
				if is-at-least "${minimum:-0000}" "$version" && is-at-least "$version" "${maximum:-9999}"; then
					local address=$(curl -LA "mozilla/5.0" "$address" | jq ".[$j].file" | tr -d '"')
					local address="https://plugins.jetbrains.com/files/$address"
					local plugins="$deposit/plugins" && mkdir -p "$plugins"
					[[ "$address" == *.zip ]] && expand_archive "$address" "$plugins"
					[[ "$address" == *.jar ]] && curl -LA "mozilla/5.0" "$address" -o "$plugins"
					break 2
				fi
				sleep 1
			done
		done
	fi

}

update_vscode_extension() {

	# Handle parameters
	local payload=${1}

	# Update extension
	code --install-extension "$payload" --force &>/dev/null || true

}

#endregion

#region updaters

update_android_cmdline() {

	# Update dependencies
	brew install fileicon grep
	brew upgrade fileicon grep
	brew install --cask --no-quarantine temurin
	brew upgrade --cask --no-quarantine temurin

	# Update package
	sdkroot="$HOME/Library/Android/sdk"
	deposit="$sdkroot/cmdline-tools"
	if [[ ! -d $deposit ]]; then
		mkdir -p "$deposit"
		website="https://developer.android.com/studio#command-tools"
		version="$(curl -s "$website" | ggrep -oP "commandlinetools-mac-\K(\d+)" | head -1)"
		address="https://dl.google.com/android/repository/commandlinetools-mac-${version}_latest.zip"
		archive="$(mktemp -d)/$(basename "$address")"
		curl -L "$address" -o "$archive"
		expand_archive "$archive" "$deposit"
		yes | "$deposit/cmdline-tools/bin/sdkmanager" --sdk_root="$sdkroot" "cmdline-tools;latest"
		rm -rf "$deposit/cmdline-tools"
	fi

	# Change environment
	configs="$HOME/.zshrc"
	if ! grep -q "ANDROID_HOME" "$configs" 2>/dev/null; then
		[[ -s "$configs" ]] || touch "$configs"
		[[ -z $(tail -1 "$configs") ]] || echo "" >>"$configs"
		echo 'export ANDROID_HOME="$HOME/Library/Android/sdk"' >>"$configs"
		echo 'export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"' >>"$configs"
		echo 'export PATH="$PATH:$ANDROID_HOME/emulator"' >>"$configs"
		echo 'export PATH="$PATH:$ANDROID_HOME/platform-tools"' >>"$configs"
		export ANDROID_HOME="$HOME/.android/sdk"
		export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"
		export PATH="$PATH:$ANDROID_HOME/emulator"
		export PATH="$PATH:$ANDROID_HOME/platform-tools"
	fi

}

update_android_studio() {

	# Update dependencies
	brew install fileicon grep xmlstarlet
	brew upgrade fileicon grep xmlstarlet

	# Update package
	starter="/Applications/Android Studio.app"
	present=$([[ -d "$starter" ]] && echo true || echo false)
	brew install --cask --no-quarantine android-studio
	brew upgrade --cask --no-quarantine android-studio

	# Launch package once
	if [[ $present = false ]]; then
		osascript <<-EOD
			set checkup to "/Applications/Android Studio.app"
			tell application checkup
				activate
				reopen
				tell application "System Events"
					tell process "Android Studio"
						with timeout of 30 seconds
							repeat until (exists window 1)
								delay 1
							end repeat
						end timeout
					end tell
				end tell
				delay 4
				quit app "Android Studio"
				delay 4
			end tell
		EOD
	fi

	# Finish installation
	if [[ $present == false ]]; then
		update_android_cmdline
		yes | sdkmanager --channel=0 "build-tools;33.0.1"
		yes | sdkmanager --channel=0 "emulator"
		yes | sdkmanager --channel=0 "extras;intel;Hardware_Accelerated_Execution_Manager"
		yes | sdkmanager --channel=0 "platform-tools"
		yes | sdkmanager --channel=0 "platforms;android-33"
		yes | sdkmanager --channel=0 "platforms;android-33-ext4"
		yes | sdkmanager --channel=0 "sources;android-33"
		yes | sdkmanager --channel=0 "system-images;android-33;google_apis;x86_64"
		avdmanager create avd -n "Pixel_3_API_33" -d "pixel_3" -k "system-images;android-33;google_apis;x86_64" -f
	fi

	# Change icons
	address="https://github.com/sharpordie/machogen/raw/HEAD/src/assets/android-studio.icns"
	picture="$(mktemp -d)/$(basename "$address")"
	curl -LA "mozilla/5.0" "$address" -o "$picture"
	fileicon set "/Applications/Android Studio.app" "$picture" || sudo !!

}

update_appearance() {

	# Change dock items
	local factors=(
		"/Applications/Chromium.app"
		"/Applications/Transmission.app"
		"/Applications/JDownloader 2.0/JDownloader2.app"

		"/Applications/UTM.app"
		"/Applications/Visual Studio Code.app"
		"/Applications/Xcode.app"
		"/Applications/Android Studio.app"
		"/Applications/PyCharm.app"
		"/Applications/DBeaverUltimate.app"
		# "/Applications/pgAdmin 4.app"
		"/Applications/Spotify.app"
		"/Applications/IINA.app"
		"/Applications/Figma.app"
		"/Applications/KeePassXC.app"
		"/Applications/JoalDesktop.app"
		"System/Applications/Utilities/Terminal.app"
		"/Applications/Docker.app/Contents/MacOS/Docker Desktop.app/"
		"/System/Applications/Stickies.app"
	)
	change_dock_items "${factors[@]}"

	# Change dock settings
	defaults write com.apple.dock autohide -bool true
	defaults write com.apple.dock autohide-delay -float 0
	defaults write com.apple.dock autohide-time-modifier -float 0.25
	defaults write com.apple.dock minimize-to-application -bool true
	defaults write com.apple.dock show-recents -bool false
	defaults write com.apple.Dock size-immutable -bool yes
	defaults write com.apple.dock tilesize -int 48
	defaults write com.apple.dock wvous-bl-corner -int 0
	defaults write com.apple.dock wvous-br-corner -int 0
	defaults write com.apple.dock wvous-tl-corner -int 0
	defaults write com.apple.dock wvous-tr-corner -int 0
	killall Dock

	# Change wallpaper
	local address="https://github.com/sharpordie/andpaper/raw/main/src/android-bottom-darken.png"
	local picture="$HOME/Pictures/Backgrounds/$(basename "$address")"
	mkdir -p "$(dirname $picture)" && curl -L "$address" -o "$picture"
	osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$picture\""

}

update_appcleaner() {

	# Update package
	brew install --cask --no-quarantine appcleaner
	brew upgrade --cask --no-quarantine appcleaner

	# Change icons
	local address="https://github.com/sharpordie/machogen/raw/HEAD/src/assets/appcleaner.icns"
	local picture="$(mktemp -d)/$(basename "$address")"
	curl -L "$address" -A "mozilla/5.0" -o "$picture"
	fileicon set "/Applications/AppCleaner.app" "$picture" || sudo !!

}

update_chromium() {

	# Handle parameters
	local deposit=${1:-$HOME/Downloads/DDL}
	local pattern=${2:-duckduckgo}
	local tabpage=${3:-about:blank}

	# Update dependencies
	brew install jq
	brew upgrade jq

	# Update package
	local starter="/Applications/Chromium.app"
	local present=$([[ -d "$starter" ]] && echo "true" || echo "false")
	brew install --cask --no-quarantine eloston-chromium
	brew upgrade --cask --no-quarantine eloston-chromium
	killall Chromium || true

	# Change default browser
	change_default_browser "chromium"

	# Finish installation
	if [[ "$present" == "false" ]]; then

		# Change language
		defaults write org.chromium.Chromium AppleLanguages "(en-US)"

		# Handle notification
		open -a "/Applications/Chromium.app"
		osascript <<-EOD
			if running of application "Chromium" then tell application "Chromium" to quit
			do shell script "/usr/bin/osascript -e 'tell application \"Chromium\" to do shell script \"\"' &>/dev/null &"
			repeat 5 times
				try
					tell application "System Events"
						tell application process "UserNotificationCenter"
							click button 3 of window 1
						end tell
					end tell
				end try
				delay 1
			end repeat
			if running of application "Chromium" then tell application "Chromium" to quit
			delay 4
		EOD
		killall "Chromium" && sleep 4

		# Change deposit
		mkdir -p "$deposit" && osascript <<-EOD
			set checkup to "/Applications/Chromium.app"
			tell application checkup
				activate
				reopen
				delay 4
				open location "chrome://settings/"
				delay 2
				tell application "System Events"
					keystroke "before downloading"
					delay 4
					repeat 3 times
						key code 48
					end repeat
					delay 2
					key code 36
					delay 4
					key code 5 using {command down, shift down}
					delay 4
					keystroke "${deposit}"
					delay 2
					key code 36
					delay 2
					key code 36
					delay 2
					key code 48
					key code 36
				end tell
				delay 2
				quit
				delay 2
			end tell
		EOD

		# Change engine
		osascript <<-EOD
			set checkup to "/Applications/Chromium.app"
			tell application checkup
				activate
				reopen
				delay 4
				open location "chrome://settings/"
				delay 2
				tell application "System Events"
					keystroke "search engines"
					delay 2
					repeat 3 times
						key code 48
					end repeat
					delay 2
					key code 49
					delay 2
					keystroke "${pattern}"
					delay 2
					key code 49
				end tell
				delay 2
				quit
				delay 2
			end tell
		EOD

		# Change custom-ntp
		osascript <<-EOD
			set checkup to "/Applications/Chromium.app"
			tell application checkup
				activate
				reopen
				delay 4
				open location "chrome://flags/"
				delay 2
				tell application "System Events"
					keystroke "custom-ntp"
					delay 2
					repeat 5 times
						key code 48
					end repeat
					delay 2
					keystroke "a" using {command down}
					delay 1
					keystroke "${tabpage}"
					delay 2
					key code 48
					key code 48
					delay 2
					key code 49
					delay 2
					key code 125
					delay 2
					key code 49
				end tell
				delay 2
				quit
				delay 2
			end tell
		EOD

		# Change extension-mime-request-handling
		osascript <<-EOD
			set checkup to "/Applications/Chromium.app"
			tell application checkup
				activate
				reopen
				delay 4
				open location "chrome://flags/"
				delay 2
				tell application "System Events"
					keystroke "extension-mime-request-handling"
					delay 2
					repeat 6 times
						key code 48
					end repeat
					delay 2
					key code 49
					delay 2
					key code 125
					key code 125
					delay 2
					key code 49
				end tell
				delay 2
				quit
				delay 2
			end tell
		EOD

		# Change hide-sidepanel-button
		osascript <<-EOD
			set checkup to "/Applications/Chromium.app"
			tell application checkup
				activate
				reopen
				delay 4
				open location "chrome://flags/"
				delay 2
				tell application "System Events"
					keystroke "hide-sidepanel-button"
					delay 2
					repeat 6 times
						key code 48
					end repeat
					delay 2
					key code 49
					delay 2
					key code 125
					delay 2
					key code 49
				end tell
				delay 2
				quit
				delay 2
			end tell
		EOD

		# Change remove-tabsearch-button
		osascript <<-EOD
			set checkup to "/Applications/Chromium.app"
			tell application checkup
				activate
				reopen
				delay 4
				open location "chrome://flags/"
				delay 2
				tell application "System Events"
					keystroke "remove-tabsearch-button"
					delay 2
					repeat 6 times
						key code 48
					end repeat
					delay 2
					key code 49
					delay 2
					key code 125
					delay 2
					key code 49
				end tell
				delay 2
				quit
				delay 2
			end tell
		EOD

		# Change show-avatar-button
		osascript <<-EOD
			set checkup to "/Applications/Chromium.app"
			tell application checkup
				activate
				reopen
				delay 4
				open location "chrome://flags/"
				delay 2
				tell application "System Events"

					keystroke "show-avatar-button"
					delay 2
					repeat 6 times
						key code 48
					end repeat
					delay 2
					key code 49
					delay 2
					key code 125
					key code 125
					key code 125
					delay 2
					key code 49
				end tell
				delay 2
				quit
				delay 2
			end tell
		EOD

		# Remove bookmark bar
		osascript <<-EOD
			set checkup to "/Applications/Chromium.app"
			tell application checkup
				activate
				reopen
				delay 4
				open location "about:blank"
				delay 2
				tell application "System Events"
					keystroke "b" using {shift down, command down}
				end tell
				delay 2
				quit
				delay 2
			end tell
		EOD

		# Revert language
		defaults delete org.chromium.Chromium AppleLanguages

		# Update chromium-web-store
		website="https://api.github.com/repos/NeverDecaf/chromium-web-store/releases"
		version=$(curl -s "$website" | jq -r ".[0].tag_name" | tr -d "v")
		address="https://github.com/NeverDecaf/chromium-web-store/releases/download/v$version/Chromium.Web.Store.crx"
		update_chromium_extension "$address"

		# Update extensions
		update_chromium_extension "bcjindcccaagfpapjjmafapmmgkkhgoa" # json-formatter
		update_chromium_extension "ibplnjkanclpjokhdolnendpplpjiace" # simple-translate
		update_chromium_extension "mnjggcdmjocbbbhaepdhchncahnbgone" # sponsorblock-for-youtube
		update_chromium_extension "cjpalhdlnbpafiamejdnhcphjbkeiagm" # ublock-origin

	fi

	# Update bypass-paywalls-chrome
	update_chromium_extension "https://github.com/iamadamdev/bypass-paywalls-chrome/archive/master.zip"

}

update_dbeaver() {

	# Update dependencies
    brew install curl jq
    brew upgrade curl jq

	# Update package
    local address="https://dbeaver.com/download/ultimate/"
    local pattern="DBeaver Ultimate Edition \K([\d.]+)"
    local version=$(curl -LA "mozilla/5.0" "$address" | ggrep -oP "$pattern" | head -1)
    local current=$(expand_version "/*ppl*/*eav*lti*")
    autoload is-at-least
    local updated=$(is-at-least "$version" "$current" && echo "true" || echo "false")
    if [[ "$updated" == "false" ]]; then
	    local cpuname=$(sysctl -n machdep.cpu.brand_string)
	    local silicon=$([[ $cpuname =~ "pple" ]] && echo "true" || echo "false")
	    local adjunct=$([[ $silicon == "true" ]] && echo "aarch64" || echo "x86_64")
        local address="https://download.dbeaver.com/ultimate/$version.0/dbeaver-ue-$version.0-macos-$adjunct.dmg"
	    local fetched="$(mktemp -d)/$(basename "$address")"
		curl -LA "mozilla/5.0" "$address" -o "$fetched"
        hdiutil convert "$fetched" -format UDTO -o "$fetched.cdr"
		hdiutil attach "$fetched.cdr" -noautoopen -nobrowse
		cp -fr /Volumes/DB*/DB*.app /Applications
		hdiutil detach /Volumes/DB*
		sudo xattr -rd com.apple.quarantine /*ppl*/*eav*lti*
    fi

}

update_docker() {

	# Update dependencies
    brew install curl jq
    brew upgrade curl jq
    
	# Update package
    local address="https://docs.docker.com/desktop/release-notes/"
    local pattern="<h2 id=\"[\d]+\">\K([\d.]+)"
    local version=$(curl -LA "mozilla/5.0" "$address" | ggrep -oP "$pattern" | head -1)
    local current=$(expand_version "/*ppl*/*ocke*")
    autoload is-at-least
    local updated=$(is-at-least "$version" "$current" && echo "true" || echo "false")
    if [[ "$updated" == "false" ]]; then
	    local cpuname=$(sysctl -n machdep.cpu.brand_string)
	    local silicon=$([[ $cpuname =~ "pple" ]] && echo "true" || echo "false")
	    local adjunct=$([[ $silicon == "true" ]] && echo "arm64" || echo "amd64")
        local address="https://desktop.docker.com/mac/main/$adjunct/Docker.dmg"
	    local fetched="$(mktemp -d)/$(basename "$address")"
        curl -LA "mozilla/5.0" "$address" -o "$fetched"
		sudo hdiutil attach "$fetched"
        sudo /Volumes/Docker/Docker.app/Contents/MacOS/install --accept-license --user=$USER
        sudo hdiutil detach /Volumes/Docker
    fi

}

update_dotnet() {

	# Update package
	brew install --cask --no-quarantine dotnet-sdk
	brew upgrade --cask --no-quarantine dotnet-sdk

	# Change environment
	if ! grep -q "DOTNET_CLI_TELEMETRY_OPTOUT" "$HOME/.zshrc" 2>/dev/null; then
		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"
		echo 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' >>"$HOME/.zshrc"
		echo 'export DOTNET_NOLOGO=1' >>"$HOME/.zshrc"
		echo 'export PATH="$PATH:/Users/$USER/.dotnet/tools"' >>"$HOME/.zshrc"
		source "$HOME/.zshrc"
	fi

}

update_flutter() {

	# Update dependencies
	brew install dart
	brew upgrade dart

	# Update package
	brew install --cask --no-quarantine flutter
	brew upgrade --cask --no-quarantine flutter

	# Change environment
	local altered="$(grep -q "CHROME_EXECUTABLE" "$HOME/.zshrc" >/dev/null 2>&1 && echo "true" || echo "false")"
	local present="$([[ -d "/Applications/Chromium.app" ]] && echo "true" || echo "false")"
	if [[ "$altered" == "false" && "$present" == "true" ]]; then
		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"
		echo 'export CHROME_EXECUTABLE="/Applications/Chromium.app/Contents/MacOS/Chromium"' >>"$HOME/.zshrc"
		source "$HOME/.zshrc"
	fi

	# Finish installation
	flutter precache && flutter upgrade
	dart --disable-analytics
	flutter config --no-analytics
	yes | flutter doctor --android-licenses

	# Update android-studio plugins
	update_jetbrains_plugin "AndroidStudio" "6351"   # dart
	update_jetbrains_plugin "AndroidStudio" "9212"   # flutter
	update_jetbrains_plugin "AndroidStudio" "13666"  # flutter-intl
	update_jetbrains_plugin "AndroidStudio" "14641"  # flutter-riverpod-snippets

	# Update vscode extensions
	update_vscode_extension "alexisvt.flutter-snippets"
	update_vscode_extension "dart-code.flutter"
	update_vscode_extension "pflannery.vscode-versionlens"
	update_vscode_extension "RichardCoutts.mvvm-plus"
	update_vscode_extension "robert-brunhage.flutter-riverpod-snippets"
	update_vscode_extension "usernamehw.errorlens"

	# TODO: Add `readlink -f $(which flutter)` to android-studio
	# /usr/local/Caskroom/flutter/*/flutter

}

update_figma() {

	# Update package
	brew install --cask --no-quarantine figma
	brew upgrade --cask --no-quarantine figma

}

update_git() {

	# Handle parameters
	local default=${1:-main}
	local gituser=${2}
	local gitmail=${3}

	# Update package
	brew install gh git
	brew upgrade gh git

	# Change settings
	git config --global credential.helper "store"
	git config --global http.postBuffer 1048576000
	git config --global init.defaultBranch "$default"
	[[ -n "$gitmail" ]] && git config --global user.email "$gitmail" || true
	[[ -n "$gituser" ]] && git config --global user.name "$gituser" || true

}

update_homebrew() {

	# Update package
	printf "\r\033[93m%s\033[00m" "UPGRADING HOMEBREW PACKAGE, PLEASE BE PATIENT"
	local command=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
	CI=1 /bin/bash -c "$command" &>/dev/null

}

update_iina() {

	# Update dependencies
	brew install yt-dlp
	brew upgrade yt-dlp

	# Update package
	local present=$([[ -d "/Applications/IINA.app" ]] && echo "true" || echo "false")
	brew install --cask --no-quarantine iina
	brew upgrade --cask --no-quarantine iina

	# Finish installation
	if [[ "$present" == "false" ]]; then
		osascript <<-EOD
			set checkup to "/Applications/IINA.app"
			tell application checkup
				activate
				reopen
				tell application "System Events"
					with timeout of 10 seconds
						repeat until (exists window 1 of application process "IINA")
							delay 0.02
						end repeat
						tell application process "IINA" to set visible to false
					end timeout
				end tell
				delay 4
				quit
				delay 4
			end tell
		EOD
		update_chromium_extension "pdnojahnhpgmdhjdhgphgdcecehkbhfo"
	fi

	# Change settings
	ln -s /usr/local/bin/yt-dlp /usr/local/bin/youtube-dl
	defaults write com.colliderli.iina recordPlaybackHistory -integer 0
	defaults write com.colliderli.iina recordRecentFiles -integer 0
	defaults write com.colliderli.iina SUEnableAutomaticChecks -integer 0
	defaults write com.colliderli.iina ytdlSearchPath "/usr/local/bin"

	# Change association
	local address="https://api.github.com/repos/jdek/openwith/releases/latest"
	local version=$(curl -LA "mozilla/5.0" "$address" | jq -r ".tag_name" | tr -d "v")
	local address="https://github.com/jdek/openwith/releases/download/v$version/openwith-v$version.tar.xz"
	local archive=$(mktemp -d)/$(basename "$address") && curl -LA "mozilla/5.0" "$address" -o "$archive"
	local deposit=$(mktemp -d)
	expand_archive "$archive" "$deposit"
	"$deposit/openwith" com.colliderli.iina mkv mov mp4 avi

	# Change icons
	local address="https://github.com/sharpordie/machogen/raw/HEAD/src/assets/iina.icns"
	local picture="$(mktemp -d)/$(basename "$address")"
	curl -LA "mozilla/5.0" "$address" -o "$picture"
	fileicon set "/Applications/IINA.app" "$picture" || sudo !!

}

update_jdownloader() {

	# Handle parameters
	local deposit=${1:-$HOME/Downloads/JD2}

	# Update dependencies
	brew install coreutils fileicon jq
	brew upgrade coreutils fileicon jq
	brew install --cask --no-quarantine homebrew/cask-versions/temurin8
	brew upgrade --cask --no-quarantine homebrew/cask-versions/temurin8

	# Update package
	local present=$([[ -d "/Applications/JDownloader 2.0/JDownloader2.app" ]] && echo "true" || echo "false")
	brew install --cask --no-quarantine jdownloader
	brew upgrade --cask --no-quarantine jdownloader

	# Finish installation
	if [[ "$present" == "false" ]]; then
		local appdata="/Applications/JDownloader 2.0/cfg"
		local config1="$appdata/org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
		local config2="$appdata/org.jdownloader.settings.GeneralSettings.json"
		local config3="$appdata/org.jdownloader.gui.jdtrayicon.TrayExtension.json"
		local config4="$appdata/org.jdownloader.extensions.extraction.ExtractionExtension.json"
		osascript <<-EOD
			set checkup to "/Applications/JDownloader 2.0/JDownloader2.app"
			tell application checkup
				activate
				reopen
				tell application "System Events"
					repeat until (exists window 1 of application process "JDownloader2")
						delay 0.02
					end repeat
					tell application process "JDownloader2" to set visible to false
					repeat until (do shell script "test -f '$config1' && echo true || echo false") as boolean is true
						delay 1
					end repeat
				end tell
				delay 8
				quit
				delay 4
			end tell
		EOD
		jq ".bannerenabled = false" "$config1" | sponge "$config1"
		jq ".clipboardmonitored = false" "$config1" | sponge "$config1"
		jq ".donatebuttonlatestautochange = 4102444800000" "$config1" | sponge "$config1"
		jq ".donatebuttonstate = \"AUTO_HIDDEN\"" "$config1" | sponge "$config1"
		jq ".myjdownloaderviewvisible = false" "$config1" | sponge "$config1"
		jq ".premiumalertetacolumnenabled = false" "$config1" | sponge "$config1"
		jq ".premiumalertspeedcolumnenabled = false" "$config1" | sponge "$config1"
		jq ".premiumalerttaskcolumnenabled = false" "$config1" | sponge "$config1"
		jq ".specialdealoboomdialogvisibleonstartup = false" "$config1" | sponge "$config1"
		jq ".specialdealsenabled = false" "$config1" | sponge "$config1"
		jq ".speedmetervisible = false" "$config1" | sponge "$config1"
		mkdir -p "$deposit" && jq ".defaultdownloadfolder = \"$deposit\"" "$config2" | sponge "$config2"
		jq ".enabled = false" "$config3" | sponge "$config3"
		jq ".enabled = false" "$config4" | sponge "$config4"
		update_chromium_extension "fbcohnmimjicjdomonkcbcpbpnhggkip"
	fi

	# Change icons
	local address="https://github.com/sharpordie/machogen/raw/HEAD/src/assets/jdownloader.icns"
	local picture="$(mktemp -d)/$(basename "$address")"
	curl -LA "mozilla/5.0" "$address" -o "$picture"
	fileicon set "/Applications/JDownloader 2.0/JDownloader2.app" "$picture" || sudo !!
	fileicon set "/Applications/JDownloader 2.0/JDownloader Uninstaller.app" "$picture" || sudo !!
	cp "$picture" "/Applications/JDownloader 2.0/JDownloader2.app/Contents/Resources/app.icns"
	sips -Z 128 -s format png "$picture" --out "/Applications/JDownloader 2.0/themes/standard/org/jdownloader/images/logo/jd_logo_128_128.png"

}

update_joal() {

	# Update dependencies
	brew install grep jq
	brew upgrade grep jq

	# Update package
	local address="https://api.github.com/repos/anthonyraymond/joal-desktop/releases/latest"
	local version=$(curl -LA "mozilla/5.0" "$address" | jq -r ".tag_name" | tr -d "v")
	local current=$(expand_version "/*ppl*/*oal*esk*")
	autoload is-at-least
    local updated=$(is-at-least "$version" "$current" && echo "true" || echo "false")
    if [[ "$updated" == "false" ]]; then
		local address="https://github.com/anthonyraymond/joal-desktop/releases"
		local address="$address/download/v$version/JoalDesktop-$version-mac-x64.dmg"
		local package=$(mktemp -d)/$(basename "$address") && curl -LA "mozilla/5.0" "$address" -o "$package"
		hdiutil attach "$package" -noautoopen -nobrowse
		cp -fr /Volumes/Joal*/Joal*.app /Applications
		hdiutil detach /Volumes/Joal*
		sudo xattr -rd com.apple.quarantine /Applications/Joal*.app
	fi

	# Change icons
	local address="https://github.com/sharpordie/machogen/raw/HEAD/src/assets/joal-desktop.icns"
	local picture="$(mktemp -d)/$(basename "$address")"
	curl -LA "mozilla/5.0" "$address" -o "$picture"
	fileicon set "/Applications/JoalDesktop.app" "$picture" || sudo !!

}

update_keepassxc() {

	# Update package
	brew install --cask --no-quarantine keepassxc
	brew upgrade --cask --no-quarantine keepassxc

}

update_mambaforge() {

	# Update package
	brew install mambaforge
	brew upgrade mambaforge

	# Change environment
	conda init zsh

	# Change settings
	conda config --set auto_activate_base false

}

update_nightlight() {

	# Handle parameters
	local percent=${1:-75}
	local forever=${2:-true}

	# Update package
	brew install smudge/smudge/nightlight
	brew upgrade smudge/smudge/nightlight

	# Change settings
	[[ "$forever" == "true" ]] && nightlight schedule 3:00 2:59
	nightlight temp "$percent" && nightlight on

}

update_nodejs() {

	# Update dependencies
	brew install grep
	brew upgrade grep

	# Update package
	local address="https://nodejs.org/en/download/"
	local pattern="LTS Version: <strong>\K([\d]+)"
	version=$(curl -LA "mozilla/5.0" "$address" | ggrep -oP "$pattern" | head -1)
	brew install node@"$version"
	brew upgrade node@"$version"

	# Change environment
	if ! grep -q "/usr/local/opt/node" "$HOME/.zshrc" 2>/dev/null; then
		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"
		echo "export PATH=\"\$PATH:/usr/local/opt/node@$version/bin\"" >>"$HOME/.zshrc"
		source "$HOME/.zshrc"
	else
		sed -i "" -e "s#/usr/local/opt/node.*/bin#/usr/local/opt/node@$version/bin#" "$HOME/.zshrc"
		source "$HOME/.zshrc"
	fi

}

update_odoo() {

	# Update dependencies
	update_python

	# Update postgresql
	update_postgresql
	su - postgres createuser -sdP odoo

	# Update nodejs
	update_nodejs
	npm install -g rtlcss

	# Update wkhtmltopdf
	brew install --cask --no-quarantine wkhtmltopdf
	brew upgrade --cask --no-quarantine wkhtmltopdf

	# Update pycharm plugins
	update_jetbrains_plugin "PyCharm" "10037" # csv-editor
	update_jetbrains_plugin "PyCharm" "12478" # xpathview-xslt
	update_jetbrains_plugin "PyCharm" "13499" # odoo

	# Update vscode extensions
	update_vscode_extension "jigar-patel.odoosnippets"

}

update_pgadmin() {

	# Update package
	brew install --cask --no-quarantine pgadmin4
	brew upgrade --cask --no-quarantine pgadmin4

}

update_postgresql() {

	# Update package
	brew install postgresql@14
	brew upgrade postgresql@14
	brew services restart postgresql@14

}

update_pycharm() {

	# Handle parameters
	local deposit="${1:-$HOME/Projects}"

	# Update dependencies
	brew install fileicon
	brew upgrade fileicon

	# Update package
	local present=$([[ -d "/Applications/PyCharm.app" ]] && echo "true" || echo "false")
	brew install --cask --no-quarantine pycharm
	brew upgrade --cask --no-quarantine pycharm

	# Finish installation
	if [[ "$present" == "false" ]]; then
		osascript <<-EOD
			set checkup to "/Applications/PyCharm.app"
			tell application checkup
				activate
				reopen
				tell application "System Events"
					tell process "PyCharm"
						with timeout of 30 seconds
							repeat until (exists window 1)
								delay 1
							end repeat
						end timeout
					end tell
				end tell
				delay 4
				quit app "PyCharm"
				delay 4
			end tell
		EOD
	fi

	# Change icons
	local address="https://github.com/sharpordie/machogen/raw/HEAD/src/assets/pycharm.icns"
	local picture="$(mktemp -d)/$(basename "$address")"
	curl -LA "mozilla/5.0" "$address" -o "$picture"
	fileicon set "/Applications/PyCharm.app" "$picture" || sudo !!

}

update_python() {

	# Handle parameters
	local version=${1:-3.10}

	# Update package
	brew install python@"$version" poetry
	brew upgrade python@"$version" poetry
	brew unlink python@3.9
	brew link --force python@"$version"

	# Change environment
	if ! grep -q "PYTHONDONTWRITEBYTECODE" "$HOME/.zshrc" 2>/dev/null; then
		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"
		echo "export PYTHONDONTWRITEBYTECODE=1" >>"$HOME/.zshrc"
		source "$HOME/.zshrc"
	fi

	# Update vscode extensions
	update_vscode_extension "ms-python.python"

	# Change settings
	poetry config virtualenvs.in-project true

}

update_spotify() {

	# Update dependencies
	brew install fileicon
	brew upgrade fileicon

	# Update package
	brew uninstall --cask spotify
	brew install --cask --no-quarantine spotify
	bash <(curl -sSL https://raw.githubusercontent.com/SpotX-CLI/SpotX-Mac/main/install.sh) -ceu -E leftsidebar

	# TODO: Remove autorun

	# Change icons
	local address="https://github.com/sharpordie/machogen/raw/HEAD/src/assets/spotify.icns"
	local picture="$(mktemp -d)/$(basename "$address")"
	curl -LA "mozilla/5.0" "$address" -o "$picture"
	fileicon set "/Applications/Spotify.app" "$picture" || sudo !!

}

update_scrcpy() {

	# Update package
	brew install scrcpy
	brew upgrade scrcpy

}

update_system() {

	# Handle parameters
	local country=${1:-Europe/Brussels}
	local machine=${2:-macintosh}

	# Change hostname
	sudo scutil --set ComputerName "$machine"
	sudo scutil --set HostName "$machine"
	sudo scutil --set LocalHostName "$machine"
	sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$machine"

	# Change timezone
	sudo systemsetup -settimezone "$country"

	# Change finder
	defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
	defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
	defaults write com.apple.finder ShowPathbar -bool true

	# Change globals
	defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
	defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

	# Change preview
	defaults write com.apple.Preview NSRecentDocumentsLimit 0
	defaults write com.apple.Preview NSRecentDocumentsLimit 0

	# Change services
	defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
	defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
	defaults write com.apple.LaunchServices "LSQuarantine" -bool false

	# Enable subpixel rendering
	defaults write NSGlobalDomain AppleFontSmoothing -int 2

	# Enable tap-to-click
	defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
	defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

	# Remove remnants
	find ~ -name ".DS_Store" -delete

	# Update system
	sudo softwareupdate -ia

}

update_the_unarchiver() {

	# Update package
	local present=$([[ -d "/Applications/The Unarchiver.app" ]] && echo "true" || echo "false")
	brew install --cask --no-quarantine the-unarchiver
	brew upgrade --cask --no-quarantine the-unarchiver

	# Finish installation
	if [[ "$present" == "false" ]]; then
		osascript <<-EOD
			set checkup to "/Applications/The Unarchiver.app"
			tell application checkup
				activate
				reopen
				tell application "System Events"
					with timeout of 10 seconds
						repeat until (exists window 1 of application process "The Unarchiver")
							delay 1
						end repeat
					end timeout
					tell process "The Unarchiver"
						try
							click button "Accept" of window 1
							delay 2
						end try
						click button "Select All" of tab group 1 of window 1
					end tell
				end tell
				delay 2
				quit
				delay 2
			end tell
		EOD
	fi

	# Change settings
	defaults write com.macpaw.site.theunarchiver extractionDestination -integer 3
	defaults write com.macpaw.site.theunarchiver isFreshInstall -integer 1
	defaults write com.macpaw.site.theunarchiver userAgreedToNewTOSAndPrivacy -integer 1

}

update_transmission() {

	# Handle parameters
	local deposit=${1:-$HOME/Downloads/P2P}
	local seeding=${2:-0.1}

	# Update package
	brew install --cask --no-quarantine transmission
	brew upgrade --cask --no-quarantine transmission

	# Change settings
	mkdir -p "$deposit/Incompleted"
	defaults write org.m0k.transmission DownloadFolder -string "$deposit"
	defaults write org.m0k.transmission IncompleteDownloadFolder -string "$deposit/Incompleted"
	defaults write org.m0k.transmission RatioCheck -bool true
	defaults write org.m0k.transmission RatioLimit -int "$seeding"
	defaults write org.m0k.transmission UseIncompleteDownloadFolder -bool true
	defaults write org.m0k.transmission WarningDonate -bool false
	defaults write org.m0k.transmission WarningLegal -bool false

	# Change icons
	local address="https://github.com/sharpordie/machogen/raw/HEAD/src/assets/transmission.icns"
	local picture="$(mktemp -d)/$(basename "$address")"
	curl -LA "mozilla/5.0" "$address" -o "$picture"
	fileicon set "/Applications/Transmission.app" "$picture" || sudo !!

}

update_utm() {

	# Update package
	brew install --cask --no-quarantine utm
	brew upgrade --cask --no-quarantine utm

}

update_vscode() {

	# Update dependencies
	brew install jq sponge
	brew upgrade jq sponge

	# Update package
	brew install --cask --no-quarantine visual-studio-code
	brew upgrade --cask --no-quarantine visual-studio-code
	
	# Update extensions
	update_vscode_extension "foxundermoon.shell-format"
	update_vscode_extension "github.github-vscode-theme"

	# Change settings
	local configs="$HOME/Library/Application Support/Code/User/settings.json"
	[[ -s "$configs" ]] || echo "{}" >"$configs"
	jq '."editor.fontSize" = 12' "$configs" | sponge "$configs"
	jq '."editor.lineHeight" = 28' "$configs" | sponge "$configs"
	jq '."security.workspace.trust.enabled" = false' "$configs" | sponge "$configs"
	jq '."telemetry.telemetryLevel" = "crash"' "$configs" | sponge "$configs"
	jq '."update.mode" = "none"' "$configs" | sponge "$configs"
	jq '."workbench.colorTheme" = "GitHub Dark Default"' "$configs" | sponge "$configs"
	jq '."workbench.startupEditor" = "none"' "$configs" | sponge "$configs"
	
}

update_xcode() {

	# Verify apple id
	assert_apple_id || return 1

	# Update dependencies
	brew install cocoapods fileicon robotsandpencils/made/xcodes
	brew upgrade cocoapods fileicon robotsandpencils/made/xcodes

	# Update package
	xcodes install --latest
	mv -f /Applications/Xcode*.app /Applications/Xcode.app
	sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
	sudo xcodebuild -runFirstLaunch
	sudo xcodebuild -license accept

	# Change icons
	local address="https://github.com/sharpordie/machogen/raw/HEAD/src/assets/xcode.icns"
	local picture="$(mktemp -d)/$(basename "$address")"
	curl -LA "mozilla/5.0" "$address" -o "$picture"
	fileicon set "/Applications/Xcode.app" "$picture" || sudo !!

}

#endregion

main() {

	# Verify executor
	assert_executor || return 1

	# Prompt password
	sudo -v && clear

	# Change headline
	printf "\033]0;%s\007" "$(basename "$ZSH_ARGZERO" | cut -d . -f 1)"

	# Output greeting
	read -r -d "" welcome <<-EOD
		███╗░░░███╗░█████╗░░█████╗░██╗░░██╗░█████╗░░██████╗░███████╗███╗░░██╗
		████╗░████║██╔══██╗██╔══██╗██║░░██║██╔══██╗██╔════╝░██╔════╝████╗░██║
		██╔████╔██║███████║██║░░╚═╝███████║██║░░██║██║░░██╗░█████╗░░██╔██╗██║
		██║╚██╔╝██║██╔══██║██║░░██╗██╔══██║██║░░██║██║░░╚██╗██╔══╝░░██║╚████║
		██║░╚═╝░██║██║░░██║╚█████╔╝██║░░██║╚█████╔╝╚██████╔╝███████╗██║░╚███║
		╚═╝░░░░░╚═╝╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝░╚════╝░░╚═════╝░╚══════╝╚═╝░░╚══╝
	EOD
	printf "\n\033[92m%s\033[00m\n\n" "$welcome"

	# Remove timeouts
	echo "Defaults timestamp_timeout=-1" | sudo tee /private/etc/sudoers.d/disable_timeout >/dev/null

	# Remove sleeping
	sudo pmset -a disablesleep 1 && (caffeinate -i -w $$ &) &>/dev/null

	# Verify password
	# assert_password || return 1

	# Handle security
	handle_security || return 1

	# Update homebrew
	update_homebrew || return 1

	# Verify apple id
	# assert_apple_id || return 1

	# Handle elements
	local factors=(
		"update_system"

		"update_android_studio"
		"update_chromium"
		"update_git 'main' 'sharpordie' '72373746+sharpordie@users.noreply.github.com'"
		"update_pycharm"
		"update_vscode"
		# "update_xcode"

		"update_appcleaner"
		"update_dbeaver"
		"update_docker"
		# "update_dotnet"
		"update_figma"
		"update_flutter"
		"update_iina"
		"update_jdownloader"
		"update_joal"
		"update_keepassxc"
		"update_mambaforge"
		"update_nightlight"
		"update_nodejs"
		# "update_pgadmin"
		# "update_postgresql"
		"update_python"
		# "update_odoo"
		"update_scrcpy"
		# "update_spotify"
		"update_the_unarchiver"
		"update_transmission"
		"update_utm"

		"update_appearance"
	)

	# Output progress
	local maximum=$((${#welcome} / $(echo "$welcome" | wc -l)))
	local heading="\r%-"$((maximum - 20))"s   %-6s   %-8s\n\n"
	local loading="\r%-"$((maximum - 20))"s   \033[93mACTIVE\033[0m   %-8s\b"
	local failure="\r%-"$((maximum - 20))"s   \033[91mFAILED\033[0m   %-8s\n"
	local success="\r%-"$((maximum - 20))"s   \033[92mWORKED\033[0m   %-8s\n"
	printf "$heading" "FUNCTION" "STATUS" "DURATION"
	for element in "${factors[@]}"; do
		local written=$(basename "$(echo "$element" | cut -d "'" -f 1)" | tr "[:lower:]" "[:upper:]")
		local started=$(date +"%s") && printf "$loading" "$written" "--:--:--"
		eval "$element" >/dev/null 2>&1 && local current="$success" || local current="$failure"
		local extinct=$(date +"%s") && elapsed=$((extinct - started))
		local elapsed=$(printf "%02d:%02d:%02d\n" $((elapsed / 3600)) $(((elapsed % 3600) / 60)) $((elapsed % 60)))
		printf "$current" "$written" "$elapsed"
	done

	# Revert timeouts
	sudo rm /private/etc/sudoers.d/disable_timeout 2>/dev/null

	# Revert sleeping
	sudo pmset -a disablesleep 0

	# Output new line
	printf "\n"

}

main
