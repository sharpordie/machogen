#!/bin/zsh

expand_pattern() {

	local pattern=${1}
	local expanse=${2:-0}

	printf "%s" $(/bin/zsh -c "find $pattern -maxdepth $expanse" 2>/dev/null | sort -r | head -1)

}

expand_version() {

    local payload=${1}
    local default=${2:-0.0.0.0}

    brew install grep

    local starter=$(expand_pattern "$payload/*ontents/*nfo.plist")
    local version=$(defaults read "$starter" CFBundleShortVersionString 2>/dev/null)
    echo "$version" | ggrep -oP "[\d.]+" || echo "$default"

}

update_dbeaver_ultimate() {

    brew install curl jq

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

update_docker_desktop() {

    brew install curl jq
    
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

sudo -v
update_docker_desktop