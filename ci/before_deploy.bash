#!/usr/bin/env bash
# Building and packaging for release

set -ex

build() {
    cargo build --target "$TARGET" --release --verbose
    cargo test --all --release
    cargo doc --all --release
}

pack() {
    mkdir -p pfiles
    if [[ "$TRAVIS_OS_NAME" == 'windows' ]]; then
        cp "target/$TARGET/release/${PROJECT_NAME}.exe" "pfiles/${PROJECT_NAME}-${TRAVIS_TAG}-${EXE}.exe"
    else
        strip "target/$TARGET/release/${PROJECT_NAME}"
        cp "target/$TARGET/release/${PROJECT_NAME}" "pfiles/${PROJECT_NAME}-${TRAVIS_TAG}-${EXE}"
    fi
}

packOld() {
    local tempdir
    local out_dir
    local package_name
    local gcc_prefix

    tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t tmp)
    out_dir=$(pwd)
    package_name="$PROJECT_NAME-$TRAVIS_TAG-$TARGET"

    if [[ $TARGET == "arm-unknown-linux-gnueabihf" ]]; then
        gcc_prefix="arm-linux-gnueabihf-"
    else
        gcc_prefix=""
    fi

    # create a "staging" directory
    mkdir "$tempdir/$package_name"
    mkdir "$tempdir/$package_name/autocomplete"

    # copying the main binary
    cp "target/$TARGET/release/$PROJECT_NAME" "$tempdir/$package_name/"
    "${gcc_prefix}"strip "$tempdir/$package_name/$PROJECT_NAME"

    # manpage, readme and license
    cp "doc/$PROJECT_NAME.1" "$tempdir/$package_name"
    cp README.md "$tempdir/$package_name"
    cp LICENSE-MIT "$tempdir/$package_name"
    cp LICENSE-APACHE "$tempdir/$package_name"

    # various autocomplete
    cp target/"$TARGET"/release/build/"$PROJECT_NAME"-*/out/"$PROJECT_NAME".bash "$tempdir/$package_name/autocomplete/${PROJECT_NAME}.bash-completion"
    cp target/"$TARGET"/release/build/"$PROJECT_NAME"-*/out/"$PROJECT_NAME".fish "$tempdir/$package_name/autocomplete"
    cp target/"$TARGET"/release/build/"$PROJECT_NAME"-*/out/_"$PROJECT_NAME" "$tempdir/$package_name/autocomplete"

    # archiving
    pushd "$tempdir"
    tar czf "$out_dir/$package_name.tar.gz" "$package_name"/*
    popd
    rm -r "$tempdir"
}

make_deb() {
    local tempdir
    local architecture
    local version
    local dpkgname
    local conflictname

    case $TARGET in
        x86_64*)
            architecture=amd64
            ;;
        i686*)
            architecture=i386
            ;;
        *)
            echo "make_deb: skipping target '${TARGET}'" >&2
            return 0
            ;;
    esac
    version=${TRAVIS_TAG#v}
    if [[ $TARGET = *musl* ]]; then
      dpkgname=$PROJECT_NAME-musl
      conflictname=$PROJECT_NAME
    else
      dpkgname=$PROJECT_NAME
      conflictname=$PROJECT_NAME-musl
    fi

    tempdir=$(mktemp -d 2>/dev/null || mktemp -d -t tmp)

    # copy the main binary
    install -Dm755 "target/$TARGET/release/$PROJECT_NAME" "$tempdir/usr/bin/$PROJECT_NAME"
    strip "$tempdir/usr/bin/$PROJECT_NAME"

    # manpage
    install -Dm644 "doc/$PROJECT_NAME.1" "$tempdir/usr/share/man/man1/$PROJECT_NAME.1"
    gzip --best "$tempdir/usr/share/man/man1/$PROJECT_NAME.1"

    # readme and license
    install -Dm644 README.md "$tempdir/usr/share/doc/$PROJECT_NAME/README.md"
    install -Dm644 LICENSE-MIT "$tempdir/usr/share/doc/$PROJECT_NAME/LICENSE-MIT"
    install -Dm644 LICENSE-APACHE "$tempdir/usr/share/doc/$PROJECT_NAME/LICENSE-APACHE"

    # completions
    install -Dm644 target/$TARGET/release/build/$PROJECT_NAME-*/out/$PROJECT_NAME.bash "$tempdir/usr/share/bash-completion/completions/${PROJECT_NAME}"
    install -Dm644 target/$TARGET/release/build/$PROJECT_NAME-*/out/$PROJECT_NAME.fish "$tempdir/usr/share/fish/completions/$PROJECT_NAME.fish"
    install -Dm644 target/$TARGET/release/build/$PROJECT_NAME-*/out/_$PROJECT_NAME "$tempdir/usr/share/zsh/vendor-completions/_$PROJECT_NAME"

    # Control file
    mkdir "$tempdir/DEBIAN"
    cat > "$tempdir/DEBIAN/control" <<EOF
Package: $dpkgname
Version: $version
Section: utils
Priority: optional
Maintainer: Adam Lesperance <lespea@gmail.com>
Architecture: $architecture
Provides: $PROJECT_NAME
Conflicts: $conflictname
Description: Dumps the fseventsd entries from a mac
EOF

    fakeroot dpkg-deb --build "$tempdir" "${dpkgname}_${version}_${architecture}.deb"
}


main() {
    build
    pack
    #if [[ $TARGET = *linux* ]]; then
      #make_deb
    #fi
}

main
