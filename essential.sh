#!/bin/zsh

#region security

assert_apple_id() {

	appmail=$(security find-generic-password -a $USER -s appmail -w 2>/dev/null)
	apppass=$(security find-generic-password -a $USER -s apppass -w 2>/dev/null)

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

	is_root=$([[ $EUID = 0 ]] && echo true || echo false)

	if [[ $is_root = true ]]; then
		printf "\r\033[91m%s\033[00m\n\n" "EXECUTING THIS SCRIPT AS ROOT IS NOT ADMITTED"
		return 1
	fi

	return 0

}

assert_password() {

	account=$(security find-generic-password -a $USER -s account -w 2>/dev/null)
	correct=$(sudo -k ; echo "$account" | sudo -S -v &>/dev/null && echo true || echo false)

	if [[ $correct = false ]]; then
		security delete-generic-password -s account &>/dev/null
		printf "\r\033[91m%s\033[00m\n\n" "ACCOUNT PASSWORD NOT IN KEYCHAIN OR INCORRECT"
		printf "\r\033[92m%s\033[00m\n\n" "security add-generic-password -a $USER -s account -w password"
		return 1
	fi

	return 0

}

remove_security() {

	version=$(sw_vers -productVersion)
	correct=$([[ "${version:0:2}" = "12" ]] && echo true || echo false)

	if [[ $correct = false ]]; then
		printf "\r\033[91m%s\033[00m\n\n" "CURRENT MACOS VERSION (${version:0:4}) IS NOT SUPPORTED"
		return 1
	fi

	printf "\r\033[93m%s\033[00m" "CHANGING SECURITY, PLEASE FOLLOW THE MESSAGES"

	account=$(security find-generic-password -w -s "account" -a "$USER" 2>/dev/null)
	program=$(echo "$TERM_PROGRAM" | sed -e "s/.app//" | sed -e "s/Apple_//")
	heading=$(basename "$ZSH_ARGZERO" | cut -d . -f 1)
	allowed() { osascript -e 'tell application "System Events" to log ""' &>/dev/null }
	capable() { osascript -e 'tell application "System Events" to key code 60' &>/dev/null }
	granted() { plutil -lint /Library/Preferences/com.apple.TimeMachine.plist &>/dev/null }

	while ! allowed; do
		message="Press the OK button"
		osascript <<-EOD &>/dev/null
			tell application "${TERM_PROGRAM//Apple_/}"
				display alert "$heading" message "$message" as informational giving up after 10
			end tell
		EOD
		tccutil reset AppleEvents &>/dev/null
	done

	while ! capable; do
		osascript -e 'tell application "universalAccessAuthWarn" to quit' &>/dev/null
		message="Press the lock icon, enter your password, ensure $program is present, checked it and close the window"
		osascript <<-EOD &>/dev/null
			tell application "${TERM_PROGRAM//Apple_/}"
				display alert "$heading" message "$message" as informational giving up after 10
			end tell
		EOD
		open -W "x-apple.systempreferences:com.apple.preference.security?Privacy_Accessibility" &>/dev/null
	done

	if ! granted; then
		message="The script is going to add $program in full disk access automatically, don't touch anything"
		osascript <<-EOD &>/dev/null
			tell application "${TERM_PROGRAM//Apple_/}"
				display alert "$heading" message "$message" as informational giving up after 10
			end tell
		EOD
		osascript <<-EOD &>/dev/null
			-- Ensure the system preferences application is not running
			if running of application "System Preferences" then
				tell application "System Preferences" to quit
				delay 2
			end if
			-- Reveal the security pane of the system preferences application
			tell application "System Preferences"
				activate
				reveal anchor "Privacy" of pane "com.apple.preference.security"
				delay 4
			end tell
			-- Handle the full disk access permission
			tell application "System Events" to tell application process "System Preferences"
				-- Press the lock icon
				click button 1 of window 1
				delay 4
				-- Enter the account password
				set value of text field 2 of sheet 1 of window 1 to "$account"
				delay 2
				click button 2 of sheet 1 of window 1
				-- Press the full disk access row
				delay 2
				select row 11 of table 1 of scroll area 1 of tab group 1 of window 1
				-- Fecth the table row element by its name
				set fullAccessTable to table 1 of scroll area 1 of group 1 of tab group 1 of window 1
				set terminalItemRow to (row 1 where name of UI element 1 is "$program" or name of UI element 1 is "${program}.app") of fullAccessTable
				-- Check the checkbox only if it is not already checked
				set terminalCheckbox to checkbox 1 of UI element 1 of terminalItemRow
				set checkboxStatus to value of terminalCheckbox as boolean
				if checkboxStatus is false then
					click terminalCheckbox
					delay 2
					click button 1 of sheet 1 of window 1
				end if
			end tell
			-- Ensure the system preferences application is not running
			if running of application "System Preferences" then
				delay 2
				tell application "System Preferences" to quit
			end if
		EOD
	fi

}

