# -----------------------------------------------------------------------------
# This file is part of the xPack distribution.
#   (https://xpack.github.io)
# Copyright (c) 2020 Liviu Ionescu.
#
# Permission to use, copy, modify, and/or distribute this software
# for any purpose is hereby granted, under the terms of the MIT license.
# -----------------------------------------------------------------------------

# -----------------------------------------------------------------------------

function define_flags_for_target()
{
  local is_nano="n"

  while [ $# -gt 0 ]
  do
    case "$1" in
      --nano )
        is_nano="y"
        ;;

      "" )
        ;;

      * )
        echo "Unsupported argument $1 in ${FUNCNAME[0]}()"
        exit 1
        ;;
    esac
    shift
  done

  local optimize="${XBB_CFLAGS_OPTIMIZATIONS_FOR_TARGET}"
  if [ "${is_nano}" != "y" ]
  then
    # For newlib, optimize for speed.
    optimize="$(echo ${optimize} | sed -e 's/-O[123]/-O2/g')"
    # DO NOT make this explicit, since exceptions references will always be
    # inserted in the `extab` section.
    # optimize+=" -fexceptions"
  else
    # For newlib-nano optimize for size and disable exceptions.
    optimize="$(echo ${optimize} | sed -e 's/-O[123]/-Os/g')"
    optimize="$(echo ${optimize} | sed -e 's/-Ofast/-Os/p')"
    optimize+=" -fno-exceptions"
  fi

  CFLAGS_FOR_TARGET="${optimize}"
  CXXFLAGS_FOR_TARGET="${optimize}"

  if [ "${XBB_IS_DEBUG}" == "y" ]
  then
    # Generally avoid `-g`, many local symbols cannot be removed by strip.
    CFLAGS_FOR_TARGET+=" -g"
    CXXFLAGS_FOR_TARGET+=" -g"
  fi

  # if [ "${XBB_WITH_LIBS_LTO:-}" == "y" ]
  # then
  #   CFLAGS_FOR_TARGET+=" -flto -ffat-lto-objects"
  #   CXXFLAGS_FOR_TARGET+=" -flto -ffat-lto-objects"
  # fi

  LDFLAGS_FOR_TARGET="--specs=nosys.specs"
}

# -----------------------------------------------------------------------------

function download_cross_gcc()
{
  if [ ! -d "${XBB_SOURCES_FOLDER_PATH}/${XBB_GCC_SRC_FOLDER_NAME}" ]
  then
    (
      mkdir -pv "${XBB_SOURCES_FOLDER_PATH}"
      cd "${XBB_SOURCES_FOLDER_PATH}"

      download_and_extract "${XBB_GCC_ARCHIVE_URL}" \
        "${XBB_GCC_ARCHIVE_NAME}" "${XBB_GCC_SRC_FOLDER_NAME}" \
        "${XBB_GCC_PATCH_FILE_NAME}"
    )
  fi
}

# Environment variables:
# XBB_GCC_SRC_FOLDER_NAME
# XBB_GCC_ARCHIVE_URL
# XBB_GCC_ARCHIVE_NAME
# XBB_GCC_PATCH_FILE_NAME

# https://github.com/archlinux/svntogit-community/blob/packages/arm-none-eabi-gcc/trunk/PKGBUILD
# https://github.com/archlinux/svntogit-community/blob/packages/riscv64-elf-gcc/trunk/PKGBUILD

