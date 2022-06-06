#!/bin/zsh

#region COMMENTS

# shellcheck disable=SC1091,SC2059,SC2016,SC2129
# shellcheck shell=bash

#endregion

#region CHECKERS

assert_account() {

	account=$(security find-generic-password -w -s "account" -a "$USER" 2>/dev/null)

	sudo -k && echo "$account" | sudo -S -v &>/dev/null

}

assert_appleid() {

	appleid=$(security find-generic-password -w -s "appleid" -a "$USER" 2>/dev/null)
	secrets=$(security find-generic-password -w -s "secrets" -a "$USER" 2>/dev/null)

	[[ -z $appleid || -z $secrets ]] && return 1

	if [[ -x $(command -v brew) ]]; then

		export XCODES_USERNAME="$appleid"
		export XCODES_PASSWORD="$secrets"

		[[ -z $(command -v xcodes) ]] && brew install robotsandpencils/made/xcodes &>/dev/null

		expect <<-EOD

			log_user 0
			set timeout 8
			spawn xcodes install --latest

			expect {

				-re {.*(L|l)ocked.*} { exit 1 }
				-re {.*(P|p)assword.*} { exit 1 }
				timeout { exit 0 }

			}

		EOD

	fi

}

assert_secrets() {

	verbose=${1:-false}

	[[ $verbose = true ]] && printf "\n\033[93m%s\033[00m" "VERIFICATION IS IN PROGRESS, BE PATIENT..."

	if ! assert_account; then

		if [[ $verbose = true ]]; then

			heading="\r\033[91m%s\033[00m\n"
			message="\r\033[92m%s\033[00m\n"

			printf "$heading" "ACCOUNT PASSWORD NOT IN KEYCHAIN OR INCORRECT"
			printf "\n"
			printf "$message" "security delete-generic-password -s \"account\" &>/dev/null"
			printf "$message" "security add-generic-password -s \"account\" -a \"\$USER\" -w \"password\""
			printf "\n"

		fi

		exit 1

	fi

	if ! assert_appleid; then

		if [[ $verbose = true ]]; then

			heading="\r\033[91m%s\033[00m\n"
			message="\r\033[92m%s\033[00m\n"

			printf "$heading" "APPLE CREDENTIALS NOT IN KEYCHAIN OR INCORRECT"
			printf "\n"
			printf "$message" "security delete-generic-password -s \"appleid\" &>/dev/null"
			printf "$message" "security delete-generic-password -s \"secrets\" &>/dev/null"
			printf "\n"
			printf "$message" "security add-generic-password -s \"appleid\" -a \"\$USER\" -w \"username\""
			printf "$message" "security add-generic-password -s \"secrets\" -a \"\$USER\" -w \"password\""
			printf "\n"

		fi

		exit 1

	fi

}

#endregion

#region ENABLERS

enable_sleeping() {

	sudo rm "/private/etc/sudoers.d/disable_timeout" 2>/dev/null
	sudo pmset -a disablesleep 0

}

remove_sleeping() {

	message="Defaults timestamp_timeout=-1"
	private="/private/etc/sudoers.d/disable_timeout"
	echo "$message" | sudo tee "$private" >/dev/null

	sudo pmset -a disablesleep 1 && caffeinate -i -w $$ &

}

#endregion

#region INVOKERS

expand_archive() {

	archive=${1}
	deposit=${2:-.}
	subtree=${3:-0}

	if [[ -n $archive && ! -f $deposit && $subtree =~ ^[0-9]+$ ]]; then

		mkdir -p "$deposit"

		if [[ $archive = http* ]]; then

			curl -Ls "$archive" | tar -zxf - -C "$deposit" --strip-components=$((subtree))

		else

			tar -zxf "$archive" -C "$deposit" --strip-components=$((subtree))

		fi

		printf "%s" "$deposit"

	fi

}

invoke_alerter() {

	heading=${1}
	message=${2}
	timeout=${3:-10}

	[[ -z $heading ]] && heading=$(basename "$ZSH_ARGZERO" | cut -d . -f 1)

	osascript <<-EOD

		tell application "${TERM_PROGRAM//Apple_/}"

			display alert "$heading" message "$message" as informational giving up after $timeout

		end tell

	EOD

}

