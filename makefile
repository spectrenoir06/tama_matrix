project_name = new_project
apk_name = org.spectre.new_project

releases/$(project_name).love:
	love-release

releases/$(project_name).apk: releases/$(project_name).love
	cp releases/$(project_name).love ../love2apk/love_decoded/assets/game.love
	cp ressource/AndroidManifest.xml ../love2apk/love_decoded/
	apktool b -o releases/$(project_name).apk ../love2apk/love_decoded

releases/$(project_name)-aligned-debugSigned.apk: releases/$(project_name).apk
	java -jar ~/dev/prog/uber-apk-signer.jar --apks releases/$(project_name).apk

build_macos: releases/$(project_name).love
	love-release -M

build_win32: releases/$(project_name).love
	love-release -W 32

build_win64: releases/$(project_name).love
	love-release -W 64

build_debian: releases/$(project_name).love
	love-release -D

clean:
	rm -f releases/*.apk releases/*.love* releases/*.zip releases/*.deb

clean_love:
	rm -f releases/*.love*

apk_install: releases/$(project_name)-aligned-debugSigned.apk
	adb install releases/$(project_name)-aligned-debugSigned.apk

apk_run: apk_install
	adb shell am force-stop $(apk_name)
	adb shell am start -n $(apk_name)/org.love2d.android.GameActivity

apk_log:
	adb logcat --pid=`adb shell pidof -s $(apk_name)`

debug_install:
	~/dev/git/adb-sync/adb-sync main.lua ressource UI conf.lua lib frame thread_led_controller.lua /sdcard/lovegame

debug_run: debug_install
	adb shell am force-stop org.love2d.android
	adb shell am start -n org.love2d.android/.GameActivity

debug_log:
	adb logcat --pid=`adb shell pidof -s org.love2d.android`

all: clean build_macos build_win32 build_win64 build_debian releases/$(project_name)-aligned-debugSigned.apk 
	echo "Done"


.PHONY: clean clean_love debug apk_install apk_run apk_log debug_install debug_run debug_log all debian
