#!/usr/bin/env bash
export STEAMAPPS="$HOME/.steam/steam/steamapps"
export STEAM_COMPAT_DATA_PATH="$STEAMAPPS/compatdata/813780"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam"
export WINEPREFIX="$STEAMAPPS/compatdata/813780/pfx"
# Xalia (Proton's accessibility helper) floods the output with stack traces
export PROTON_USE_XALIA=0

if [[ ! -d $HOME/.local/bin ]]; then
  echo "Missing $HOME/.local/bin directory. It needs to be created and added to the \$PATH."
  exit -1
fi

# Source - https://stackoverflow.com/a/48185201
# Posted by tripleee
# Retrieved 2026-06-06, License - CC BY-SA 3.0

case :$PATH: in (*:$HOME/.local/bin:*)
  ;;
(*)
  echo "$HOME/.local/bin not in \$PATH. Please ensure it is added to \$PATH before running this script." >&2
  exit -2
  ;;
esac

echo "Welcome the the UNOFFICIAL CA:DE Linux Installer"
echo ""
echo "This installer is provided AS IS. You are responsible to verify that it will function properly and not cause issues on your computer."
echo -n "Before proceeding, do you accept the terms and condition for CaptureAge? (https://captureage.com/terms) [y/N] "
read -r terms_accepted

if [ "${terms_accepted,,}" != "y" ]; then
  echo "You decided to refuse the terms and conditions, exiting..."
  exit 0
fi

echo "Downloading installer"

curl -s -L https://captureage.com/api/cade/download/prod/latest-setup --output CaptureAgeSetup.exe

proton_path="$(head -n 2 "$STEAM_COMPAT_DATA_PATH/config_info" | tail -n 1)"
proton="$(dirname "$(dirname "$(dirname "$proton_path")")")/proton"
if [[ ! -x "$proton" ]]; then
  echo "Could not detect proton. Tried to use: $proton"
  exit 1
fi
wineserver="$(dirname "$proton")/files/bin/wineserver"

# A running game keeps its own wineserver with the registry in memory and
# overwrites the .reg files on exit, discarding everything written here.
if pgrep -f 'AoE2DE_s\.exe' >/dev/null; then
  echo "Age of Empires 2 is running. Please close it before running this installer." >&2
  exit 1
fi

#install capture age (only needed once). You need to manually copy the CaptureAgeSetup.exe in this location.

echo
echo "Will now run the installer"
echo
echo "***WARNING***"
echo "You may get error messages from CaptureAge and it may not launch until you run Age of Empires 2"
echo "This is a CaptureAge limitation. At the end of the installer, try running Age of Empires 2 and launching a replay from within the game using the \"Spectate with CA\" button."
echo "Next time you start CaptureAge, you should not receive error messages."
echo

"$proton" run "Z:/$(pwd)/CaptureAgeSetup.exe"

if [[ -e $HOME/.local/bin/aoe2url ]]; then
  echo "URL handler already exists, skipping..."
else
  echo "Installation complete, adding AoE2 URL Handler"
  cat >$HOME/.local/bin/aoe2url <<'EOF'
#!/usr/bin/env bash
export PROTON_LOG=1
export STEAMAPPS="$HOME/.steam/steam/steamapps"
export STEAM_COMPAT_DATA_PATH="$STEAMAPPS/compatdata/813780"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam"
export WINEPREFIX="$STEAMAPPS/compatdata/813780/pfx"

proton_path="$(head -n 2 "$STEAM_COMPAT_DATA_PATH/config_info" | tail -n 1)"
proton="$(dirname "$(dirname "$(dirname "$proton_path")")")/proton"

"$proton" run "$STEAMAPPS/common/AoE2DE/Tools_Builds/AOEURLHelper.exe" "$@"
EOF
  chmod u+x $HOME/.local/bin/aoe2url
fi

if [[ -e $HOME/.local/share/applications/AoE2UrlHelper.desktop ]]; then
  echo "URL handler desktop file already exists, skipping..."
else
  echo "Installation complete, adding AoE2 URL Handler"
  cat >$HOME/.local/share/applications/AoE2UrlHelper.desktop <<EOF
[Desktop Entry]
Name=AoE2 URL Opener
Comment=Play this game on Steam (Open URL)
Exec=$HOME/.local/bin/aoe2url %u
Icon=steam_icon_813780
Terminal=false
Type=Application
MimeType=x-scheme-handler/aoe2de
Categories=Game
EOF
  echo "Updating desktop database, sudo is required"
  sudo update-desktop-database
