module main

import os
import flag
import time

import vcp
import vcp.curlv

// host/nix-channels/
const hosturl = "https://mirrors.ustc.edu.cn"
// const hosturl = "https://mirrors.tuna.tsinghua.edu.cn"
// const chanurl = hosturl+"/nix-channels"
// const pkgsurl = chanurl+"/nixpkgs-24.05-darwin"

struct Nixbase {
	pub mut:
	hosturl string	
}
pub fn (me Nixbase) chanurl() string { return me.hosturl + "/nix-channels/"}
pub fn (me Nixbase) pkgurl() string { return me.chanurl() + "nixpkgs-24.05-darwin/" }
pub fn (me Nixbase) storeurl() string { return me.chanurl() + "store/" }
// 这个文件是什么格式？和 jq 相关，怎么解？
// https://github.com/NixOS/nixpkgs/blob/63c4c8d6d77f80f6bee07672bdcfd8d6180fdd92/pkgs/top-level/make-tarball.nix#L54
// brotli 压缩/解压命令？这是什么格式？？？
pub fn (me Nixbase) pkgjson_url() string { return me.pkgurl() + "packages.json.br" }
pub fn (me Nixbase) store_path_url() string { return me.pkgurl() + "store-paths.xz" }
// 这个文件对应哪个目录？~/.nix-defexpr/channels/nixpkgs/pkgs/
pub fn (me Nixbase) exprurl() string { return me.pkgurl() + "nixexprs.tar.xz" }
// 在store/目录下的包名叫什么？？？
// eg: nix copy -vvv /nix/store/7wpfn219p67x4i00ll2widi9bm2ysa82-pstree-2.39 --to tmpdir/  --impure --no-use-registries --no-update-lock-file --no-write-lock-file --no-recursive --refresh --repair
// 如何得到包的大小？？？需要看nix copy怎么实现的！！！
// 替换 DEPEND 中的库路径
// 查找依赖包
// copy下来的文件不能修改的问题，需要root？

pub fn runcmdv(cmd string, wkdir ... string) []string {
	dir := firstofv(wkdir)
	scc := runcmd(cmd, dir, true)
	return scc.split_into_lines()
}
pub fn runcmd(cmd string, wkdir string, capio bool) string {
	if !cmd.contains("/which ") && cmd != "which" {
	vcp.info("[${cmd}]", "wkdir:", wkdir)
	}
	args := cmdline_split(cmd)
	// vcp.info(args.str())
	cmdfile := cmdfile_reform(args[0])
	// vcp.info(cmdfile, cmd)
	
	mut proc := os.Process{}
	proc.filename = cmdfile
	proc.set_args(args[1..])
	if capio { proc.set_redirect_stdio() }
	if wkdir.len > 0 { proc.set_work_folder(wkdir) }
	proc.run()
	proc.wait()
	defer {proc.close()}

	// vcp.info(proc.code, proc.err, args)
	if capio {
		outstr := proc.stdout_read()
		errstr := proc.stderr_read()
		// vcp.info("`${cmd}`\n", outstr, errstr)
		// vcp.info(proc.stdout_slurp())
		return outstr+errstr
	}
	return ""
}

pub fn cmdline_split(cmd string) []string{
	return cmd.split(" ")
}
pub fn cmdfile_reform(file string) string {
	if os.base(file) == file {
		// line := os.system("which $file") // no capture
		line := runcmd("/usr/bin/which $file", "", true)
		if file != "which" && file != "tar" {
		// vcp.info(file, "=>", line.trim_space())
		}
		return line.trim_space()
	}
	return file
}

@[xdoc: 'My application that does X']
@[footer: 'A footer']
@[version: '1.2.3']
@[name: 'app']
struct Cmdarg {
    show_version bool @[short: v; xdoc: 'Show version and exit']
    debug_level  int  @[long: debug; short: d; xdoc: 'Debug level']
    level        f32  @[only: l; xdoc: 'This doc text is overwritten']
    example      string
    square       bool
    show_help    bool   @[long: help; short: h]
    multi        int    @[only: m; repeats]
    wroom        []int  @[short: w]
    ignore_me    string @[ignore]
}

