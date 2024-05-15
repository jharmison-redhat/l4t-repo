#!/bin/bash -e

function crashout {
	if [[ "${1:-0}" -ne 0 ]]; then
		log -l warn -- PWD: "$PWD"
		noisy -l warn -- tree /repobuild
	fi
}
trap 'crashout $?' EXIT

declare -A levels
levels=(
	[DEBUG]=0
	[INFO]=1
	[NOTICE]=2
	[WARN]=3
	[ERR]=4
	[CRIT]=5
	[ALERT]=6
	[EMERG]=7
)
declare -A level_text
level_text=(
	[DEBUG]="[  DEBUG  ]"
	[INFO]="[  INFO   ]"
	[NOTICE]="[  NOTICE ]"
	[WARN]="[ WARNING ]"
	[ERR]="[  ERROR  ]"
	[CRIT]="[ CRITICAL]"
	[ALERT]="[  ALERT  ]"
	[EMERG]="[EMERGENCY]"
)
LOG_LEVEL=${LOG_LEVEL:-INFO}

function _log_level_warn {
	log -l warn "Unknown logging level specified ($1). Assuming INFO."
}

function log {
	# Default to debug messages if unspecified
	local msg_level
	msg_level=DEBUG
	# Default to info if couldn't parse
	local log_level
	log_level=${levels["${LOG_LEVEL@U}"]:-1}
	# Define an array for the message content
	local -a msg
	# If the log level is ERR or higher, exit 1 after echoing
	local fail
	fail=true

	# Parse function arguments
	while (($# > 0)); do
		case "$1" in
		-l | --level=*)
			# Set the log level
			if [[ "$1" = "-l" ]]; then
				shift
				msg_level="$1"
			else
				msg_level="$(cut -d= -f2- <<<"$1")"
			fi
			msg_level="${msg_level@U}"
			if [[ -z "${levels[$msg_level]}" ]]; then
				_log_level_warn "$msg_level"
				msg_level=INFO
			fi
			# Exit early rather than parse the rest
			if ((${levels[$msg_level]} < log_level)); then
				return 0
			fi
			;;
		-n | --no-fail)
			fail=false
			;;
		-)
			# Read stdin for the msg
			read -ra msg
			;;
		--)
			# Read the rest of the arguments as the message
			shift
			msg+=("${@}")
			break
			;;
		*)
			# Anything not picked up already is just a word to add to the message
			msg+=("$1")
			;;
		esac
		shift
	done

	# Assume stdin if nothing was captured from parsing
	if ((${#msg[@]} == 0)); then
		read -ra msg
	fi

	# Confirm we should process this message
	if ((${levels[$msg_level]} < log_level)); then
		return 0
	fi
	# Capture the time after early returns
	local datetime
	datetime="$(date -Iseconds)"

	echo "repobuild.sh (${datetime}) ${level_text[$msg_level]}: ${msg[*]}" >&2

	if $fail; then
		if ((${levels[$msg_level]} >= 4)); then
			exit 1
		fi
	fi
}

function noisy {
	local -a cmd
	local fail
	fail=true
	local msg_level
	msg_level=INFO
	local output
	output=false
	local quiet
	quiet=false
	while (($# > 0)); do
		case "$1" in
		-n | --no-fail)
			fail=false
			;;
		-l | --level=*)
			# Set the log level
			if [[ "$1" = "-l" ]]; then
				shift
				msg_level="$1"
			else
				msg_level="$(cut -d= -f2- <<<"$1")"
			fi
			;;
		-o | --output)
			output=true
			;;
		-q | --quiet)
			quiet=true
			;;
		--)
			# Read the rest of the arguments as the command
			shift
			cmd+=("${@}")
			break
			;;
		*)
			cmd+=("$1")
			;;
		esac
		shift
	done
	quoted_cmd="${cmd[*]@Q}"
	log -l "$msg_level" -n Running command: "$quoted_cmd"
	if $fail; then
		set -e
	fi
	if $output; then
		local retfile
		retfile=$(mktemp)
		export retfile
		if $quiet; then
			while IFS= read -r line; do
				log -l "$msg_level" -n -- "$line"
			done < <(
				"${cmd[@]}" 2>&1
				echo "$?" >"$retfile"
			)
		else
			while IFS= read -r line; do
				log -l "$msg_level" -n -- "$line"
			done < <(
				"${cmd[@]}"
				echo "$?" >"$retfile"
			)
		fi
		ret="$(cat "$retfile")"
		rm -f "$retfile"
		unset retfile
	else
		if $quiet; then
			"${cmd[@]}" 2>/dev/null
		else
			"${cmd[@]}"
		fi
		ret=$?
	fi
	set +e
	return "$ret"
}