function build_cross_gcc_first()
{
  local gcc_version="$1"
  shift

  local triplet="$1"
  shift

  local name_prefix="${triplet}-"

  local gcc_first_folder_name="${name_prefix}gcc-${gcc_version}-first"

  mkdir -pv "${XBB_LOGS_FOLDER_PATH}/${gcc_first_folder_name}"

  local gcc_first_stamp_file_path="${XBB_STAMPS_FOLDER_PATH}/stamp-${gcc_first_folder_name}-installed"
  if [ ! -f "${gcc_first_stamp_file_path}" ]
  then

    mkdir -pv "${XBB_SOURCES_FOLDER_PATH}"
    cd "${XBB_SOURCES_FOLDER_PATH}"

    download_cross_gcc

    (
      mkdir -pv "${XBB_BUILD_FOLDER_PATH}/${gcc_first_folder_name}"
      cd "${XBB_BUILD_FOLDER_PATH}/${gcc_first_folder_name}"

      xbb_activate_dependencies_dev

      CPPFLAGS="${XBB_CPPFLAGS}"
      CFLAGS="${XBB_CFLAGS_NO_W}"
      CXXFLAGS="${XBB_CXXFLAGS_NO_W}"
      if [ "${XBB_HOST_PLATFORM}" == "win32" ]
      then
        # The CFLAGS are set in XBB_CFLAGS, but for C++ it must be selective.
        # Without it gcc cannot identify cc1 and other binaries
        CXXFLAGS+=" -D__USE_MINGW_ACCESS"
      fi

      LDFLAGS="${XBB_LDFLAGS_APP}"
      xbb_adjust_ldflags_rpath

      define_flags_for_target ""

      export CPPFLAGS
      export CFLAGS
      export CXXFLAGS
      export LDFLAGS

      export CFLAGS_FOR_TARGET
      export CXXFLAGS_FOR_TARGET
      export LDFLAGS_FOR_TARGET

      if [ ! -f "config.status" ]
      then
        (
          xbb_show_env_develop

          echo
          echo "Running cross ${name_prefix}gcc first stage configure..."

          if [ "${XBB_IS_DEVELOP}" == "y" ]
          then
            bash "${XBB_SOURCES_FOLDER_PATH}/${XBB_GCC_SRC_FOLDER_NAME}/configure" --help
          fi

          # 11.2-2022.02-darwin-x86_64-arm-none-eabi-manifest.txt:
          # gcc1_configure='--target=arm-none-eabi
          # --prefix=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/install//
          # --with-gmp=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --with-mpfr=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --with-mpc=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --with-isl=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --disable-shared --disable-nls --disable-threads --disable-tls
          # --enable-checking=release --enable-languages=c --without-cloog
          # --without-isl --with-newlib --without-headers
          # --with-multilib-list=aprofile,rmprofile'

          # 11.2-2022.02-darwin-x86_64-aarch64-none-elf-manifest.txt
          # gcc1_configure='--target=aarch64-none-elf
          # --prefix=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/install//
          # --with-gmp=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/host-tools
          # --with-mpfr=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/host-tools
          # --with-mpc=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/host-tools
          # --with-isl=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/host-tools
          # --disable-shared --disable-nls --disable-threads --disable-tls
          # --enable-checking=release --enable-languages=c --without-cloog
          # --without-isl --with-newlib --without-headers'

          # From: https://gcc.gnu.org/install/configure.html
          # --enable-shared[=package[,…]] build shared versions of libraries
          # --enable-tls specify that the target supports TLS (Thread Local Storage).
          # --enable-nls enables Native Language Support (NLS)
          # --enable-checking=list the compiler is built to perform internal consistency checks of the requested complexity. ‘yes’ (most common checks)
          # --with-headers=dir specify that target headers are available when building a cross compiler
          # --with-newlib Specifies that ‘newlib’ is being used as the target C library. This causes `__eprintf`` to be omitted from `libgcc.a`` on the assumption that it will be provided by newlib.
          # --enable-languages=c newlib does not use C++, so C should be enough

          # --enable-checking=no ???

          # --enable-lto make it explicit, Arm uses the default.

          # Prefer an explicit libexec folder.
          # --libexecdir="${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/lib"

          config_options=()

          config_options+=("--prefix=${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}")

          config_options+=("--infodir=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}/share/info")
          config_options+=("--mandir=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}/share/man")
          config_options+=("--htmldir=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}/share/html")
          config_options+=("--pdfdir=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}/share/pdf")

          config_options+=("--build=${XBB_BUILD_TRIPLET}")
          config_options+=("--host=${XBB_HOST_TRIPLET}")
          config_options+=("--target=${triplet}")

          config_options+=("--disable-libgomp") # ABE
          config_options+=("--disable-libmudflap") # ABE
          config_options+=("--disable-libquadmath") # ABE
          config_options+=("--disable-libsanitizer") # ABE
          config_options+=("--disable-libssp") # ABE

          config_options+=("--disable-nls") # Arm, AArch64
          config_options+=("--disable-shared") # Arm, AArch64
          config_options+=("--disable-threads") # Arm, AArch64
          config_options+=("--disable-tls") # Arm, AArch64

          config_options+=("--enable-checking=release") # Arm, AArch64
          config_options+=("--enable-languages=c") # Arm, AArch64
          # config_options+=("--enable-lto") # ABE

          config_options+=("--without-cloog") # Arm, AArch64
          config_options+=("--without-headers") # Arm, AArch64
          config_options+=("--without-isl") # Arm, AArch64

          config_options+=("--with-gnu-as") # Arm, ABE
          config_options+=("--with-gnu-ld") # Arm, ABE

          config_options+=("--with-gmp=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}") # AArch64
          config_options+=("--with-pkgversion=${XBB_BRANDING}")
          config_options+=("--with-newlib") # Arm, AArch64

          # Use the zlib compiled from sources.
          config_options+=("--with-system-zlib")

          if [ "${triplet}" == "arm-none-eabi" ]
          then
            config_options+=("--disable-libatomic") # ABE

            if [ "${XBB_WITHOUT_MULTILIB}" == "y" ]
            then
              config_options+=("--disable-multilib")
            else
              config_options+=("--enable-multilib") # Arm
              config_options+=("--with-multilib-list=${XBB_GCC_MULTILIB_LIST}")  # Arm
            fi
          elif [ "${triplet}" == "riscv-none-elf" ]
          then
            config_options+=("--with-abi=${XBB_GCC_ABI}")
            config_options+=("--with-arch=${XBB_GCC_ARCH}")

            if [ "${XBB_WITHOUT_MULTILIB}" == "y" ]
            then
              config_options+=("--disable-multilib")
            else
              config_options+=("--enable-multilib")
            fi
          fi

          run_verbose bash ${DEBUG} "${XBB_SOURCES_FOLDER_PATH}/${XBB_GCC_SRC_FOLDER_NAME}/configure" \
            "${config_options[@]}"

          cp "config.log" "${XBB_LOGS_FOLDER_PATH}/${gcc_first_folder_name}/config-log-$(ndate).txt"
        ) 2>&1 | tee "${XBB_LOGS_FOLDER_PATH}/${gcc_first_folder_name}/configure-output-$(ndate).txt"
      fi

      (
        # Partial build, without documentation.
        echo
        echo "Running cross ${name_prefix}gcc first stage make..."

        # No need to make 'all', 'all-gcc' is enough to compile the libraries.
        # Parallel builds may fail.
        run_verbose make -j ${XBB_JOBS} all-gcc
        # make all-gcc

        # No -strip available here.
        run_verbose make install-gcc

        # Strip?

      ) 2>&1 | tee "${XBB_LOGS_FOLDER_PATH}/${gcc_first_folder_name}/make-output-$(ndate).txt"
    )

    mkdir -pv "${XBB_STAMPS_FOLDER_PATH}"
    touch "${gcc_first_stamp_file_path}"

  else
    echo "Component cross ${name_prefix}gcc first stage already installed"
  fi
}

