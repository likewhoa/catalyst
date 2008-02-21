#!/bin/bash

# Trap these signals and kill ourselves if recieved
# Force ourselves to die if any of these signals are recieved
# most likely our controlling terminal is gone
trap "echo SIGTERM signal recieved killing $0 with pid $$;kill -9 $$" SIGTERM
trap "echo SIGHUP signal recieved killing $0 with pid $$;kill -9 $$" SIGHUP
trap "echo SIGKILL signal recieved killing $0 with pid $$;kill -9 $$" SIGKILL

#SIGINT interrupt character (usually Ctrl-C)
#	* example: high-level sequence of events
#	* my process (call it "P") is running
#	* user types ctrl-c
#	* kernel recognizes this and generates SIGINT signal
trap "echo SIGINT signal recieved killing $0 with pid $$;kill -9 $$" SIGINT

check_genkernel_version(){
	if [ -x /usr/bin/genkernel ]
	then
		genkernel_version=$(genkernel --version)
		genkernel_version_major=${genkernel_version%%.*}
		genkernel_version_minor_sub=${genkernel_version#${genkernel_version_major}.}
		genkernel_version_minor=${genkernel_version_minor_sub%%.*}
		genkernel_version_sub=${genkernel_version##*.}
		if [ -n "${genkernel_version}" -a "${genkernel_version_major}" -eq '3' -a "${genkernel_version_minor}" -ge '3' ]
		then
			echo "Genkernel version ${genkernel_version} found ... continuing"
		else
			echo "ERROR: Your genkernel version is too low in your seed stage.  genkernel version 3.3.0"
			echo "or greater is required."
			exit 1
		fi
	else
		exit 1
	fi
}

get_libdir() {
	ABI=$(portageq envvar ABI)
	DEFAULT_ABI=$(portageq envvar DEFAULT_ABI)
	LIBDIR_default=$(portageq envvar LIBDIR_default)

	local abi
	if [ $# -gt 0 ]
	then
		abi=${1}
	elif [ -n "${ABI}" ]
	then
		abi=${ABI}
	elif [ -n "${DEFAULT_ABI}" ]
	then
		abi=${DEFAULT_ABI}
	else
		abi="default"
	fi

	local var="LIBDIR_${abi}"
	var=$(portageq envvar ${var})
	echo ${var}
}

setup_myfeatures(){
	setup_myemergeopts
	if [ -n "${clst_CCACHE}" ]
	then
		export clst_myfeatures="${clst_myfeatures} ccache"
		#if [ "${clst_AUTORESUME}" = "1" -a -e /tmp/.clst_ccache ]
		#then
		#	echo "CCACHE Autoresume point found not emerging ccache"
		#else
			clst_root_path=/ run_emerge --oneshot --nodeps ccache || exit 1
		#	touch /tmp/.clst_ccache
		#fi
	fi

	if [ -n "${clst_DISTCC}" ]
	then
		export clst_myfeatures="${clst_myfeatures} distcc"
		export DISTCC_HOSTS="${clst_distcc_hosts}"
		#if [ "${clst_AUTORESUME}" = "1" -a -e /tmp/.clst_distcc ]
		#then
		#	echo "DISTCC Autoresume point found not emerging distcc"
		#else
			USE="-gtk -gnome" clst_root_path=/ run_emerge --oneshot --nodeps distcc || exit 1
			#touch /tmp/.clst_distcc
		#fi
		mkdir -p /etc/distcc
		echo "${clst_distcc_hosts}" > /etc/distcc/hosts

		# This sets up automatic cross-distcc-fu according to
		# http://www.gentoo.org/doc/en/cross-compiling-distcc.xml
		CHOST=$(portageq envvar CHOST)
		# TODO: change to use get_libdir
		cd /usr/lib/distcc/bin
		rm cc gcc g++ c++ 2>/dev/null
		echo -e '#!/bin/bash\nexec /usr/lib/distcc/bin/'${CHOST}'-g${0:$[-2]} "$@"' > ${CHOST}-wrapper
		chmod a+x /usr/lib/distcc/bin/${CHOST}-wrapper
		for i in cc gcc g++ c++; do ln -s ${CHOST}-wrapper ${i}; done
	fi

	if [ -n "${clst_ICECREAM}" ]
	then
		clst_root_path=/ run_emerge --oneshot --nodeps sys-devel/icecream || exit 1

		# This sets up automatic cross-icecc-fu according to
		# http://gentoo-wiki.com/HOWTO_Setup_An_ICECREAM_Compile_Cluster#Icecream_and_cross-compiling
		CHOST=$(portageq envvar CHOST)
		LIBDIR=$(get_libdir)
		cd /usr/${LIBDIR}/icecc/bin
		rm cc gcc g++ c++ 2>/dev/null
		echo -e '#!/bin/bash\nexec /usr/'${LIBDIR}'/icecc/bin/'${CHOST}'-g${0:$[-2]} "$@"' > ${CHOST}-wrapper
		chmod a+x ${CHOST}-wrapper
		for i in cc gcc g++ c++; do ln -s ${CHOST}-wrapper ${i}; done
		export PATH="/usr/lib/icecc/bin:${PATH}"
		export PREROOTPATH="/usr/lib/icecc/bin"
	fi
	export FEATURES="${clst_myfeatures}"
}

setup_myemergeopts(){
	if [ -n "${clst_VERBOSE}" ]
	then
		clst_myemergeopts="--verbose"
	else
		clst_myemergeopts="--quiet"
	fi
	if [ -n "${clst_FETCH}" ]
	then
		export bootstrap_opts="-f"
		export clst_myemergeopts="${clst_myemergeopts} -f"
	elif [ -n "${clst_PKGCACHE}" ]
	then
		export clst_myemergeopts="${clst_myemergeopts} --usepkg --buildpkg --newuse"
		export bootstrap_opts="-r"
	fi
}

setup_portage(){
	# portage needs to be merged manually with USE="build" set to avoid frying
	# our make.conf. emerge system could merge it otherwise.
#	if [ "${clst_AUTORESUME}" = "1" -a -e /tmp/.clst_portage ]
#	then
#		echo "Portage Autoresume point found not emerging portage"
#	else
		USE="build" run_emerge --oneshot --nodeps portage
#		touch /tmp/.clst_portage || exit 1
#	fi
}

setup_gcc(){
	if [ -x /usr/bin/gcc-config ]
	then
		mythang=$( cd /etc/env.d/gcc; ls ${clst_CHOST}-* | head -n 1 )
		if [ -z "${mythang}" ]
		then
			mythang=1
		fi
		gcc-config ${mythang}; update_env_settings
	fi
}

setup_binutils(){
	if [ -x /usr/bin/binutils-config ]
	then
		mythang=$( cd /etc/env.d/binutils; ls ${clst_CHOST}-* | head -n 1 )
		if [ -z "${mythang}" ]
		then
			mythang=1
		fi
		binutils-config ${mythang}; update_env_settings
	fi
}

cleanup_distcc() {
	rm -rf /etc/distcc/hosts
	for i in cc gcc c++ g++; do
		# TODO: change to use get_libdir
		rm -f /usr/lib/distcc/bin/${i}
		ln -s /usr/bin/distcc /usr/lib/distcc/bin/${i}
	done
	rm -f /usr/lib/distcc/bin/*-wrapper
}

cleanup_icecream() {
	LIBDIR=$(get_libdir)
	for i in cc gcc c++ g++; do
		rm -f /usr/${LIBDIR}/icecc/bin/${i}
		ln -s /usr/bin/icecc /usr/${LIBDIR}/icecc/bin/${i}
	done
	rm -f /usr/${LIBDIR}/icecc/bin/*-wrapper
}

cleanup_stages() {
	if [ -n "${clst_DISTCC}" ]
	then
		cleanup_distcc
	fi
	if [ -n "${clst_ICECREAM}" ]
	then
		cleanup_icecream
	fi
	case ${clst_target} in
		stage1|stage2|stage3)
			rm -f /var/lib/portage/world
			touch /var/lib/portage/world
			;;
		*)
			echo "Skipping removal of world file for ${clst_target}"
			;;
	esac

	rm -f /var/log/emerge.log /var/log/portage/elog/*
	rm -rf /var/tmp/*
}

update_env_settings(){
	which env-update > /dev/null 2>&1
	ret=$?
	if [ $ret -eq 0 ]
	then
		ENV_UPDATE=`which env-update`
		${ENV_UPDATE}
	else
		echo "WARNING: env-update not found, skipping!"
	fi
	source /etc/profile
	[ -f /tmp/envscript ] && source /tmp/envscript
}

die() {
	echo "$1"
	exit 1
}

make_destpath() {
	if  [ "${1}" = "" ]
	then
		export ROOT=/
	else
		export ROOT=${1}
		if [ ! -d ${ROOT} ]
		then
			install -d ${ROOT}
		fi
	fi
}

run_emerge() {
	# Sets up the ROOT= parameter
	# with no options ROOT=/
	make_destpath ${clst_root_path}
	
	export EMERGE_WARNING_DELAY=0 	
	export CLEAN_DELAY=0
	export EBEEP_IGNORE=0
	export EPAUSE_IGNORE=0
	export CONFIG_PROTECT="-*"

	if [ -n "${clst_VERBOSE}" ]
	then
		echo "ROOT=${ROOT} emerge ${clst_myemergeopts} -pt $@" || exit 1
		emerge ${clst_myemergeopts} -pt $@ || exit 3
		echo "Press any key within 15 seconds to pause the build..."
		read -s -t 15 -n 1
		if [ $? -eq 0 ]
		then
			echo "Press any key to continue..."
			read -s -n 1
		fi
	fi

	echo "emerge ${clst_myemergeopts} $@" || exit 1

	emerge ${clst_myemergeopts} $@ || exit 1
}

show_debug() {
	if [ "${clst_DEBUG}" = "1" ]
	then
		unset PACKAGES
		echo "DEBUG:"
		echo "Profile/target info:"
		echo "Profile inheritance:"
		python -c 'import portage; print portage.settings.profiles'
		# TODO: grab our entire env
		# <zmedico> to get see the ebuild env you can do something like:
		# `set > /tmp/env_dump.${EBUILD_PHASE}` inside /etc/portage/bashrc
		echo
		echo "STAGE1_USE:            $(portageq envvar STAGE1_USE)"
		echo
		echo "USE (profile):         $(portageq envvar USE)"
		echo "USE (stage1):          ${USE}"
		echo "FEATURES (profile):    $(portageq envvar FEATURES)"
		echo "FEATURES (stage1):     ${FEATURES}"
		echo
		echo "ARCH:                  $(portageq envvar ARCH)"
		echo "CHOST:                 $(portageq envvar CHOST)"
		echo "CFLAGS:                $(portageq envvar CFLAGS)"
		echo
		echo "PROFILE_ARCH:          $(portageq envvar PROFILE_ARCH)"
		echo
		echo "ABI:                   $(portageq envvar ABI)"
		echo "DEFAULT_ABI:           $(portageq envvar DEFAULT_ABI)"
		echo "KERNEL_ABI:            $(portageq envvar KERNEL_ABI)"
		echo "MULTILIB_ABIS:         $(portageq envvar MULTILIB_ABIS)"
		echo
		### XXX: This is temporary until we make --debug force-enable --verbose
		if [ -n "${clst_buildpkgs}" ]
		then
			PACKAGES=${clst_buildpkgs}
		elif [ -n "${clst_packages}" ]
		then
			PACKAGES=${clst_packages}
		fi
		if [ -n "${PACKAGES}" ]
		then
			echo "Packages:"
			echo "${PACKAGES}"
			echo
		fi
		### XXX: end of section to remove
	fi
}

run_default_funcs() {
	if [ "${RUN_DEFAULT_FUNCS}" != "no" ]
	then
		update_env_settings
		setup_myfeatures
		show_debug
	fi
}

# Functions
# Copy libs of a executable in the chroot
function copy_libs() {
	# Check if it's a dynamix exec
	ldd ${1} > /dev/null 2>&1 || return

	for lib in `ldd ${1} | awk '{ print $3 }'`
	do
		echo ${lib}
		if [ -e ${lib} ]
		then
			if [ ! -e ${clst_root_path}/${lib} ]
			then
				copy_file ${lib}
				[ -e "${clst_root_path}/${lib}" ] && \
				strip -R .comment -R .note ${clst_root_path}/${lib} \
				|| echo "WARNING : Cannot strip lib ${clst_root_path}/${lib} !"
			fi
		else
			echo "WARNING : Some library was not found for ${lib} !"
		fi
	done
}

function copy_symlink() {
	STACK=${2}
	[ "${STACK}" = "" ] && STACK=16 || STACK=$((${STACK} - 1 ))

	if [ ${STACK} -le 0 ] 
	then
		echo "WARNING : ${TARGET} : too many levels of symbolic links !"
		return
	fi

	[ ! -e ${clst_root_path}/`dirname ${1}` ] && \
		mkdir -p ${clst_root_path}/`dirname ${1}`
	[ ! -e ${clst_root_path}/${1} ] && \
		cp -vfdp ${1} ${clst_root_path}/${1}
	
	if [[ -n $(type -p realpath) ]]; then
		TARGET=`realpath ${1}`
	else
		TARGET=`readlink -f ${1}`
	fi
	if [ -h ${TARGET} ]
	then
		copy_symlink ${TARGET} ${STACK}
	else
		copy_file ${TARGET}
	fi
}

function copy_file() {
	f="${1}"

	if [ ! -e "${f}" ]
	then
		echo "WARNING : File not found : ${f}"
		continue
	fi

	[ ! -e ${clst_root_path}/`dirname ${f}` ] && \
		mkdir -p ${clst_root_path}/`dirname ${f}`
	[ ! -e ${clst_root_path}/${f} ] && \
		cp -vfdp ${f} ${clst_root_path}/${f}
	if [ -x ${f} -a ! -h ${f} ]
	then
		copy_libs ${f}
		strip -R .comment -R .note ${clst_root_path}/${f} > /dev/null 2>&1
	elif [ -h ${f} ]
	then
		copy_symlink ${f}
	fi
}

create_handbook_icon() {
	# This function creates a local icon to the Gentoo Handbook
	echo "[Desktop Entry]
Encoding=UTF-8
Version=1.0
Type=Link
URL=file:///mnt/cdrom/docs/handbook/html/index.html
Terminal=false
Name=Gentoo Linux Handbook
GenericName=Gentoo Linux Handbook
Comment=This is a link to the local copy of the Gentoo Linux Handbook.
Icon=text-editor" > /usr/share/applications/gentoo-handbook.desktop
}

# We do this everywhere, so why not put it in this script
run_default_funcs