fn main() {
	// mut fp := flag.new_flag_parser(os.args)
	// fp.string("xxx", 0, "uuu", "eee", flag.FlagConfig{})
	// fp.usage()
	cfg, nomats := flag.to_struct[Cmdarg](os.args, skip:1)!
	vcp.info(nomats.str())
	if cfg.show_help || true {
		doc := flag.to_doc[Cmdarg]()!
		println(doc)
	}
	dump(cfg)

	println('Hello World! ${os.args}, ${nomats}')

	if false {
		lines := runcmdv("ls -l -h")
		for line in lines { vcp.info(line) }
		return
	}

	args := nomats
	pkgname := args[0]

	mut rcvals := []string{}
	mut fp := os.open("store-path-head200")!
	defer {fp.close()}
	
	vcp.info("reading store-path maybe need secs...")
	mut buf := []u8{len:96}
	for i:=0; !fp.eof() ;i++ {
		rn := fp.read_bytes_with_newline(mut &buf) or {
			vcp.error(err.str()); break}
		line := buf[..rn].bytestr().trim_space_right()
		// vcp.info(i, line.len, line, pkgname)
		// vcp.info(i, rn, buf.len, line.len, line)
		if line.len>0 && line.contains(pkgname) && line != "" {
			vcp.info("got???", i, line.len, line)
			rcvals << line
		}
	}
	vcp.info(rcvals.len, rcvals)
	vcp.zeroprt(rcvals.len, "not found", pkgname)
	if rcvals.len==0 {

	}
	for i, line in rcvals {
		vcp.info(i, "\t", line)
	}
	mut ino := 0
	if rcvals.len > 1 {
		ipt := os.input("input the no in [0,${rcvals.len}] > ")
		vcp.info(ipt)
		vcp.zeroprt(ipt, "no input any no")
		if ipt == "" {}
		ino = ipt.int()
	}
	vcp.info("only 1 skip interact selection.")
	time.sleep(time.second)

		if ino >= 0 && ino < rcvals.len {
			// parse line
			hv, pkg, ver := parse_nixstore_line(rcvals[ino])
			vcp.info(hv, pkg, ver)

			nix := Nixbase{hosturl}
			stpurl := nix.storeurl() + rcvals[ino]
			vcp.info("store path full", stpurl)

			runcmd("nix copy ${rcvals[ino]} --to pkgs/ --impure --no-use-registries --no-update-lock-file --no-write-lock-file --no-recursive --refresh --repair -v", ".", false)
			pkgdir := "pkgs/${rcvals[ino]}"
			dotsrcinfo := pkgdir + "/.PKGINFO"
			vcp.info("saved", os.exists(pkgdir), pkgdir)
			if !os.exists(pkgdir){
				vcp.info("wtf 404", pkgdir)
				exit(-1)
			}

			mydir := os.getenv("PWD")
			vcp.info(mydir, pkgdir)
			srcinfo := genpkg_dot_srcinfo(pkg, ver)
			// os.write_file(dotsrcinfo, srcinfo) !
			// os.write_file(".PKGINFO", srcinfo) !
			os.write_file("pkgs/.PKGINFO", srcinfo) !
			// defer {os.rm(".PKGINFO")!}

			// runcmd("tar zcf ${mydir}/test123.tar.gz .", pkgdir, false)
			runcmd("tar cfp ${mydir}/test123.tar .", pkgdir, false)

			// repack so it prefixed with usr/local
			runcmd("mkdir pkgs/usr/local -p", "", false)
			runcmd("tar xf ${mydir}/test123.tar", os.real_path("pkgs/usr/local"), false)
			runcmd("rm -f test123.tar", "", false)
			
			vcp.info("wkdir", os.getenv("PWD"))
			runcmd("sudo chmod 755 -R pkgs/usr", "", false)
			runcmd("fakeroot -- tar zcfp ${mydir}/test123.tar.gz usr/ .PKGINFO", os.real_path( "pkgs/"), false)
			runcmd("tar tf test123.tar.gz", "", false)
			runcmd("ls -lh test123.tar.gz", "", false)

			vcp.info("cleanup pkgs/usr/local/ ...", "", false)
			runcmd("rm -rf pkgs/usr/local", "", false)
			runcmd("sudo rm -rf pkgs/usr/local", "", false)
			runcmd("rm -rf pkgs/nix/store/", "", false)
			runcmd("sudo rm -rf pkgs/nix/store/", "", false)
			runcmd("sudo rm -rf pkgs/nix/var/", "", false)
		}
	// demo()
}

fn parse_nixstore_line(line string) (string, string, string) {
	hv := line.all_before("-")
	pkg := line.all_after("-")
	ver := pkg.all_after_last("-")
	return hv, pkg, ver
}

fn genpkg_dot_srcinfo(pkgname string, pkgver string) string {
	s := "# Generated by makepkg 4.0.3
# using fakeroot version 1.31
# Wed Oct 23 14:41:09 UTC 2024
pkgname = ${pkgname}
pkgver = ${pkgver}-1
pkgdesc = Gives a fake root environment
url = http://packages.debian.org/fakeroot
builddate = 1729694468
packager = Unknown Packager <pacnix@pacnix.org>
size = 307200
arch = x86_64
license = GPL
group = extras
makepkgopt = strip
makepkgopt = docs
makepkgopt = !libtool
makepkgopt = emptydirs
makepkgopt = zipman
makepkgopt = purge
makepkgopt = !upx"
	
	return s
}

fn demo() {
	nix := Nixbase{hosturl}

	mut ch := curlv.new()
	ch.url(nix.pkgurl())
	mut res := ch.get() or { panic(err) }
	vcp.info(res.stcode, res.data.len, ch.redirurl())

	ch.url(nix.storeurl())
	res = ch.get() or { panic(err) }
	vcp.info(res.stcode, res.data.len, ch.redirurl())
}