# -----------------------------------------------------------------------------

function cross_gcc_copy_linux_libs()
{
  local triplet="$1"

  local copy_linux_stamp_file_path="${XBB_STAMPS_FOLDER_PATH}/stamp-copy-linux-libs-completed"
  if [ ! -f "${copy_linux_stamp_file_path}" ]
  then

    local linux_path="${XBB_NATIVE_DEPENDENCIES_INSTALL_FOLDER_PATH}"

    (
      cd "${XBB_TARGET_WORK_FOLDER_PATH}"

      copy_dir "${linux_path}/${triplet}/lib" "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/${triplet}/lib"
      copy_dir "${linux_path}/${triplet}/include" "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/${triplet}/include"

      copy_dir "${linux_path}/include" "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/include"
      copy_dir "${linux_path}/lib" "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/lib"
      copy_dir "${linux_path}/share" "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/share"
    )

    (
      cd "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}"
      find "${triplet}/lib" "${triplet}/include" "include" "lib" "share" \
        -perm /111 -and ! -type d \
        -exec rm '{}' ';'
    )

    mkdir -pv "${XBB_STAMPS_FOLDER_PATH}"
    touch "${copy_linux_stamp_file_path}"

  else
    echo "Component copy-linux-libs already processed"
  fi
}

# -----------------------------------------------------------------------------

function cross_gcc_add_linux_install_path()
{
  local triplet="$1"

  # Verify that the compiler is there.
  "${XBB_LINUX_WORK_FOLDER_PATH}/bin/${triplet}-gcc" --version

  export PATH="${XBB_LINUX_WORK_FOLDER_PATH}/bin:${PATH}"
  echo "PATH=${PATH}"
}

# Environment variables:
# XBB_GCC_SRC_FOLDER_NAME
# XBB_GCC_ARCHIVE_URL
# XBB_GCC_ARCHIVE_NAME
# XBB_GCC_PATCH_FILE_NAME