fi
xdg-mime default AoE2UrlHelper.desktop x-scheme-handler/aoe2de

# The registry entries and scripts have been originally developed by TeknoHamster
# https://gist.github.com/TeknoHamster/d8b2f90a1cd618074aa1e35c81e7bc4b
reg_add() {
  "$proton" run reg add "$@"
}

#This creates Windows registries to make the Spectate with CA button work
register_captureage() {
  local protocol_command

  protocol_command="\"$CAPTUREAGE_DIR_WIN\\CaptureAge.exe\" \"%1\""

  for root in HKCU\\Software\\Classes HKLM\\Software\\Classes; do
    reg_add "$root\\captureage" /ve /d "URL:captureage" /f
    reg_add "$root\\captureage" /v "URL Protocol" /d "" /f
    reg_add "$root\\captureage\\shell\\open\\command" /ve /d "$protocol_command" /f
  done

  for root in HKCU HKLM; do
    reg_add "$root\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\CaptureAge.exe" /ve /d "$CAPTUREAGE_DIR_WIN\\CaptureAge.exe" /f
    reg_add "$root\\Software\\Microsoft\\Windows\\CurrentVersion\\App Paths\\CaptureAge.exe" /v "Path" /d "$CAPTUREAGE_DIR_WIN" /f
  done
}

# CaptureAge defaults to C:\Program Files (x86)\Steam\steamapps\common\AoE2DE,
# which does not exist in the Proton prefix, and crashes when spectating.
# Point it to the game directory the game itself registered.
set_game_directory() {
  local state="$WINEPREFIX/drive_c/users/steamuser/AppData/Roaming/CaptureAge/persistedState_prod.json"
  local game_dir_win tmp_state

  game_dir_win="$(sed -n 's/^"Install Location"="\(.*\)"\r\?$/\1/p' "$WINEPREFIX/user.reg" | head -n 1 | sed 's/\\\\/\\/g')"
  if [[ -z "$game_dir_win" ]]; then
    echo "Could not detect the AoE2 game directory. Start Age of Empires 2 once and rerun this installer." >&2
    return
  fi
  if [[ ! -f "$state" ]]; then
    echo "CaptureAge settings not found. Start CaptureAge once and rerun this installer to set the game directory." >&2
    return
  fi
  echo "Setting CaptureAge game directory to $game_dir_win"
  tmp_state="$(mktemp)"
  jq --arg dir "$game_dir_win" '.lastUsedGameDirectory = $dir' "$state" >"$tmp_state" && mv "$tmp_state" "$state"
}

if [[ -d "$STEAM_COMPAT_DATA_PATH/pfx/drive_c/users/steamuser/AppData/Local/Programs/CADE" ]]; then
  export CAPTUREAGE_DIR_WIN='C:\users\steamuser\AppData\Local\Programs\CADE'
else
  export CAPTUREAGE_DIR_WIN='C:\users\steamuser\AppData\Local\Programs\CaptureAge'
fi
echo $CAPTUREAGE_DIR_WIN

if [[ -e $HOME/.local/bin/captureage ]]; then
  echo "captureage launcher script already exists, skipping..."
else
  echo "Adding CaptureAge launcher script"

  cat >$HOME/.local/bin/captureage <<'EOF'
#!/usr/bin/env bash
export PROTON_LOG=1
export STEAMAPPS="$HOME/.steam/steam/steamapps"
export STEAM_COMPAT_DATA_PATH="$STEAMAPPS/compatdata/813780"
export STEAM_COMPAT_CLIENT_INSTALL_PATH="$HOME/.steam"
export WINEPREFIX="$STEAMAPPS/compatdata/813780/pfx"
export OBS_VKCAPTURE=1

proton_path="$(head -n 2 "$STEAM_COMPAT_DATA_PATH/config_info" | tail -n 1)"
proton="$(dirname "$(dirname "$(dirname "$proton_path")")")/proton"

# run capture age
EOF
  echo "\"\$proton\" run \"$CAPTUREAGE_DIR_WIN\\CaptureAge.exe\"" >>$HOME/.local/bin/captureage
  chmod u+x $HOME/.local/bin/captureage
fi

# Always (re-)register, so rerunning the installer repairs missing entries
echo "Adding registry entries to ensure CaptureAge can be launched from within AoE2"
register_captureage
# Wait for the wineserver to exit so the registry is flushed to disk
WINEPREFIX="$WINEPREFIX" "$wineserver" -w

set_game_directory