# If we are running in an OpenShift BuildConfig, we should look for secrets in a folder
if [ -f /repobuild/secrets/gpg-key ]; then
	GPG_PRIVATE_KEY=$(cat /repobuild/secrets/gpg-key)
fi

# If we are able to sign, import the key and export the pubkey
if [ -n "$GPG_PRIVATE_KEY" ]; then
	log -l info -- Importing GPG key and exporting public key
	echo "$GPG_PRIVATE_KEY" | base64 -d >"$HOME/repo.asc"
	noisy gpg --batch --import "$HOME/repo.asc"
	key=$(gpg --batch --show-keys --with-colons "$HOME/repo.asc" | awk -F: '/^fpr/{print $10}' | head -1)
	log -l info -- Identified key: "$key"
	noisy gpg --batch --export --armor "$key" >dist/SOURCES/RPM-GPG-KEY-jharmison-repo.pub
	echo
fi

# Build our repo installation RPMs using the key that signed the repos
log -l info -- Building repo installation RPMs
echo '%_topdir '"$PWD"'/dist' >"$HOME/.rpmmacros"
noisy rpmdev-setuptree
for repo in dist/SPECS/*.spec; do
	noisy rpmbuild -ba "$repo"
done
# And include them in the repo root
noisy cd repo
noisy mv ../dist/RPMS/*/*.rpm ./
noisy mv ../dist/SRPMS/*.src.rpm ./
for reporpm in *.noarch.rpm; do
	shortname=$(echo "$reporpm" | cut -d- -f1-4)
	version=$(echo "$shortname" | cut -d- -f4)
	srpm=$(find . -mindepth 1 -maxdepth 1 -type f -name "$shortname-*.src.rpm" -exec basename {} \;)
	log -l info -- Short name: "$shortname"
	log -l info -- Version: "$version"
	log -l info -- SRPM: "$srpm"
	if [ -n "$GPG_PRIVATE_KEY" ]; then
		noisy rpmsign --addsign "--key-id=$key" "$reporpm" "$srpm"
	fi
	noisy ln -sr "$reporpm" "$shortname.rpm"
	for arch in "$version/"*; do
		noisy ln -sr "$reporpm" "$arch/$reporpm"
	done
	noisy mkdir -p "$version/SRPMS"
	noisy ln -sr "$srpm" "$version/SRPMS/$srpm"
done
echo

# For every release we downloaded RPMs for
log -l info -- Creating and signing repositories
for release in *; do
	if [ -d "$release" ]; then
		log -l info -- Release "$release"
		noisy pushd "$release"
		# For every arch we had RPMs for
		for arch in *; do
			if [ -d "$arch" ]; then
				log -l info -- Architecture: "$arch"
				noisy pushd "$arch"
				# Create a repository
				noisy createrepo .
				# And sign it, if we can
				if [ -n "$GPG_PRIVATE_KEY" ]; then
					noisy gpg --batch --detach-sign --armor --local-user "$key" repodata/repomd.xml
				fi
				noisy popd
			fi
		done
		noisy popd
	fi
done

# Back to the root of the project
noisy cd ..

# Helpful output for pipeline
noisy tree