function build_cross_gcc_final()
{
  local gcc_version="$1"
  shift

  local triplet="$1"
  shift

  local name_prefix="${triplet}-"

  local name_suffix=""
  local is_nano="n"
  local nano_option=""

  while [ $# -gt 0 ]
  do
    case "$1" in
      --nano )
        is_nano="y"
        nano_option="--nano"
        name_suffix="-nano"
        ;;

      * )
        echo "Unsupported argument $1 in ${FUNCNAME[0]}()"
        exit 1
        ;;
    esac
    shift
  done

  local gcc_final_folder_name="${name_prefix}gcc-${gcc_version}-final${name_suffix}"

  mkdir -pv "${XBB_LOGS_FOLDER_PATH}/${gcc_final_folder_name}"

  local gcc_final_stamp_file_path="${XBB_STAMPS_FOLDER_PATH}/stamp-${gcc_final_folder_name}-installed"
  if [ ! -f "${gcc_final_stamp_file_path}" ]
  then

    mkdir -pv "${XBB_SOURCES_FOLDER_PATH}"
    cd "${XBB_SOURCES_FOLDER_PATH}"

    download_cross_gcc

    (
      mkdir -pv "${XBB_BUILD_FOLDER_PATH}/${gcc_final_folder_name}"
      cd "${XBB_BUILD_FOLDER_PATH}/${gcc_final_folder_name}"

      xbb_activate_dependencies_dev

      CPPFLAGS="${XBB_CPPFLAGS}"
      # if [ "${XBB_HOST_PLATFORM}" == "darwin" ]
      # then
      #   # Hack to avoid spurious errors like:
      #   # fatal error: bits/nested_exception.h: No such file or directory
      #   CPPFLAGS+=" -I${XBB_BUILD_FOLDER_PATH}/${gcc_final_folder_name}/${triplet}/libstdc++-v3/include"
      # fi
      CFLAGS="${XBB_CFLAGS_NO_W}"
      CXXFLAGS="${XBB_CXXFLAGS_NO_W}"
      if [ "${XBB_HOST_PLATFORM}" == "win32" ]
      then
        # The CFLAGS are set in XBB_CFLAGS, but for C++ it must be selective.
        # Without it gcc cannot identify cc1 and other binaries
        CXXFLAGS+=" -D__USE_MINGW_ACCESS"

        # Hack to prevent "too many sections", "File too big" etc in insn-emit.c
        CXXFLAGS=$(echo ${CXXFLAGS} | sed -e 's|-ffunction-sections -fdata-sections||')
      fi

      LDFLAGS="${XBB_LDFLAGS_APP}"
      xbb_adjust_ldflags_rpath
      # Do not add CRT_glob.o here, it will fail with already defined,
      # since it is already handled by --enable-mingw-wildcard.

      define_flags_for_target "${nano_option}"

      export CPPFLAGS
      export CFLAGS
      export CXXFLAGS
      export LDFLAGS

      export CFLAGS_FOR_TARGET
      export CXXFLAGS_FOR_TARGET
      export LDFLAGS_FOR_TARGET

      if [ "${XBB_HOST_PLATFORM}" == "win32" ]
      then
        add_cross_linux_install_path "${triplet}"

        export AR_FOR_TARGET="$(which ${name_prefix}ar)"
        export NM_FOR_TARGET="$(which ${name_prefix}nm)"
        export OBJDUMP_FOR_TARET="$(which ${name_prefix}objdump)"
        export STRIP_FOR_TARGET="$(which ${name_prefix}strip)"
        export CC_FOR_TARGET="$(which ${name_prefix}gcc)"
        export GCC_FOR_TARGET="$(which ${name_prefix}gcc)"
        export CXX_FOR_TARGET="$(which ${name_prefix}g++)"
      fi

      if [ ! -f "config.status" ]
      then
        (
          xbb_show_env_develop

          echo
          echo "Running cross ${name_prefix}gcc${name_suffix} final stage configure..."

          if [ "${XBB_IS_DEVELOP}" == "y" ]
          then
            bash "${XBB_SOURCES_FOLDER_PATH}/${XBB_GCC_SRC_FOLDER_NAME}/configure" --help
          fi

          # https://gcc.gnu.org/install/configure.html
          # --enable-shared[=package[,…]] build shared versions of libraries
          # --enable-tls specify that the target supports TLS (Thread Local Storage).
          # --enable-nls enables Native Language Support (NLS)
          # --enable-checking=list the compiler is built to perform internal consistency checks of the requested complexity. ‘yes’ (most common checks)
          # --with-headers=dir specify that target headers are available when building a cross compiler
          # --with-newlib Specifies that ‘newlib’ is being used as the target C library. This causes `__eprintf`` to be omitted from `libgcc.a`` on the assumption that it will be provided by newlib.
          # --enable-languages=c,c++ Support only C/C++, ignore all other.

          # Prefer an explicit libexec folder.
          # --libexecdir="${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/lib" \

          # --enable-lto make it explicit, Arm uses the default.
          # --with-native-system-header-dir is needed to locate stdio.h, to
          # prevent -Dinhibit_libc, which will skip some functionality,
          # like libgcov.

          config_options=()

          config_options+=("--prefix=${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}")

          config_options+=("--infodir=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}/share/info")
          config_options+=("--mandir=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}/share/man")
          config_options+=("--htmldir=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}/share/html")
          config_options+=("--pdfdir=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}/share/pdf")

          config_options+=("--build=${XBB_BUILD_TRIPLET}")
          config_options+=("--host=${XBB_HOST_TRIPLET}")
          config_options+=("--target=${triplet}")

          config_options+=("--disable-libgomp") # ABE
          config_options+=("--disable-libmudflap") # ABE
          config_options+=("--disable-libquadmath") # ABE
          config_options+=("--disable-libsanitizer") # ABE
          config_options+=("--disable-libssp") # ABE

          config_options+=("--disable-nls") # Arm, AArch64
          config_options+=("--disable-shared") # Arm, AArch64
          config_options+=("--disable-threads") # Arm, AArch64
          config_options+=("--disable-tls") # Arm, AArch64

          config_options+=("--enable-checking=release") # Arm, AArch64
          config_options+=("--enable-languages=c,c++,fortran") # Arm, AArch64

          if [ "${XBB_HOST_PLATFORM}" == "win32" ]
          then
            config_options+=("--enable-mingw-wildcard")
          fi

          config_options+=("--with-gmp=${XBB_LIBRARIES_INSTALL_FOLDER_PATH}") # AArch64

          config_options+=("--with-newlib") # Arm, AArch64
          config_options+=("--with-pkgversion=${XBB_BRANDING}")

          config_options+=("--with-gnu-as") # Arm ABE
          config_options+=("--with-gnu-ld") # Arm ABE

          # Use the zlib compiled from sources.
          config_options+=("--with-system-zlib")

          # `${with_sysroot}${native_system_header_dir}/stdio.h`
          # is checked for presence; if not present `inhibit_libc=true` and
          # libgcov.a is compiled with empty functions.
          # https://github.com/xpack-dev-tools/arm-none-eabi-gcc-xpack/issues/1
          config_options+=("--with-sysroot=${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/${triplet}")
          config_options+=("--with-native-system-header-dir=/include")

          if [ "${triplet}" == "arm-none-eabi" ]
          then
            config_options+=("--disable-libatomic") # ABE

            if [ "${XBB_WITHOUT_MULTILIB}" == "y" ]
            then
              config_options+=("--disable-multilib")
            else
              config_options+=("--enable-multilib") # Arm
              config_options+=("--with-multilib-list=${XBB_GCC_MULTILIB_LIST}")  # Arm
            fi
          elif [ "${triplet}" == "riscv-none-elf" ]
          then
            config_options+=("--with-abi=${XBB_GCC_ABI}")
            config_options+=("--with-arch=${XBB_GCC_ARCH}")

            if [ "${XBB_WITHOUT_MULTILIB}" == "y" ]
            then
              config_options+=("--disable-multilib")
            else
              config_options+=("--enable-multilib")
            fi
          fi

          # 11.2-2022.02-darwin-x86_64-arm-none-eabi-manifest.txt:
          # gcc2_configure='--target=arm-none-eabi
          # --prefix=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/install//
          # --with-gmp=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --with-mpfr=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --with-mpc=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --with-isl=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --disable-shared --disable-nls --disable-threads --disable-tls
          # --enable-checking=release --enable-languages=c,c++,fortran
          # --with-newlib --with-multilib-list=aprofile,rmprofile'

          # 11.2-2022.02-darwin-x86_64-aarch64-none-elf-manifest.txt
          # gcc2_configure='--target=aarch64-none-elf
          # --prefix=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/install//
          # --with-gmp=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/host-tools
          # --with-mpfr=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/host-tools
          # --with-mpc=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/host-tools
          # --with-isl=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-aarch64-none-elf/host-tools
          # --disable-shared --disable-nls --disable-threads --disable-tls
          # --enable-checking=release --enable-languages=c,c++,fortran
          # --with-newlib 			 			 			'

          # 11.2-2022.02-darwin-x86_64-arm-none-eabi-manifest.txt:
          # gcc2_nano_configure='--target=arm-none-eabi
          # --prefix=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/nano_install//
          # --with-gmp=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --with-mpfr=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --with-mpc=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --with-isl=/Volumes/data/jenkins/workspace/GNU-toolchain/arm-11/build-arm-none-eabi/host-tools
          # --disable-shared --disable-nls --disable-threads --disable-tls
          # --enable-checking=release --enable-languages=c,c++,fortran
          # --with-newlib --with-multilib-list=aprofile,rmprofile'

          run_verbose bash ${DEBUG} "${XBB_SOURCES_FOLDER_PATH}/${XBB_GCC_SRC_FOLDER_NAME}/configure" \
            "${config_options[@]}"

          cp "config.log" "${XBB_LOGS_FOLDER_PATH}/${gcc_final_folder_name}/config-log-$(ndate).txt"
        ) 2>&1 | tee "${XBB_LOGS_FOLDER_PATH}/${gcc_final_folder_name}/configure-output-$(ndate).txt"
      fi

      (
        # Partial build, without documentation.
        echo
        echo "Running cross ${name_prefix}gcc${name_suffix} final stage make..."

        if [ "${XBB_HOST_PLATFORM}" != "win32" ]
        then

          # Passing USE_TM_CLONE_REGISTRY=0 via INHIBIT_LIBC_CFLAGS to disable
          # transactional memory related code in crtbegin.o.
          # This is a workaround. Better approach is have a t-* to set this flag via
          # CRTSTUFF_T_CFLAGS

          if [ "${XBB_HOST_PLATFORM}" == "darwin" ]
          then
            if [ "${XBB_IS_DEVELOP}" == "y" ]
            then
              run_verbose make -j ${XBB_JOBS} INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
            else
              # Retry, parallel builds do fail, headers are probably
              # used before being installed. For example:
              # fatal error: bits/string_view.tcc: No such file or directory
              run_verbose make -j ${XBB_JOBS} INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0" \
              || run_verbose make -j ${XBB_JOBS} INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0" \
              || run_verbose make -j ${XBB_JOBS} INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0" \
              || run_verbose make -j ${XBB_JOBS} INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
            fi
          else
            run_verbose make -j ${XBB_JOBS} INHIBIT_LIBC_CFLAGS="-DUSE_TM_CLONE_REGISTRY=0"
          fi

          # Avoid strip here, it may interfere with patchelf.
          # make install-strip
          run_verbose make install

          # if [ "${is_nano}" == "y" ]
          # then
          #   cross_copy_nono_libs "${name_prefix}"
          # fi

        else

          # For Windows build only the GCC binaries, the libraries were copied
          # from the Linux build.
          # Parallel builds may fail.
          run_verbose make -j ${XBB_JOBS} all-gcc
          # make all-gcc

          # No -strip here.
          run_verbose make install-gcc

          # Strip?

        fi

      ) 2>&1 | tee "${XBB_LOGS_FOLDER_PATH}/${gcc_final_folder_name}/make-output-$(ndate).txt"

      copy_license \
        "${XBB_SOURCES_FOLDER_PATH}/${XBB_GCC_SRC_FOLDER_NAME}" \
        "gcc-${gcc_version}"

    )

    mkdir -pv "${XBB_STAMPS_FOLDER_PATH}"
    touch "${gcc_final_stamp_file_path}"

  else
    echo "Component cross ${name_prefix}gcc${name_suffix} final stage already installed"
  fi

  if [ "${is_nano}" != "y" ]
  then
    tests_add "test_cross_gcc" "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/bin" "${triplet}"
  fi
}

