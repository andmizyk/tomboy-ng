#!/usr/bin/bash

# ====================================================
# a short script to make RPMs from our tomboy-ng debs
# does more than just call alien as that seems to end up
# with commands to create / and /usr/bin that upset yum
#
# This script must be run as fake root, so useage is -
# fakeroot bash mk_rpm
#
# History
# 2020/03/10 
# Finally worked out why yum won't work, while the rpm
# command is happy with me calling the arch i386, amd64 (debian speak)
# yum insists on them being x86, x86_64.
# Manually add wmctrl to dependencies.
# ====================================================

PROD=tomboy-ng
VERS=`cat version`
RDIR="$PROD"-"$VERS"


function DoAlien ()  {
	FILENAME="$PROD"_"$VERS"-0_"$1".deb
	ARCH="$1"
	rm -Rf "$RDIR"
	# Note, debs have a dash after initial version number, RPM an underscore
	if [ "$1" = amd64Qt ]; then
	#	FILENAME="tomboy-ngQt_0.24b-0_amd64.deb"
		ARCH=x86_64
	fi
	if [ "$1" = amd64 ]; then
		ARCH=x86_64
	fi
	if [ "$1" = i386 ]; then
		ARCH=x86
	fi

	echo "--- RDIR=$RDIR and building for $1 using $FILENAME ---------"
	alien -r -g -v "$FILENAME"
	# Alien inserts requests the package create / and /usr/bin and
	# the os does not apprieciate that, not surprisingly.
	# This removes the %dir /   
	sed -i 's#%dir "/"##' "$RDIR"/"$RDIR"-2.spec
	# and this removes %dir /usr/bin
	sed -i 's#%dir "/usr/bin/"##' "$RDIR"/"$RDIR"-2.spec
	# rpmbuild detects the dependencies but it misses wmctrl due to way its used.
	# So we add it to the spec file manually, insert as line 5.
	# at the same time we add things Fedora Gnome need to display SysTray Icon
	# not needed in other desktops but should not break anything, I hope.
	# Note that the user still needs to restart desktop and then issue
	# $>  gnome-extensions enable appindicatorsupport@rgcjonas.gmail.com
	sed -i '5i Requires: wmctrl libappindicator-gtk3 gnome-shell-extension-appindicator' "$RDIR"/"$RDIR"-2.spec
	# cp -r "$RDIR" "$RDIR"-"$1"
	cd "$RDIR"
	rpmbuild --target "$ARCH" --buildroot "$PWD" -bb "$RDIR"-2.spec
	cd ..
	# if its a Qt one, rename it so it does not get overwritten subsquently
	if [ "$1" = amd64Qt ]; then
		mv "$RDIR"-2."$ARCH".rpm "$PROD"Qt-"$VERS"-2."$ARCH".rpm
	fi
}

rm -f tom*.rpm
# Must do the "non std" ones first, else have overwrite problems
DoAlien "amd64Qt"
DoAlien "i386"
DoAlien "amd64"
chown "$SUDO_USER" *.rpm
ls -l *.rpm
echo "OK, now sign with    rpm --addsign  *.rpm"