#endregion

#region services

change_default_browser() {

	# Handle parameters
	browser=${1:-safari}

	# Update dependencies
	brew install defaultbrowser

	# Change browser
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

expand_archive() {

	# Handle parameters
	archive=${1}
	deposit=${2:-.}
	subtree=${3:-0}

	# Expand archive
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

search_pattern() {

	# Handle parameters
	pattern=${1}
	expanse=${2:-0}

	# Output results
	printf "%s" "$(/bin/zsh -c "find $pattern -maxdepth $expanse" 2>/dev/null | sort -r | head -1)"

}

update_chromium_extension() {

	# Handle parameters
	payload=${1}

	# Update extension
	if [[ -d "/Applications/Chromium.app" ]]; then
		if [[ ${payload:0:4} = "http" ]]; then
			address="$payload"
			package=$(mktemp -d)/$(basename "$address")
		else
			version=$(defaults read "/Applications/Chromium.app/Contents/Info" CFBundleShortVersionString)
			address="https://clients2.google.com/service/update2/crx?response=redirect&acceptformat=crx2,crx3"
			address="${address}&prodversion=${version}&x=id%3D${payload}%26installsource%3Dondemand%26uc"
			package=$(mktemp -d)/${payload}.crx
		fi
		curl -Ls "$address" -o "$package" || return 1
		defaults write NSGlobalDomain AppleKeyboardUIMode -int 3
		if [[ $package = *.zip ]]; then
			storage="/Applications/Chromium.app/Unpacked/$(echo "$payload" | cut -d / -f5)"
			present=$([[ -d "$storage" ]] && echo true || echo false)
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
	pattern=${1}
	element=${2}

	# Update dependencies
	brew install grep jq
	brew upgrade grep jq

	# Update plugin
	deposit=$(search_pattern "$HOME/*ibrary/*pplication*upport/*/*$pattern*")
	if [[ -d $deposit ]]; then
		checkup=$(search_pattern "/*pplications/*${pattern:0:5}*/*ontents/*nfo.plist")
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

#endregion

update_android_studio() {

	# Update dependencies
	brew install fileicon grep xmlstarlet
	brew upgrade fileicon grep xmlstarlet

	# Update package
	starter="/Applications/Android Studio Preview.app"
	present=$([[ -d "$starter" ]] && echo true || echo false)
	brew tap homebrew/cask-versions
	brew install --cask homebrew/cask-versions/android-studio-preview-canary
	brew upgrade --cask homebrew/cask-versions/android-studio-preview-canary

	# Update commandlinetools
	brew install --cask android-commandlinetools temurin
	brew upgrade --cask android-commandlinetools temurin

	# Finish installation
	if [[ $present = false ]]; then
		yes | sdkmanager "build-tools;33.0.1"
		yes | sdkmanager "emulator"
		yes | sdkmanager "extras;intel;Hardware_Accelerated_Execution_Manager"
		yes | sdkmanager "platform-tools"
		yes | sdkmanager "platforms;android-32"
		yes | sdkmanager "platforms;android-33"
		yes | sdkmanager "sources;android-33"
		yes | sdkmanager "system-images;android-33;google_apis;x86_64"
		avdmanager create avd -n "Pixel_5_API_33" -d "pixel_5" -k "system-images;android-33;google_apis;x86_64" &>/dev/null
	fi

}

# update_appearance() {}

update_chromium() {

	# Handle parameters
	deposit=${1:-$HOME/Downloads/DDL}
	pattern=${2:-duckduckgo}
	tabpage=${3:-about:blank}

	# Update dependencies
	brew install jq
	brew upgrade jq

	# Update package
	checkup="/Applications/Chromium.app"
	present=$([[ -d "$checkup" ]] && echo true || echo false)
	brew install --cask eloston-chromium
	brew upgrade --cask eloston-chromium
	killall Chromium
	sudo xattr -rd com.apple.quarantine /Applications/Chromium.app

	# Change default browser
	change_default_browser "chromium"

	# Finish installation
	if [[ $present = false ]]; then

		# Change language
		defaults write org.chromium.Chromium AppleLanguages "(en-US)"

		# Handle notification
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

		# Change deposit
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

		# Update ublock-origin
		update_chromium_extension "cjpalhdlnbpafiamejdnhcphjbkeiagm"

	fi

	# Update bypass-paywalls-chrome
	update_chromium_extension "https://github.com/iamadamdev/bypass-paywalls-chrome/archive/master.zip"

}

update_flutter() {

	# Update package
	brew install --cask flutter
	brew upgrade --cask flutter

	# Change environment
	altered="$(grep -q "CHROME_EXECUTABLE" "$HOME/.zshrc" >/dev/null 2>&1 && echo true || echo false)"
	present="$([[ -d "/Applications/Chromium.app" ]] && echo true || echo false)"
	if [[ $altered = false && $present = true ]]; then
		[[ -s "$HOME/.zshrc" ]] || echo '#!/bin/zsh' >"$HOME/.zshrc"
		[[ -z $(tail -1 "$HOME/.zshrc") ]] || echo "" >>"$HOME/.zshrc"
		echo 'export CHROME_EXECUTABLE="/Applications/Chromium.app/Contents/MacOS/Chromium"' >>"$HOME/.zshrc"
		source "$HOME/.zshrc"
	fi

	# Finish installation
	flutter config --no-analytics
	flutter precache && flutter upgrade
	yes | flutter doctor --android-licenses

	# Update android-studio
	update_jetbrains_plugin "AndroidStudio" "6351"  # Dart
	update_jetbrains_plugin "AndroidStudio" "9212"  # Flutter

	# Update visual-studio-code
	code --install-extension "dart-code.flutter" &>/dev/null

}

# update_figma() {}
# update_gh() {}
# update_git() {}

update_homebrew() {

	printf "\r\033[93m%s\033[00m" "UPGRADING HOMEBREW PACKAGE, PLEASE BE PATIENT"
	command=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
	CI=1 /bin/bash -c "$command" &>/dev/null

}

# update_iina() {}

update_jdownloader() {

	# Handle parameters
	deposit=${1:-$HOME/Downloads/JD2}

	# Update dependencies
	brew install coreutils fileicon jq
	brew upgrade coreutils fileicon jq
	brew install --cask homebrew/cask-versions/temurin8
	brew upgrade --cask homebrew/cask-versions/temurin8

	# Update package
	brew install --cask jdownloader
	brew upgrade --cask jdownloader

	# Change settings
	appdata="/Applications/JDownloader 2.0/cfg"
	config1="$appdata/org.jdownloader.settings.GeneralSettings.json"
	config2="$appdata/org.jdownloader.settings.GraphicalUserInterfaceSettings.json"
	config3="$appdata/org.jdownloader.gui.jdtrayicon.TrayExtension.json"
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
	jq ".donatebuttonlatestautochange = 4102444800000" "$config1" | sponge "$config1"
	jq ".donatebuttonstate = \"AUTO_HIDDEN\"" "$config1" | sponge "$config1"
	jq ".myjdownloaderviewvisible = false" "$config1" | sponge "$config1"
	jq ".premiumalertetacolumnenabled = false" "$config1" | sponge "$config1"
	jq ".premiumalertspeedcolumnenabled = false" "$config1" | sponge "$config1"
	jq ".premiumalerttaskcolumnenabled = false" "$config1" | sponge "$config1"
	jq ".specialdealoboomdialogvisibleonstartup = false" "$config1" | sponge "$config1"
	jq ".specialdealsenabled = false" "$config1" | sponge "$config1"
	jq ".speedmetervisible = false" "$config1" | sponge "$config1"
	jq ".defaultdownloadfolder = \"$deposit\"" "$config2" | sponge "$config2"
	jq ".enabled = false" "$config3" | sponge "$config3"

	# Change icons
	picture="$(dirname $ZSH_ARGZERO)/icons/jdownloader.icns"
	fileicon set "/Applications/JDownloader 2.0/JDownloader2.app" "$picture" || sudo !!
	fileicon set "/Applications/JDownloader 2.0/JDownloader Uninstaller.app" "$picture" || sudo !!
	cp "$picture" "/Applications/JDownloader 2.0/JDownloader2.app/Contents/Resources/app.icns"
	sips -Z 128 -s format png "$picture" --out "/Applications/JDownloader 2.0/themes/standard/org/jdownloader/images/logo/jd_logo_128_128.png"

}

# update_joal_desktop() {}
# update_keepassxc() {}
# update_macos() {}
# update_nightlight() {}
# update_nodejs() {}
# update_pycharm() {}
# update_python() {}
# update_spotify() {}
# update_scrcpy() {}
# update_the_unarchiver() {}
# update_transmission() {}
# update_utm() {}
# update_vscode() {}
# update_xcode() {}

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
	sudo pmset -a disablesleep 1 && caffeinate -i -w $$ &

	# Verify password
	assert_password || return 1

	# Remove security
	# remove_security || return 1

	# Update homebrew
	update_homebrew || return 1

	# Verify apple id
	# assert_apple_id || return 1

	# Handle elements
	factors=(
		"update_macos"

		"update_android_studio"
		"update_chromium"
		"update_pycharm"
		"update_vscode"
		"update_xcode"

		"update_figma"
		"update_flutter"
		"update_gh"
		"update_git"
		"update_iina"
		"update_jdownloader"
		"update_joal_desktop"
		"update_nightlight"
		"update_nodejs"
		"update_python"
		"update_the_unarchiver"
		"update_transmission"
		"update_utm"

		"update_appearance"
	)

	# Output progress
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

	# Revert timeouts
	sudo rm /private/etc/sudoers.d/disable_timeout 2>/dev/null

	# Revert sleeping
	sudo pmset -a disablesleep 0

	# Output new line
	printf "\n"

}

main