function test_cross_gcc()
{
  local test_bin_path="$1"
  local triplet="$2"

  (
    CC="${test_bin_path}/${triplet}-gcc${XBB_HOST_DOT_EXE}"
    CXX="${test_bin_path}/${triplet}-g++${XBB_HOST_DOT_EXE}"

    echo
    echo "Checking the ${triplet}-gcc shared libraries..."

    show_host_libs "${CC}"
    show_host_libs "${CXX}"

    if [ "${XBB_HOST_PLATFORM}" != "win32" ]
    then
      show_host_libs "$(${CC} -print-prog-name=cc1)"
      show_host_libs "$(${CC} -print-prog-name=cc1plus)"
      show_host_libs "$(${CC} -print-prog-name=collect2)"
      show_host_libs "$(${CC} -print-prog-name=lto-wrapper)"
      show_host_libs "$(${CC} -print-prog-name=lto1)"
    fi

    echo
    echo "Testing the ${triplet}-gcc configuration..."

    run_host_app_verbose "${CC}" --help
    run_host_app_verbose "${CC}" -v
    run_host_app_verbose "${CC}" -dumpversion
    run_host_app_verbose "${CC}" -dumpmachine

    run_host_app_verbose "${CC}" -print-search-dirs
    run_host_app_verbose "${CC}" -print-libgcc-file-name
    run_host_app_verbose "${CC}" -print-multi-directory
    run_host_app_verbose "${CC}" -print-multi-lib
    run_host_app_verbose "${CC}" -print-multi-os-directory
    run_host_app_verbose "${CC}" -print-sysroot

    echo
    echo "Testing if ${triplet}-gcc compiles simple programs..."

    rm -rf "${XBB_TESTS_FOLDER_PATH}/${triplet}-gcc"
    mkdir -pv "${XBB_TESTS_FOLDER_PATH}/${triplet}-gcc"
    cd "${XBB_TESTS_FOLDER_PATH}/${triplet}-gcc"

    echo
    echo "pwd: $(pwd)"

    # -------------------------------------------------------------------------

    if false # [ "${XBB_HOST_PLATFORM}" == "win32" ] && [ -z ${IS_NATIVE_TEST+x} ]
    then
      : # Skip Windows when non native (running on Wine).
    else

      if [ "${triplet}" == "arm-none-eabi" ]
      then
        specs="-specs=rdimon.specs"
      elif [ "${triplet}" == "aarch64-none-elf" ]
      then
        specs="-specs=rdimon.specs"
      elif [ "${triplet}" == "riscv-none-elf" ]
      then
        specs="-specs=semihost.specs"
      else
        specs="-specs=nosys.specs"
      fi

      # Note: __EOF__ is quoted to prevent substitutions here.
      cat <<'__EOF__' > hello.c
#include <stdio.h>

int
main(int argc, char* argv[])
{
  printf("Hello World\n");
}
__EOF__

      run_host_app_verbose "${CC}" -pipe -o hello-c.elf "${specs}" hello.c -v

      run_host_app_verbose "${CC}" -pipe -o hello.c.o -c -flto hello.c
      run_host_app_verbose "${CC}" -pipe -o hello-c-lto.elf "${specs}" -flto -v hello.c.o

      # Note: __EOF__ is quoted to prevent substitutions here.
      cat <<'__EOF__' > hello.cpp
#include <iostream>

int
main(int argc, char* argv[])
{
  std::cout << "Hello World" << std::endl;
}

extern "C" void __sync_synchronize();

void
__sync_synchronize()
{
}
__EOF__

      run_host_app_verbose "${CXX}" -pipe -o hello-cpp.elf "${specs}" hello.cpp

      run_host_app_verbose "${CXX}" -pipe -o hello.cpp.o -c -flto hello.cpp
      run_host_app_verbose "${CXX}" -pipe -o hello-cpp-lto.elf "${specs}" -flto -v hello.cpp.o

      run_host_app_verbose "${CXX}" -pipe -o hello-cpp-gcov.elf "${specs}" -fprofile-arcs -ftest-coverage -lgcov hello.cpp
    fi
  )
}

