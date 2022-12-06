#!/bin/zsh

#region services

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
	allowed() { osascript -e 'tell application "System Events" to log ""' &>/dev/null; }
	capable() { osascript -e 'tell application "System Events" to key code 60' &>/dev/null; }
	granted() { ls "$HOME"/Library/Messages &>/dev/null; }

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

# expand_arch() {} Used only in update_jetbrains_plugin
# invoke_mess() {} Used only in update_security
# search_file() {} Used only in update_jetbrains_plugin
# update_dock() {} Used once in update_appearance

update_chromium_extension() {}
update_jetbrains_plugin() {}
update_jetbrains_setting() {}

#endregion

update_android_studio() {

	# Update dependencies
	brew install fileicon grep xmlstarlet
	brew upgrade fileicon grep xmlstarlet

	# Update package
	starter="/Applications/Android Studio Preview.app"
	present=$([[ -d "$starter" ]] && echo true || echo false)
	brew tap homebrew/cask-versions
	brew install --cask android-studio-preview-canary
	brew upgrade --cask android-studio-preview-canary

	# Update cmdline

	# Change environment

	# Finish installation
	# if [[ $present = false ]]; then
	# 	return
	# fi

	# Update icon
	# address="https://media.macosicons.com/parse/files/macOSicons"
	# address="$address/de693c82ac93afd304fbcb3a0fb5ff1f_Android_Studio.icns"
	# fetched="$(mktemp -d)/$(basename "$address")"
	# curl -Ls "$address" -A "mozilla/5.0" -o "$fetched"
	# fileicon set "/Applications/Android Studio.app" "$fetched" &>/dev/null || sudo !!

}

update_appearance() {}
update_chromium() {}
update_flutter() {}
update_figma() {}
update_gh() {}
update_git() {}

update_homebrew() {

	printf "\r\033[93m%s\033[00m" "UPGRADING HOMEBREW PACKAGE, PLEASE BE PATIENT"
	command=$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)
	CI=1 /bin/bash -c "$command" &>/dev/null

}

update_iina() {}
update_iterm() {}
update_jdownloader() {}
update_joal_desktop() {}
update_keepassxc() {}
update_macos() {}
update_nightlight() {}
update_nodejs() {}
update_pycharm() {}
update_python() {}
update_spotify() {}
update_scrcpy() {}
update_the_unarchiver() {}
update_transmission() {}
update_vmware_fusion() {}
update_vscode() {}
update_xcode() {}

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
	remove_security || return 1

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
