#!/bin/bash
# Scheme and test plan resolution helpers for test-ios.sh

resolve_execution_scheme() {
  case "${1}:${2}" in
    sideBar:AppleFast)
      # Keep `sideBar` as the user-facing Logic lane selector, but execute
      # AppleFast through sideBarLogicHost. Invoking AppleFast directly on the
      # sideBar scheme causes Xcode to union the scheme's built-in sideBarTests
      # with AppleFast's sideBarLogicTests, which then builds both sideBar and
      # sideBarLogicHost and can produce duplicate sideBar.swiftmodule outputs.
      echo "sideBarLogicHost"
      ;;
    *)
      echo "${1}"
      ;;
  esac
}

default_test_plan_for_scheme() {
  case "${1}" in
    sideBar)
      echo "AppleFast"
      ;;
    sideBarLogicHost)
      echo "AppleFast"
      ;;
    sideBarUI)
      echo "AppleUI"
      ;;
    sideBarExtensions)
      echo "AppleExtensions"
      ;;
    *)
      echo ""
      ;;
  esac
}

default_ui_smoke_only_testing() {
  cat <<'EOF'
sideBarUITests/SideBarUITests/testLoginSuccessNavigatesToSignedInHome,sideBarUITests/SideBarUITests/testSendMessageInSeededConversationShowsStreamingReply,sideBarUITests/SideBarUITests/testCreateEditDeleteNoteInSeededAccount,sideBarUITests/SideBarUITests/testStreamingReplyKeepsBottomAnchorVisible,sideBarUITests/SideBarUITests/testIPadTasksWorkspaceDoesNotShowFloatingDock
EOF
}

scheme_includes_ui_tests() {
  [[ "${1}" == "sideBarUI" ]]
}

scheme_has_only_ui_tests() {
  [[ "${1}" == "sideBarUI" ]]
}