# -----------------------------------------------------------------------------

function cross_gcc_copy_nano_multilibs()
{
  local triplet="$1"

  echo
  echo "# Copying newlib${XBB_NEWLIB_NANO_SUFFIX} libraries..."

  # local name_prefix="${triplet}-"

  # if [ "${XBB_HOST_PLATFORM}" == "win32" ]
  # then
  #   target_gcc="${triplet}-gcc"
  # else
  #   if [ -x "${APP_PREFIX_NANO}/bin/${name_prefix}gcc" ]
  #   then
  #     target_gcc="${APP_PREFIX_NANO}/bin/${name_prefix}gcc"
  #   # elif [ -x "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/bin/${name_prefix}gcc" ]
  #   # then
  #   #   target_gcc="${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/bin/${name_prefix}gcc"
  #   else
  #     echo "No ${name_prefix}gcc --print-multi-lib"
  #     exit 1
  #   fi
  # fi

  # Copy the libraries after appending the `_nano` suffix.
  # Iterate through all multilib names.
  local src_folder="${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}${XBB_NEWLIB_NANO_SUFFIX}/${triplet}/lib" \
  local dst_folder="${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/${triplet}/lib" \
  local target_gcc="${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}${XBB_NEWLIB_NANO_SUFFIX}/bin/${triplet}-gcc"

  echo ${target_gcc}
  multilibs=( $("${target_gcc}" -print-multi-lib 2>/dev/null) )
  if [ ${#multilibs[@]} -gt 0 ]
  then
    for multilib in "${multilibs[@]}"
    do
      multi_folder="${multilib%%;*}"
      cross_newlib_copy_nano_libs "${src_folder}/${multi_folder}" \
        "${dst_folder}/${multi_folder}"
    done
  else
    cross_newlib_copy_nano_libs "${src_folder}" "${dst_folder}"
  fi

  # Copy the nano configured newlib.h file into the location that nano.specs
  # expects it to be.
  mkdir -pv "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/${triplet}/include/newlib${XBB_NEWLIB_NANO_SUFFIX}"
  cp -v -f "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}${XBB_NEWLIB_NANO_SUFFIX}/${triplet}/include/newlib.h" \
    "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/${triplet}/include/newlib${XBB_NEWLIB_NANO_SUFFIX}/newlib.h"
}

function cross_gcc_tidy_up()
{
  (
    echo
    echo "# Tidying up..."

    # find: pred.c:1932: launch: Assertion `starting_desc >= 0' failed.
    cd "${XBB_APPLICATION_INSTALL_FOLDER_PATH}"

    find "${XBB_APPLICATION_INSTALL_FOLDER_PATH}" -name "libiberty.a" -exec rm -v '{}' ';'
    find "${XBB_APPLICATION_INSTALL_FOLDER_PATH}" -name '*.la' -exec rm -v '{}' ';'

    if [ "${XBB_HOST_PLATFORM}" == "win32" ]
    then
      find "${XBB_APPLICATION_INSTALL_FOLDER_PATH}" -name "liblto_plugin.a" -exec rm -v '{}' ';'
      find "${XBB_APPLICATION_INSTALL_FOLDER_PATH}" -name "liblto_plugin.dll.a" -exec rm -v '{}' ';'
    fi
  )
}

function cross_gcc_strip_libs()
{
  local triplet="$1"

  if [ "${XBB_WITH_STRIP}" == "y" ]
  then
    (
      # TODO!?
      # PATH="${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/bin:${PATH}"

      echo
      echo "# Stripping libraries..."

      cd "${XBB_TARGET_WORK_FOLDER_PATH}"

      # which "${triplet}-objcopy"

      local libs=$(find "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/${triplet}/lib" "${XBB_EXECUTABLES_INSTALL_FOLDER_PATH}/lib/gcc" -name '*.[ao]')
      for lib in ${libs}
      do
        if false
        then
          echo "${triplet}-objcopy -R ... ${lib}"
          "${XBB_APPLICATION_INSTALL_FOLDER_PATH}/bin/${triplet}-objcopy" -R .comment -R .note -R .debug_info -R .debug_aranges -R .debug_pubnames -R .debug_pubtypes -R .debug_abbrev -R .debug_line -R .debug_str -R .debug_ranges -R .debug_loc "${lib}" || true
        else
          echo "[${XBB_APPLICATION_INSTALL_FOLDER_PATH}/bin/${triplet}-strip --strip-debug ${lib}]"
          "${XBB_APPLICATION_INSTALL_FOLDER_PATH}/bin/${triplet}-strip" --strip-debug "${lib}"
        fi
      done
    )
  fi
}

function cross_gcc_final_tunings()
{
  # Create the missing LTO plugin links.
  # For `ar` to work with LTO objects, it needs the plugin in lib/bfd-plugins,
  # but the build leaves it where `ld` needs it. On POSIX, make a soft link.
  if [ "${XBB_FIX_LTO_PLUGIN:-}" == "y" ]
  then
    (
      cd "${XBB_APPLICATION_INSTALL_FOLDER_PATH}"

      echo
      if [ "${XBB_HOST_PLATFORM}" == "win32" ]
      then
        echo
        echo "Copying ${XBB_LTO_PLUGIN_ORIGINAL_NAME}..."

        mkdir -pv "$(dirname ${XBB_LTO_PLUGIN_BFD_PATH})"

        if [ ! -f "${XBB_LTO_PLUGIN_BFD_PATH}" ]
        then
          local plugin_path="$(find * -type f -name ${XBB_LTO_PLUGIN_ORIGINAL_NAME})"
          if [ ! -z "${plugin_path}" ]
          then
            cp -v "${plugin_path}" "${XBB_LTO_PLUGIN_BFD_PATH}"
          else
            echo "${XBB_LTO_PLUGIN_ORIGINAL_NAME} not found"
            exit 1
          fi
        fi
      else
        echo
        echo "Creating ${XBB_LTO_PLUGIN_ORIGINAL_NAME} link..."

        mkdir -pv "$(dirname ${XBB_LTO_PLUGIN_BFD_PATH})"
        if [ ! -f "${XBB_LTO_PLUGIN_BFD_PATH}" ]
        then
          local plugin_path="$(find * -type f -name ${XBB_LTO_PLUGIN_ORIGINAL_NAME})"
          if [ ! -z "${plugin_path}" ]
          then
            ln -s -v "../../${plugin_path}" "${XBB_LTO_PLUGIN_BFD_PATH}"
          else
            echo "${XBB_LTO_PLUGIN_ORIGINAL_NAME} not found"
            exit 1
          fi
        fi
      fi
    )
  fi
}

# -----------------------------------------------------------------------------
