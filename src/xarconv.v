module main

import os

import vcp

// (x)ar <=> (y)ar
// .tar, .gz, .bz2, .xz, .7z, .zip, .rar, .nar, .ar, .zstd, .deb, .rpm, .dmg, .pkg, .AppImage, .snap, .img
// depends: https://github.com/AppImage/AppImageKit
pub fn xarconv(dst string) {

}

pub fn appimginfo(file string) string {
	mut rets := []string{}
	filetype, ok := vcp.runcmd('file "${file}"', "", true)
	rets << "-: filetype: " + filetype.trim_space()
	rets << "-: filesize: " + os.file_size(file).str()
	// help, extract, mount
	args := ["version", "offset", "signature", "updateinfo"]
	for idx, arg in args {
		cmd := '"${file}" --appimage-${arg}'
		res, ok := vcp.runcmd(cmd, "", true, true)
		rets << "${idx}: ${arg}: ${res}"
	}
	
	return rets.join("\n")
}

pub fn appimg2tar(file string, dst string) IError {
	// cd temp && --appimage-extract
	return IError(vnil)
}