invoke_default() {

	browser=${1:-safari}

	brew install defaultbrowser

	factors=(brave chrome chromium firefox safari vivaldi)

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

invoke_docking() {

	factors=("${@}")

	defaults write com.apple.dock persistent-apps -array

	for element in "${factors[@]}"; do

		content="<dict><key>tile-data</key><dict><key>file-data</key><dict><key>_CFURLString</key><string>$element"
		content="$content</string><key>_CFURLStringType</key><integer>0</integer></dict></dict></dict>"
		defaults write com.apple.dock persistent-apps -array-add "$content"

	done

}

invoke_newicon() {

	address=${1}
	deposit=${2}

	brew install fileicon

	picture="$(mktemp -d)/$(basename "${address}")"
	curl -Ls "${address}" -A "mozilla/5.0" -o "${picture}"
	fileicon set "$deposit" "${picture}" &>/dev/null || sudo !!

}

invoke_pattern() {

	pattern=${1}
	expanse=${2:-0}

	printf "%s" "$(/bin/zsh -c "find $pattern -maxdepth $expanse" 2>/dev/null | sort -r | head -1)"

}

update_package() {

	package=${1}

	brew upgrade --cask --no-quarantine $package || brew install --cask --no-quarantine $package

}

#endregion

#region UPDATERS

update_angular() {

	update_nodejs || return 1

	export NG_CLI_ANALYTICS="ci" && npm install -g @angular/cli &>/dev/null

	update_chromium_extension "ienfalfjdbdpebioblfackkekamfmbnh" # Angular DevTools
	update_chromium_extension "lmhkpmbekcpmknklioeibfkpmmfibljd" # Redux DevTools

	update_vscode_extension "angular.ng-template"

	ng analytics off

}

update_appearance() {

	factors=(

		"/Applications/Chromium.app"
		# "/Applications/NetNewsWire.app"
		"/Applications/Transmission.app"
		"/Applications/JDownloader 2.0/JDownloader2.app"
		"/Applications/Insomnia.app"
		"/Applications/iTerm.app"
		"/Applications/Visual Studio Code.app"
		"/Applications/PyCharm.app"
		"/Applications/Android Studio.app"
		"/Applications/Figma.app"
		"/Applications/IINA.app"
		"/Applications/JoalDesktop.app"
		"/Applications/KeePassXC.app"
		"/System/Applications/Stickies.app"

	)

	invoke_docking "${factors[@]}"

	defaults write com.apple.dock autohide -bool true
	defaults write com.apple.dock autohide-delay -float 0
	defaults write com.apple.dock autohide-time-modifier -float 0.25
	defaults write com.apple.dock show-recents -bool false
	defaults write com.apple.Dock size-immutable -bool yes
	defaults write com.apple.dock tilesize -int 48

	killall Dock

	picture="$HOME/Pictures/Backgrounds/odoo-dark.png"
	mkdir -p "$(dirname "$picture")" && curl -L "https://i.imgur.com/U6a0cdR.png" -o "$picture"
	osascript -e "tell application \"System Events\" to tell every desktop to set picture to \"$picture\""

}

update_android_studio() {

	deposit="${1:-${HOME}/Projects}"
	wrapped="${2:-true}"

	checkup="/Applications/Android Studio.app"
	present=$(test -d "$checkup" && echo true || echo false)

	brew install fileicon grep xmlstarlet
	update_package android-studio

	if [[ $present = false ]]; then

		osascript <<-EOD

			set checkup to "/Applications/Android Studio.app"

				tell application checkup

					activate
					reopen

					tell application "System Events"

						tell process "Android Studio"

							-- Handle the long verification process.
							with timeout of 30 seconds
								repeat until (exists window 1)
									delay 1
								end repeat
							end timeout

							-- Handle the import settings window.
							delay 2
							key code 48
							delay 2
							key code 49
							delay 2

							-- Handle the long starting process.
							with timeout of 30 seconds
								repeat until (exists window 1)
									delay 1
								end repeat
							end timeout
							delay 6

							-- Handle the data sharing window.
							delay 2
							key code 48
							delay 2
							key code 49
							delay 2

							-- Handle the welcome window.
							delay 2
							key code 48
							delay 2
							key code 49
							delay 2

							-- Handle the install type window.
							key code 36
							delay 2

							-- Handle the select ui theme window.
							key code 36
							delay 2

							-- Handle the verify settings window.
							key code 48
							key code 48
							key code 48
							delay 2
							key code 36
							delay 6

							-- Handle the license agreements window.
							set button1 to (get button "Finish" of window 1)
							repeat until (get enabled of button1 is true)
								try
									click radio button "Accept" of window 1
								end try
								delay 2
								key code 125
								delay 2
							end repeat
							click button1
							delay 2

							-- Handle the installation completion window.
							set button1 to (get button "Finish" of window 1)
							repeat until (get enabled of button1 is true)
								delay 1
							end repeat
							click button1
							delay 8

						end tell  

					end tell

					delay 2
					quit
					delay 2

			end tell

		EOD

	fi

	cmdline="$HOME/Library/Android/sdk/cmdline-tools"

	if [[ ! -d $cmdline ]]; then

		website="https://developer.android.com/studio#command-tools"
		pattern="commandlinetools-win-\K(\d+)"
		version=$(curl -s "$website" | ggrep -oP "$pattern" | head -1)

		address="https://dl.google.com/android/repository"
		address="$address/commandlinetools-mac-${version}_latest.zip"

		expand_archive "$address" "$cmdline"
		chmod -R +x "$cmdline/cmdline-tools/bin"

		jdkhome="$checkup/Contents/jre/Contents/Home"
		manager="$cmdline/cmdline-tools/bin/sdkmanager"
		export JAVA_HOME="$jdkhome" && yes | $manager "cmdline-tools;latest"

		rm -rf "$cmdline/cmdline-tools"

	fi

	if ! grep -q "ANDROID_HOME" "$HOME/.zshrc" 2>/dev/null; then

		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"

		echo 'export ANDROID_HOME="$HOME/Library/Android/sdk"' >>"$HOME/.zshrc"
		echo 'export JAVA_HOME="/Applications/Android Studio.app/Contents/jre/Contents/Home"' >>"$HOME/.zshrc"
		echo 'export PATH="$PATH:$ANDROID_HOME/cmdline-tools/latest/bin"' >>"$HOME/.zshrc"
		echo 'export PATH="$PATH:$ANDROID_HOME/emulator"' >>"$HOME/.zshrc"
		echo 'export PATH="$PATH:$ANDROID_HOME/platform-tools"' >>"$HOME/.zshrc"

		source "$HOME/.zshrc"

	fi

	if [[ -n $wrapped ]]; then

		storage="$(invoke_pattern "$HOME/*ibrary/*pplication*upport/*oogle/*ndroid*tudio*")/options"
		configs="$storage/ide.general.xml" && mkdir -p "${storage}"

		if [[ -z $(xmlstarlet sel -t -v "//*[@name='Emulator']/@name" "$configs") ]]; then

			[[ -s "$configs" ]] || echo "<application />" >"$configs"

			xmlstarlet ed -L -s "/application" \
				-t "elem" -n "new-component" -v "" \
				-i "/application/new-component" \
				-t "attr" -n "name" -v "Emulator" \
				-r "/application/new-component" -v "component" "$configs"

		fi

		if [[ -z $(xmlstarlet sel -t -v "//*[@name='launchInToolWindow']/@name" "$configs") ]]; then

			xmlstarlet ed -L -s "/application/component[@name='Emulator']" \
				-t "elem" -n "new-option" -v "" \
				-i "/application/component[@name='Emulator']/new-option" \
				-t "attr" -n "name" -v "launchInToolWindow" \
				-i "/application/component[@name='Emulator']/new-option" \
				-t "attr" -n "value" -v "$wrapped" \
				-r "/application/component[@name='Emulator']/new-option" -v "option" "$configs"

		else

			xmlstarlet ed -L -u "//*[@name='launchInToolWindow']/@value" -v "$wrapped" "$configs"

		fi

	fi

	update_jetbrains_config "Android" "directory" "$deposit"
	update_jetbrains_config "Android" "font_size" "13"
	update_jetbrains_config "Android" "line_size" "1.5"
	update_jetbrains_config "Android" "line_wrap" "150"

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/d3e04839a5dd5c50e5d41dc6e7e50823_Android_Studio_Alt.icns"
	invoke_newicon "$address" "/Applications/Android Studio.app"

}

update_chromium() {

	deposit=${1:-${HOME}/Downloads/DDL}
	pattern=${2:-duckduckgo}
	tabpage=${3:-about:blank}

	checkup="/Applications/Chromium.app"
	present=$(test -d "$checkup" && echo true || echo false)
	present=false

	brew install jq
	update_package eloston-chromium

	sudo xattr -rd com.apple.quarantine /Applications/Chromium.app

	invoke_default "chromium"

	if [[ $present = false ]]; then

		# Ensure using the english language for future instructions.
		defaults write org.chromium.Chromium AppleLanguages "(en-US)"

		# Handle the notification center.
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

		# Update the downloads settings.
		mkdir -p "${deposit}" && osascript <<-EOD

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

		# Update the search engine settings.
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

		# Update the custom-ntp flags.
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

		# Update the extension-mime-request-handling flag.
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

		# Update the remove-tabsearch-button flag.
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

		# Update the show-avatar-button flag.
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

		# Remove the bookmarks bar.
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

		# Revert the default language.
		defaults delete org.chromium.Chromium AppleLanguages

		# Update the chromium web store extension.
		website="https://api.github.com/repos/NeverDecaf/chromium-web-store/releases"
		version=$(curl -s "$website" | jq -r ".[0].tag_name" | tr -d "v")
		address="https://github.com/NeverDecaf/chromium-web-store/releases/download/v${version}/Chromium.Web.Store.crx"
		update_chromium_extension "$address"

		# Update the ublock origin extension.
		update_chromium_extension "cjpalhdlnbpafiamejdnhcphjbkeiagm"

	fi

	# Update the bypass-paywalls-chrome extension.
	update_chromium_extension "https://github.com/iamadamdev/bypass-paywalls-chrome/archive/master.zip"

}

update_chromium_extension() {

	element=${1}

	[[ -d "/Applications/Chromium.app" ]] || return 1

	if [[ ${element:0:4} = "http" ]]; then

		address="$element"
		package=$(mktemp -d)/$(basename "$address")

	else

		version=$(defaults read "/Applications/Chromium.app/Contents/Info" CFBundleShortVersionString)
		address="https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3"
		address="${address}&prodversion=${version}&x=id%3D${element}%26installsource%3Dondemand%26uc"
		package=$(mktemp -d)/${element}.crx

	fi

	curl -Ls "$address" -o "$package" || return 1
	defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

	if [[ $package = *.zip ]]; then

		storage="/Applications/Chromium.app/Unpacked/$(echo "$element" | cut -d / -f5)"
		present=$(test -d "$storage" && echo true || echo false)
		expand_archive "$package" "$storage" 1

		if [[ $present = false ]]; then

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

					key code 48
					delay 2
					key code 49

				end tell

				delay 6
				quit
				delay 2

			end tell

		EOD

	fi

}

update_docker() {

	update_package docker

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/a74bb7c042e74f6e20dc3a50c631c41f_Docker.icns"
	invoke_newicon "$address" "/Applications/Docker.app"
	invoke_newicon "$address" "/Applications/Docker.app/Contents/MacOS/Docker Desktop.app"

}

update_dotnet() {

	update_package dotnet-sdk

	if ! grep -q "DOTNET_CLI_TELEMETRY_OPTOUT" "$HOME/.zshrc" 2>/dev/null; then

		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"

		echo 'export DOTNET_CLI_TELEMETRY_OPTOUT=1' >>"$HOME/.zshrc"
		echo 'export DOTNET_NOLOGO=1' >>"$HOME/.zshrc"
		echo 'export PATH="$PATH:/Users/$USER/.dotnet/tools"' >>"$HOME/.zshrc"

		source "$HOME/.zshrc"

	fi

	sudo dotnet workload install maui

}

update_figma() {

	update_package figma
	update_package figmadaemon

}

update_flutter() {

	brew install --cask --no-quarantine flutter

	altered="$(grep -q "CHROME_EXECUTABLE" "$HOME/.zshrc" >/dev/null 2>&1 && echo true || echo false)"
	present="$(test -d "/Applications/Chromium.app" && echo true || echo false)"

	if [[ $altered = false && $present = true ]]; then

		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"

		echo 'export CHROME_EXECUTABLE="/Applications/Chromium.app/Contents/MacOS/Chromium"' >>"${HOME}/.zshrc"

		source "$HOME/.zshrc"

	fi

	update_jetbrains_plugin "AndroidStudio" "6351"  # Dart
	update_jetbrains_plugin "AndroidStudio" "9212"  # Flutter
	update_jetbrains_plugin "AndroidStudio" "13666" # Flutter Intl

	update_vscode_extension "dart-code.flutter"
	update_vscode_extension "localizely.flutter-intl"

	flutter config --no-analytics
	yes | flutter doctor --android-licenses
	flutter upgrade

}

update_git() {

	default=${1:-master}

	brew install gh git

	git config --global credential.helper osxkeychain
	git config --global init.defaultBranch "$default"
	git config --global user.email "sharpordie@example.org"
	git config --global user.name "sharpordie"

}

update_homebrew() {

	if ! grep -q "HOMEBREW_NO_ANALYTICS" "$HOME/.zshrc" 2>/dev/null; then

		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"

		echo "export HOMEBREW_NO_ANALYTICS=1" >>"$HOME/.zshrc"
		echo "export HOMEBREW_NO_AUTO_UPDATE=1" >>"$HOME/.zshrc"
		echo "export HOMEBREW_NO_EMOJI=1" >>"$HOME/.zshrc"
		echo "export HOMEBREW_NO_INSTALL_CLEANUP=1" >>"$HOME/.zshrc"
		echo "export HOMEBREW_UPDATE_REPORT_ONLY_INSTALLED=1" >>"$HOME/.zshrc"

		source "$HOME/.zshrc"

	fi

	if [[ -z $(command -v brew) ]]; then

		command=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)

		CI=1 /bin/bash -c "$command" &>/dev/null

	fi

	brew update && brew upgrade && brew cleanup

}

update_iina() {

	present=$(test -d "/Applications/IINA.app" && echo true || echo false)

	brew install grep yt-dlp

	address="https://nightly.iina.io/"
	pattern="href=\"\K(static/IINA-.*.app.tar.xz)(?=\")"
	address="$address$(curl -Ls "$address" | ggrep -oP "$pattern" | head -1)"
	archive=$(mktemp -d)/$(basename "$address") && curl -Ls "$address" -o "$archive"
	expand_archive "$archive" "/Applications" && mv /Applications/IINA-*.app /Applications/IINA.app

	if [[ $present = false ]]; then

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

	ln -s /usr/local/bin/yt-dlp /usr/local/bin/youtube-dl

	defaults write com.colliderli.iina SUEnableAutomaticChecks -integer 0
	defaults write com.colliderli.iina ytdlSearchPath "/usr/local/bin"

	website="https://api.github.com/repos/jdek/openwith/releases"
	version=$(curl -s "$website" -A "mozilla/5.0" | jq -r ".[0].tag_name" | tr -d "v")
	address="https://github.com/jdek/openwith/releases/download/v$version/openwith-v$version.tar.xz"
	archive=$(mktemp -d)/$(basename "$address") && curl -Ls "$address" -A "mozilla/5.0" -o "$archive"
	expand_archive "$archive" "$HOME"
	"$HOME/openwith" com.colliderli.iina mkv mov mp4 avi && rm "$HOME/openwith"

}

update_insomnia() {

	present=$(test -d "/Applications/Insomnia.app" && echo true || echo false)

	update_package insomnia

	if [[ $present = false ]]; then

		osascript <<-EOD

			set checkup to "/Applications/Insomnia.app"

			tell application checkup

				activate
				reopen

				tell application "System Events"

					with timeout of 10 seconds
						repeat until (exists window 1 of application process "Insomnia")
							delay 1
						end repeat
					end timeout

					delay 6
					repeat 8 times
						key code 48
					end repeat
					delay 2
					key code 36
					delay 2
					repeat 4 times
						key code 48
					end repeat
					delay 2
					key code 36

				end tell

				delay 4
				quit
				delay 4

			end tell

		EOD

	fi

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/7130391d4e290b132e5fbde61f209f0b_Insomnia.icns"
	invoke_newicon "$address" "/Applications/Insomnia.app"

}

update_iterm() {

	present=$(test -d "/Applications/iTerm.app" && echo true || echo false)

	update_package iterm2

	defaults write com.googlecode.iterm2 DisableWindowSizeSnap -integer 1
	defaults write com.googlecode.iterm2 PromptOnQuit -bool false

	if [[ $present = false ]]; then

		osascript <<-EOD

			set checkup to "/Applications/iTerm.app"

			tell application checkup

				activate
				reopen

				tell application "System Events"

					with timeout of 10 seconds
						repeat until (exists window 1 of application process "iTerm2")
							delay 1
						end repeat
					end timeout

					delay 2
					key code 36
					delay 2

					key code 42 using {control down, shift down, command down}

				end tell

				delay 2
				quit
				delay 2

			end tell

		EOD

	fi

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/d2e2d6e9824e19d279df6e7dd18ed24f_iterm2.icns"
	invoke_newicon "$address" "/Applications/iTerm.app"

}

update_jdownloader() {

	deposit=${1:-$HOME/Downloads/JD2}

	brew install fileicon jq sponge
	update_package jdownloader

	mkdir -p "$deposit"

	config1="/Applications/JDownloader 2.0/cfg/org.jdownloader.settings.GeneralSettings.json"
	config2="/Applications/JDownloader 2.0/cfg/org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
	config3="/Applications/JDownloader 2.0/cfg/org.jdownloader.gui.jdtrayicon.TrayExtension.json"

	read -r -d '' content <<-EOD

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

			delay 4
			quit
			delay 4

		end tell

	EOD

	for i in {0..2}; do

		osascript -e "$content"

		jq ".defaultdownloadfolder =  \"$deposit\"" "$config1" | sponge "$config1"
		jq '."bannerenabled" = false' "$config2" | sponge "$config2"
		jq '."donatebuttonstate" = "AUTO_HIDDEN"' "$config2" | sponge "$config2"
		jq '."myjdownloaderviewvisible" = false' "$config2" | sponge "$config2"
		jq '."specialdealoboomdialogvisibleonstartup" = false' "$config2" | sponge "$config2"
		jq '."specialdealsenabled" = false' "$config2" | sponge "$config2"
		jq '."speedmetervisible" = false' "$config2" | sponge "$config2"
		jq '."enabled" = false' "$config3" | sponge "$config3"

	done

	update_chromium_extension "fbcohnmimjicjdomonkcbcpbpnhggkip"

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/f9f34425fea22ece047c7f6ede568ace_jDownloader.icns"
	picture="$(mktemp -d)/$(basename "$address")"
	curl -Ls "$address" -o "$picture"
	fileicon set "/Applications/JDownloader2.app" "$picture"
	fileicon set "/Applications/JDownloader 2.0/JDownloader2.app" "$picture"
	fileicon set "/Applications/JDownloader 2.0/JDownloader Uninstaller.app" "$picture"
	cp "$picture" "/Applications/JDownloader 2.0/JDownloader2.app/Contents/Resources/app.icns"
	sips -Z 128 -s format png "$picture" --out "/Applications/JDownloader 2.0/themes/standard/org/jdownloader/images/logo/jd_logo_128_128.png"

}

update_jetbrains_config() {

	pattern=${1}
	element=${2}
	content=${3}

	brew install curl xmlstarlet

	deposit=$(invoke_pattern "$HOME/*ibrary/*pplication*upport/*/*$pattern*")
	factors=(directory font_name font_size line_size line_wrap)

	if [[ -z "$content" || -z "$deposit" || ! "${factors[*]}" =~ $element ]]; then

		return 1

	elif [[ $element = "directory" ]]; then

		storage="$deposit/options" && mkdir -p "$content" "$storage"
		configs="$storage/ide.general.xml"

		[[ -s "$configs" ]] || echo "<application />" >"$configs"

		if [[ -z "$(xmlstarlet sel -t -v "//*[@name='GeneralSettings']/@name" "$configs")" ]]; then

			xmlstarlet ed -L -s "/application" \
				-t "elem" -n "new-component" -v "" \
				-i "/application/new-component" \
				-t "attr" -n "name" -v "GeneralSettings" \
				-r "/application/new-component" -v "component" "$configs"

		fi

		if [[ -z "$(xmlstarlet sel -t -v "//*[@name='defaultProjectDirectory']/@name" "$configs")" ]]; then

			xmlstarlet ed -L -s "/application/component[@name='GeneralSettings']" \
				-t "elem" -n "new-option" -v "" \
				-i "/application/component[@name='GeneralSettings']/new-option" \
				-t "attr" -n "name" -v "defaultProjectDirectory" \
				-i "/application/component[@name='GeneralSettings']/new-option" \
				-t "attr" -n "value" -v "$content" \
				-r "/application/component[@name='GeneralSettings']/new-option" -v "option" "$configs"

		else

			xmlstarlet ed -L -u "//*[@name='defaultProjectDirectory']/@value" -v "$content" "$configs"

		fi

	elif [[ $element = "font_name" ]]; then

		# TODO
		echo "font_name"

	elif [[ $element = "font_size" ]]; then

		autoload is-at-least

		checkup=$(invoke_pattern "/*pplications/*$pattern*.app")
		version=$(defaults read "$checkup/Contents/Info.plist" CFBundleShortVersionString)
		storage="$deposit/options" && mkdir -p "$storage"
		configs=$(is-at-least "2021.2" "$version" && echo "$storage/editor-font.xml" || echo "$storage/editor.xml")

		[[ -s "$configs" ]] || echo "<application />" >"$configs"

		if [[ -z "$(xmlstarlet sel -t -v "//*[@name='DefaultFont']/@name" "$configs")" ]]; then

			xmlstarlet ed -L -s "/application" \
				-t "elem" -n "new-component" -v "" \
				-i "/application/new-component" \
				-t "attr" -n "name" -v "DefaultFont" \
				-r "/application/new-component" -v "component" "$configs"

		fi

		if [[ -z "$(xmlstarlet sel -t -v "//*[@name='FONT_SIZE']/@name" "$configs")" ]]; then

			xmlstarlet ed -L -s "/application/component[@name='DefaultFont']" \
				-t "elem" -n "new-option" -v "" \
				-i "/application/component[@name='DefaultFont']/new-option" \
				-t "attr" -n "name" -v "FONT_SIZE" \
				-i "/application/component[@name='DefaultFont']/new-option" \
				-t "attr" -n "value" -v "$content" \
				-r "/application/component[@name='DefaultFont']/new-option" -v "option" "$configs"

		else

			xmlstarlet ed -L -u "//*[@name='FONT_SIZE']/@value" -v "$content" "$configs"

		fi

	elif [[ $element = "line_size" ]]; then

		autoload is-at-least

		checkup=$(invoke_pattern "/*pplications/*$pattern*.app")
		version=$(defaults read "$checkup/Contents/Info.plist" CFBundleShortVersionString)
		storage="$deposit/options" && mkdir -p "$storage"
		configs=$(is-at-least "2021.2" "$version" && echo "$storage/editor-fonts.xml" || echo "$storage/editor.xml")

		[[ -s "$configs" ]] || echo "<application />" >"$configs"

		if [[ -z "$(xmlstarlet sel -t -v "//*[@name='DefaultFont']/@name" "$configs")" ]]; then

			xmlstarlet ed -L -s "/application" \
				-t "elem" -n "new-component" -v "" \
				-i "/application/new-component" \
				-t "attr" -n "name" -v "DefaultFont" \
				-r "/application/new-component" -v "component" "$configs"

		fi

		if [[ -z "$(xmlstarlet sel -t -v "//*[@name='LINE_SPACING']/@name" "$configs")" ]]; then

			xmlstarlet ed -L -s "/application/component[@name='DefaultFont']" \
				-t "elem" -n "new-option" -v "" \
				-i "/application/component[@name='DefaultFont']/new-option" \
				-t "attr" -n "name" -v "LINE_SPACING" \
				-i "/application/component[@name='DefaultFont']/new-option" \
				-t "attr" -n "value" -v "$content" \
				-r "/application/component[@name='DefaultFont']/new-option" -v "option" "$configs"

		else

			xmlstarlet ed -L -u "//*[@name='LINE_SPACING']/@value" -v "$content" "$configs"

		fi

	elif [[ $element = "line_wrap" ]]; then

		storage="$deposit/codestyles" && mkdir -p "$storage"
		configs="$storage/Default.xml"

		[[ -s "$configs" ]] || echo "<code_scheme name='Default'/>" >"$configs"

		if [ -z "$(xmlstarlet sel -t -v "//*[@name='RIGHT_MARGIN']/@name" "$configs")" ]; then

			xmlstarlet ed -L -s "/code_scheme" \
				-t "elem" -n "new-option" -v "" \
				-i "/code_scheme/new-option" \
				-t "attr" -n "name" -v "RIGHT_MARGIN" \
				-i "/code_scheme/new-option" \
				-t "attr" -n "value" -v "$content" \
				-r "/code_scheme/new-option" -v "option" "$configs"

		else

			xmlstarlet ed -L -u "//*[@name='RIGHT_MARGIN']/@value" -v "$content" "$configs"

		fi

	fi

}

update_jetbrains_plugin() {

	pattern="${1}"
	element="${2}"

	deposit=$(invoke_pattern "$HOME/*ibrary/*pplication*upport/*/*$pattern*")

	if [[ -d $deposit ]]; then

		brew install grep jq

		checkup=$(invoke_pattern "/*pplications/*${pattern:0:5}*/*ontents/*nfo.plist")
		version=$(defaults read "$checkup" CFBundleVersion | ggrep -oP "[\d.]+" | cut -d . -f -3)

		autoload is-at-least

		for i in {0..19}; do

			address="https://plugins.jetbrains.com/api/plugins/$element/updates"
			maximum=$(curl -s "$address" | jq ".[$i].until" | tr -d '"' | sed "s/\.\*/\.9999/")
			minimum=$(curl -s "$address" | jq ".[$i].since" | tr -d '"' | sed "s/\.\*/\.9999/")

			if is-at-least "${minimum:-0000}" "$version" && is-at-least "$version" "${maximum:-9999}"; then

				address=$(curl -s "$address" | jq ".[$i].file" | tr -d '"')
				address="https://plugins.jetbrains.com/files/$address"
				plugins="$deposit/plugins" && mkdir -p "$plugins"

				[[ "$address" == *.zip ]] && expand_archive "$address" "$plugins"
				[[ "$address" == *.jar ]] && curl -Ls "$address" -o "$plugins"

				break

			fi

			sleep 1

		done

	fi

}

update_joal_desktop() {

	brew install jq

	address="https://api.github.com/repos/anthonyraymond/joal-desktop/releases"
	version=$(curl -Ls "$address" | jq -r ".[0].tag_name" | tr -d "v")
	checkup=$(invoke_pattern "/*pplications/*oal*esktop*/*ontents/*nfo.plist")
	current=$(defaults read "$checkup" CFBundleShortVersionString 2>/dev/null | ggrep -oP "[\d.]+" || echo "0.0.0.0")

	autoload is-at-least

	if ! is-at-least "$version" "$current"; then

		address="https://github.com/anthonyraymond/joal-desktop/releases"
		address="$address/download/v${version}/JoalDesktop-${version}-mac-x64.dmg"
		package=$(mktemp -d)/$(basename "$address") && curl -Ls "$address" -o "$package"

		hdiutil attach "$package" -noautoopen -nobrowse
		cp -fr /Volumes/Joal*/Joal*.app /Applications
		hdiutil detach /Volumes/Joal*
		sudo xattr -rd com.apple.quarantine /Applications/Joal*.app

	fi

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/9620a6c1e563bb87fd8e68d6aeeee8ad_undefined.icns"
	invoke_newicon "$address" "/Applications/JoalDesktop.app"

}

update_keepassxc() {

	update_package keepassxc

}

update_mpv() {

	brew install grep yt-dlp

	address="https://laboratory.stolendata.net/~djinn/mpv_osx/"
	pattern="mpv-\K([\d.]+)(?=.tar.gz\")"
	version=$(curl -Ls "$address" | ggrep -oP "$pattern" | head -1)
	checkup=$(invoke_pattern "/*pplications/*pv.app/*ontents/*nfo.plist")
	current=$(defaults read "$checkup" CFBundleShortVersionString 2>/dev/null | ggrep -oP "[\d.]+" || echo "0.0.0.0")

	autoload is-at-least

	if ! is-at-least "$version" "$current"; then

		address="https://laboratory.stolendata.net/~djinn/mpv_osx/mpv-latest.tar.gz"
		archive=$(mktemp -d)/$(basename "$address") && curl -Ls "$address" -o "$archive"
		expand_archive "$archive" "/Applications" && rm -rf "/Applications/documentation"
		ln -s "/Applications/mpv.app/Contents/MacOS/mpv" "/usr/local/bin/mpv"

	fi

	configs="$HOME/.config/mpv/mpv.conf"
	mkdir -p "$(dirname "$configs")" && cat /dev/null >"${configs}"
	echo "profile=gpu-hq" >>"${configs}"
	echo "hwdec=auto" >>"${configs}"
	echo "keep-open=yes" >>"${configs}"
	echo "save-position-on-quit=yes" >>"${configs}"
	echo "interpolation=yes" >>"${configs}"
	echo "blend-subtitles=yes" >>"${configs}"
	echo "tscale=oversample" >>"${configs}"
	echo "video-sync=display-resample" >>"${configs}"
	echo 'ytdl-format="bestvideo[height<=?2160][vcodec!=vp9]+bestaudio/best"' >>"${configs}"
	echo "[protocol.http]" >>"${configs}"
	echo "force-window=immediate" >>"${configs}"
	echo "[protocol.https]" >>"${configs}"
	echo "profile=protocol.http" >>"${configs}"
	echo "[protocol.ytdl]" >>"${configs}"
	echo "profile=protocol.http" >>"${configs}"

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/f5885423e105d39295af90e5bfa8d36a_MPV.icns"
	invoke_newicon "$address" "/Applications/mpv.app"

	website="https://api.github.com/repos/jdek/openwith/releases"
	version=$(curl -s "$website" -A "mozilla/5.0" | jq -r ".[0].tag_name" | tr -d "v")
	address="https://github.com/jdek/openwith/releases/download/v$version/openwith-v$version.tar.xz"
	archive=$(mktemp -d)/$(basename "$address") && curl -Ls "$address" -A "mozilla/5.0" -o "$archive"
	expand_archive "$archive" "$HOME"
	"$HOME/openwith" io.mpv mkv mov mp4 avi && rm "$HOME/openwith"

}

update_mqtt_explorer() {

	update_package mqtt-explorer

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/9ea65d2400ef27120e7dd4dc00e85881_MQTT_Explorer.icns"
	invoke_newicon "$address" "/Applications/MQTT Explorer.app"

}

update_netnewswire() {

	update_package netnewswire

}

update_nightshift() {

	percent=${1:-70}
	forever=${2:-true}

	brew install smudge/smudge/nightlight

	[[ $forever = true ]] && nightlight schedule 3:00 2:59

	nightlight temp "$percent" && nightlight on

}

update_nodejs() {

	brew install grep

	address="https://nodejs.org/en/download/"
	pattern="LTS Version: <strong>\K([\d]+)"
	version=$(curl -s "$address" | ggrep -oP "$pattern" | head -1)
	brew install node@"$version"

	if ! grep -q "/usr/local/opt/node" "$HOME/.zshrc" 2>/dev/null; then

		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"

		echo "export PATH=\"\$PATH:/usr/local/opt/node@$version/bin\"" >>"$HOME/.zshrc"

	else

		sed -i '' -e "s#/usr/local/opt/node.*/bin#/usr/local/opt/node@$version/bin#" "$HOME/.zshrc"

	fi

	source "$HOME/.zshrc"

}

update_odoo() {

	update_jetbrains_plugin "PyCharm" "10037" # CSV
	update_jetbrains_plugin "PyCharm" "12478" # XPathView +​ XSLT
	update_jetbrains_plugin "PyCharm" "13499" # Odoo

	update_vscode_extension "jigar-patel.odoosnippets"

}

update_permissions() {

	assert_account || return 1

	account=$(security find-generic-password -w -s "account" -a "$USER" 2>/dev/null)
	program=$(echo "$TERM_PROGRAM" | sed -e "s/.app//" | sed -e "s/Apple_//")

	allowed() { osascript -e 'tell application "System Events" to log ""' &>/dev/null; }
	capable() { osascript -e 'tell application "System Events" to key code 60' &>/dev/null; }
	granted() { ls "$HOME"/Library/Messages &>/dev/null; }

	while ! allowed; do

		invoke_alerter "" "Press the OK button" &>/dev/null
		tccutil reset AppleEvents &>/dev/null

	done

	while ! capable; do

		osascript -e 'tell application "universalAccessAuthWarn" to quit' &>/dev/null

		message="Press the lock icon, enter your password, ensure $program is present, checked it and close the window"
		invoke_alerter "" "$message" &>/dev/null

		open -W "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" &>/dev/null

	done

	if ! granted; then

		message="The script is going to add $program in full disk access automatically, don't touch anything."
		invoke_alerter "" "$message" &>/dev/null

		osascript <<-EOD

			-- Ensure the system preferences application is not running.
			if running of application "System Preferences" then

				tell application "System Preferences" to quit
				delay 2

			end if

			-- Reveal the security pane of the system preferences application.
			tell application "System Preferences"

				activate
				reveal anchor "Privacy" of pane "com.apple.preference.security"
				delay 4

			end tell

			-- Handle the full disk access permission.
			tell application "System Events" to tell application process "System Preferences"

				-- Press the lock icon.
				click button 1 of window 1
				delay 4

				-- Enter the account password.
				set value of text field 2 of sheet 1 of window 1 to "$account"
				delay 2
				click button 2 of sheet 1 of window 1

				-- Press the full disk access row.
				delay 2
				select row 11 of table 1 of scroll area 1 of tab group 1 of window 1

				-- Fecth the table row element by its name.
				set fullAccessTable to table 1 of scroll area 1 of group 1 of tab group 1 of window 1
				set terminalItemRow to (row 1 where name of UI element 1 is "$program" or name of UI element 1 is "${program}.app") of fullAccessTable

				-- Check the checkbox only if it is not already checked.
				set terminalCheckbox to checkbox 1 of UI element 1 of terminalItemRow
				set checkboxStatus to value of terminalCheckbox as boolean

				if checkboxStatus is false then

					click terminalCheckbox
					delay 2
					click button 1 of sheet 1 of window 1

				end if

			end tell

			-- Ensure the system preferences application is not running.
			if running of application "System Preferences" then

				delay 2
				tell application "System Preferences" to quit

			end if

		EOD

	fi

}

update_phpstorm() {

	deposit="${1:-$HOME/Projects}"

	present=$(test -d "/Applications/PhpStorm.app" && echo true || echo false)

	brew install fileicon xmlstarlet
	update_package phpstorm

	update_jetbrains_config "PhpStorm" "directory" "$deposit"
	update_jetbrains_config "PhpStorm" "font_size" "13"
	update_jetbrains_config "PhpStorm" "line_size" "1.5"
	update_jetbrains_config "PhpStorm" "line_wrap" "160"

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/47ac6ca6873ff8e9e018ba781d9e1f12_PhpStorm.icns"
	invoke_newicon "$address" "/Applications/PhpStorm.app"

}

update_powershell() {

	update_package powershell

	update_vscode_extension "ms-vscode.powershell-preview"

}

update_pycharm() {

	deposit="${1:-$HOME/Projects}"

	present=$(test -d "/Applications/PyCharm.app" && echo true || echo false)

	brew install fileicon xmlstarlet
	update_package pycharm

	if [[ $present = false ]]; then

		osascript <<-EOD

			set checkup to "/Applications/PyCharm.app"

			tell application checkup

				activate
				reopen

				tell application "System Events"

					tell process "PyCharm"

						-- Handle the long verification process.
						with timeout of 30 seconds
							repeat until (exists window 1)
								delay 1
							end repeat
						end timeout

						delay 2
						key code 48
						delay 2
						key code 49
						delay 2
						key code 49
						delay 2
						key code 48
						delay 2
						key code 49
						delay 12

						repeat with button1 in (get buttons of window 1) as list
							if get description of button1 as string is "Exit" then
								click button1
								exit repeat
							end if
						end repeat

					end tell

				end tell

				delay 2

			end tell

		EOD

	fi

	update_jetbrains_config "PyCharm" "directory" "$deposit"
	update_jetbrains_config "PyCharm" "font_size" "13"
	update_jetbrains_config "PyCharm" "line_size" "1.5"
	update_jetbrains_config "PyCharm" "line_wrap" "140"

	# https://macosicons.com/#/u/twilightwalker
	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/1745c1fdacf6f97df6807b0306ae0921_PyCharm.icns"
	invoke_newicon "$address" "/Applications/PyCharm.app"

}

update_python() {

	brew install python@3.10 poetry

	if ! grep -q "PYTHONDONTWRITEBYTECODE" "$HOME/.zshrc" 2>/dev/null; then

		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"

		echo "export PYTHONDONTWRITEBYTECODE=1" >>"$HOME/.zshrc"

		source "$HOME/.zshrc"

	fi

	update_vscode_extension "ms-python.python"
	update_vscode_extension "njpwerner.autodocstring"
	update_vscode_extension "visualstudioexptteam.vscodeintellicode"

	poetry config virtualenvs.in-project true

}

update_rider() {

	deposit="${1:-$HOME/Projects}"

	present=$(test -d "/Applications/Rider.app" && echo true || echo false)

	brew install fileicon xmlstarlet
	update_package rider

	update_jetbrains_config "Rider" "directory" "$deposit"
	update_jetbrains_config "Rider" "font_size" "13"
	update_jetbrains_config "Rider" "line_size" "1.5"
	update_jetbrains_config "Rider" "line_wrap" "160"

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/0b1e6756e49f76cbf0d0da4ea02ccec7_Rider.icns"
	invoke_newicon "$address" "/Applications/Rider.app"

}

update_system() {

	country=${1:-Europe/Brussels}
	machine=${2:-macintosh}

	# Enable the full keyboard access for all controls.
	defaults write NSGlobalDomain AppleKeyboardUIMode -int 3

	# Enable the hidpi display modes.
	sudo defaults write /Library/Preferences/com.apple.windowserver DisplayResolutionEnabled -bool true

	# Enable the screen sharing feature.
	sudo defaults write /var/db/launchd.db/com.apple.launchd/overrides.plist com.apple.screensharing -dict Disabled -bool false
	sudo launchctl load -w /System/Library/LaunchDaemons/com.apple.screensharing.plist
	tccutil reset ScreenCapture

	# Enable the subpixel font rendering on non-apple monitors.
	# defaults write NSGlobalDomain AppleFontSmoothing -int 2

	# Enable the tap to click feature.
	defaults -currentHost write NSGlobalDomain com.apple.mouse.tapBehavior -int 1
	defaults write com.apple.driver.AppleBluetoothMultitouch.trackpad Clicking -bool true
	defaults write NSGlobalDomain com.apple.mouse.tapBehavior -int 1

	# TODO: Ensure all pending software updates are installed.
	# sudo softwareupdate -ia

	# Remove the startup chime.
	sudo nvram StartupMute=%01

	# Update the computer name.
	sudo scutil --set ComputerName "$machine"
	sudo scutil --set HostName "$machine"
	sudo scutil --set LocalHostName "$machine"
	sudo defaults write /Library/Preferences/SystemConfiguration/com.apple.smb.server NetBIOSName -string "$machine"

	# Update the timezone.
	sudo systemsetup -settimezone "$country"

	# Update other miscellaneous settings.
	defaults write com.apple.desktopservices DSDontWriteNetworkStores -bool true
	defaults write com.apple.desktopservices DSDontWriteUSBStores -bool true
	defaults write com.apple.finder FXDefaultSearchScope -string "SCcf"
	defaults write com.apple.finder FXEnableExtensionChangeWarning -bool false
	defaults write com.apple.finder ShowPathbar -bool true
	defaults write com.apple.LaunchServices "LSQuarantine" -bool false
	defaults write com.apple.Preview NSRecentDocumentsLimit 0
	defaults write com.apple.Preview NSRecentDocumentsLimit 0
	defaults write com.apple.TimeMachine DoNotOfferNewDisksForBackup -bool true
	defaults write NSGlobalDomain NSAutomaticDashSubstitutionEnabled -bool false
	defaults write NSGlobalDomain NSAutomaticQuoteSubstitutionEnabled -bool false

	killall Finder

}

update_the_unarchiver() {

	present=$(test -d "/Applications/The Unarchiver.app" && echo true || echo false)

	update_package the-unarchiver

	if [[ $present = false ]]; then

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

	defaults write com.macpaw.site.theunarchiver extractionDestination -integer 3
	defaults write com.macpaw.site.theunarchiver isFreshInstall -integer 1
	defaults write com.macpaw.site.theunarchiver userAgreedToNewTOSAndPrivacy -integer 1

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/b2511dfa51412811b36f55e108503749_1618249837652.icns"
	invoke_newicon "$address" "/Applications/The Unarchiver.app"

}

update_transmission() {

	deposit=${1:-$HOME/Downloads/P2P}
	seeding=${2:-0.1}

	update_package transmission

	mkdir -p "$deposit/Incompleted"

	defaults write org.m0k.transmission DownloadFolder -string "$deposit"
	defaults write org.m0k.transmission IncompleteDownloadFolder -string "$deposit/Incompleted"
	defaults write org.m0k.transmission RatioCheck -bool true
	defaults write org.m0k.transmission RatioLimit -int "$seeding"
	defaults write org.m0k.transmission UseIncompleteDownloadFolder -bool true
	defaults write org.m0k.transmission WarningDonate -bool false
	defaults write org.m0k.transmission WarningLegal -bool false

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/be45498b6e2bc2cf97ea6467e9799243_Transmission_Alt_2.icns"
	invoke_newicon "$address" "/Applications/Transmission.app"

}

update_vemto() {

	brew install jq

	address="https://api.github.com/repos/TiagoSilvaPereira/vemto-releases/releases"
	version=$(curl -Ls "$address" | jq -r ".[0].tag_name" | tr -d "v")
	checkup=$(invoke_pattern "/*pplications/*emto*/*ontents/*nfo.plist")
	current=$(defaults read "$checkup" CFBundleShortVersionString 2>/dev/null | ggrep -oP "[\d.]+" || echo "0.0.0.0")

	autoload is-at-least

	if ! is-at-least "$version" "$current"; then

		rm -rf /Applications/vemto*.app

		address="https://github.com/TiagoSilvaPereira/vemto-releases/releases"
		address="$address/download/v${version}/vemto-${version}.dmg"
		package=$(mktemp -d)/$(basename "$address") && curl -Ls "$address" -o "$package"

		hdiutil attach "$package" -noautoopen -nobrowse
		cp -fr /Volumes/vemto*/vemto*.app /Applications
		hdiutil detach /Volumes/vemto*
		sudo xattr -rd com.apple.quarantine /Applications/vemto*.app

	fi

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="$address/f651155c09106bf1d5f53db760342fd1_SmartGit.icns"
	invoke_newicon "$address" "/Applications/vemto.app"

}

update_vscode() {

	brew install homebrew/cask-fonts/font-cascadia-code jq sponge
	update_package visual-studio-code

	update_vscode_extension "foxundermoon.shell-format"
	update_vscode_extension "github.github-vscode-theme"

	configs="$HOME/Library/Application Support/Code/User/settings.json"
	[[ -s "$configs" ]] || echo "{}" >"$configs"
	jq '."editor.fontFamily" = "Cascadia Code, monospace"' "$configs" | sponge "$configs"
	jq '."editor.fontSize" = 13' "$configs" | sponge "$configs"
	jq '."editor.lineHeight" = 35' "$configs" | sponge "$configs"
	jq '."security.workspace.trust.enabled" = false' "$configs" | sponge "$configs"
	jq '."telemetry.telemetryLevel" = "crash"' "$configs" | sponge "$configs"
	jq '."update.mode" = "none"' "$configs" | sponge "$configs"
	jq '."workbench.colorTheme" = "GitHub Dark"' "$configs" | sponge "$configs"

}

update_vscode_extension() {

	element=${1}

	[[ -x $(command -v code) ]] || return 1

	code --install-extension "$element" &>/dev/null

}

update_xcode() {

	ensure_apple_id || return 1

	brew install cocoapods fileicon robotsandpencils/made/xcodes

	xcodes install --latest
	mv /Applications/Xcode*.app /Applications/Xcode.app
	sudo xcode-select --switch /Applications/Xcode.app/Contents/Developer
	sudo xcodebuild -runFirstLaunch
	sudo xcodebuild -license accept

	address="https://media.macosicons.com/parse/files/macOSicons"
	address="${address}/d5d49e016cfc40133d4ceda3431442dc_XCode_Alt.icns"
	invoke_newicon "${address}" "/Applications/Xcode.app"

}

#endregion

main() {

	sudo -v && clear

	read -r -d "" welcome <<-EOD

		███╗░░░███╗░█████╗░░█████╗░██╗░░██╗░█████╗░░██████╗░███████╗███╗░░██╗
		████╗░████║██╔══██╗██╔══██╗██║░░██║██╔══██╗██╔════╝░██╔════╝████╗░██║
		██╔████╔██║███████║██║░░╚═╝███████║██║░░██║██║░░██╗░█████╗░░██╔██╗██║
		██║╚██╔╝██║██╔══██║██║░░██╗██╔══██║██║░░██║██║░░╚██╗██╔══╝░░██║╚████║
		██║░╚═╝░██║██║░░██║╚█████╔╝██║░░██║╚█████╔╝╚██████╔╝███████╗██║░╚███║
		╚═╝░░░░░╚═╝╚═╝░░╚═╝░╚════╝░╚═╝░░╚═╝░╚════╝░░╚═════╝░╚══════╝╚═╝░░╚══╝

	EOD

	printf "\n\033[92m%s\033[00m\n" "$welcome"
	printf "\033]0;%s\007" "$(basename "$ZSH_ARGZERO" | cut -d . -f 1)"

	remove_sleeping || return 1
	printf "\n"
	# assert_secrets true && remove_sleeping || return 1

	factors=(

		"update_permissions"
		"update_homebrew"

		"update_android_studio"
		# "update_chromium"
		# "update_git"
		# "update_phpstorm"
		# "update_pycharm"
		# "update_rider"
		# "update_vscode"
		# "update_xcode"

		# "update_angular"
		"update_docker"
		# "update_dotnet"
		"update_flutter"
		# "update_mqtt_explorer"
		# "update_nodejs"
		# "update_odoo"
		# "update_powershell"
		# "update_python"
		# "update_vemto"

		"update_figma"
		# "update_iina"
		# "update_insomnia"
		# "update_iterm"
		# "update_jdownloader"
		# "update_joal_desktop"
		# "update_keepassxc"
		# "update_mpv"
		# "update_netnewswire"
		# "update_nightshift"
		# "update_the_unarchiver"
		# "update_transmission"

		"update_appearance"
		"update_system"

	)

	maximum=$((${#welcome} / $(echo "$welcome" | wc -l)))
	heading="\r%-"$((maximum - 20))"s   %-6s   %-8s\n\n"
	loading="\r%-"$((maximum - 20))"s   \033[93mACTIVE\033[0m   %-8s\b"
	failure="\r%-"$((maximum - 20))"s   \033[91mFAILED\033[0m   %-8s\n"
	success="\r%-"$((maximum - 20))"s   \033[92mWORKED\033[0m   %-8s\n"

	printf "$heading" "FUNCTION" "STATUS" "DURATION"

	for element in "${factors[@]}"; do

		written=$(basename "$(echo "$element" | cut -d '"' -f 1)" | tr "[:lower:]" "[:upper:]")
		started=$(date +"%s") && printf "$loading" "$written" "--:--:--"
		eval "$element" >/dev/null 2>&1 && current="$success" || current="$failure"
		extinct=$(date +"%s") && elapsed=$((extinct - started))
		elapsed=$(printf "%02d:%02d:%02d\n" $((elapsed / 3600)) $(((elapsed % 3600) / 60)) $((elapsed % 60)))
		printf "$current" "$written" "$elapsed"

	done

	printf "\n" && enable_sleeping

}

main
