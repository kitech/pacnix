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

// todo pipe out or hang somewhere when too many out
pub fn runcmd(cmd string, wkdir string, capio bool) string {
	if !cmd.contains("/which ") && cmd != "which" {
		// vcp.info("[${cmd}]", "wkdir:", wkdir)
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
	mut outbuf := ""
	mut errbuf := ""
	if capio {
		mut toobig := false
		for proc.is_alive() {
			outstr := proc.pipe_read(.stdout) or {
				// vcp.error(err.str())
				""}
			if !toobig { outbuf += outstr }
			// vcp.info("out", outstr.len, outbuf.len)
			errstr := proc.pipe_read(.stderr) or {
				// vcp.error(err.str())
				"" }
			if !toobig { errbuf += errstr }
			// vcp.info("`${cmd}`", outstr.len, errstr.len, "buffed", outbuf.len, errbuf.len)
			if outbuf.len + errbuf.len > 8*1024*1025 {
				toobig = true
				vcp.warn("out toobig", outbuf.len + errbuf.len, cmd)
			}
		}
	}
	// vcp.info("should done", proc.is_alive(), outbuf.len, errbuf.len, cmd)
	proc.wait()
	defer {proc.close()}

	// vcp.info(proc.code, proc.err, args)
	if capio {
		outbuf += proc.stdout_read()
		errbuf += proc.stderr_read()
		// vcp.info("`${cmd}`\n", outstr, errstr)
		// vcp.info(proc.stdout_slurp())
		return outbuf+errbuf
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

// todo temp repack directory
// todo depends packages resolve
// linked shared library resolve
// todo max candidate lines to show option
// todo meta data file auto update
// todo implement nix copy, drop nix depened
// prerequires: sudo!!! tar brotli grep install_name_tool
// sometimes need select package.
// sometimes need input root password
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
	// if true { return }

	args := nomats
	pkgname := args[0]
	// store_path_file := "store-path-head200" // about 15K
	store_path_file := "store-path" // about 11M
	
	vcp.info("reading store-path maybe need secs...")
	rcvals := get_match_store_paths(store_path_file, pkgname)
	vcp.info(rcvals.len, rcvals.str().elide_right(64))
	vcp.zeroprt(rcvals.len, "not found", pkgname, os.file_size(store_path_file))
	if rcvals.len == 0 {
		exit(-1)
	}

	maxoptno := 30
	for i, line in rcvals {
		vcp.info(i, "\t", line)
		if i > maxoptno { break}
	}
	vcp.trueprt(rcvals.len>maxoptno, "too many matches", rcvals.len, pkgname, "file size:", os.file_size(store_path_file))
	if rcvals.len > maxoptno {
		exit(-1)
	}
	mut ino := -1
	mut ipt := ""
	if rcvals.len > 1 {
		ipt = os.input("input the no in [0,${rcvals.len-1}] > ")
		// vcp.info(ipt, ipt.is_digit())
		vcp.zeroprt(ipt, "no input any no")
		if ipt == "" || !ipt.is_digit() {}
		else {ino = ipt.int()}
	}else if rcvals.len == 1{
		vcp.info("only 1 skip interact selection.")
		time.sleep(time.second)
		ino = 0
	}
	// vcp.info(ino)
	if ino < 0 { vcp.info("invalid select no", ino, ipt);  exit(-1) }

		if ino >= 0 && ino < rcvals.len {
			// parse line
			pkgline := rcvals[ino]
			hv, pkg, ver := parse_nixstore_line(pkgline)
			vcp.info(hv, pkg, ver)

			nix := Nixbase{hosturl}
			stpurl := nix.storeurl() + pkgline
			vcp.info("store path full", stpurl)

			runcmd("nix copy ${pkgline} --to pkgs/ --impure --no-use-registries --no-update-lock-file --no-write-lock-file --no-recursive --refresh --repair -v", "", false)
			pkgdir := "pkgs/${pkgline}"
			dotsrcinfo := pkgdir + "/.PKGINFO"
			vcp.info("saved", os.exists(pkgdir), pkgdir)
			if !os.exists(pkgdir){
				vcp.info("wtf 404", pkgdir)
				exit(-1)
			}

			mydir := os.getenv("PWD")
			vcp.info(mydir, pkgdir)

			tmptar := "test123.tar"
			tmpgz := "${tmptar}.gz"

			// runcmd("tar zcf ${mydir}/${tmpgz} .", pkgdir, false)
			runcmd("tar cfp ${mydir}/${tmptar} .", pkgdir, false)
			srcinfo := genpkg_dot_srcinfo(pkg, ver, pkgline, os.file_size(tmptar))
			os.write_file("pkgs/.PKGINFO", srcinfo) !
			// defer {os.rm("pkgs/.PKGINFO")!}

			// repack so it prefixed with usr/local
			runcmd("mkdir pkgs/usr/local -p", "", false)
			runcmd("tar xf ${mydir}/${tmptar}", os.real_path("pkgs/usr/local"), false)
			runcmd("rm -f ${tmptar}", "", false)
			
			vcp.info("wkdir", os.getenv("PWD"))
			runcmd("sudo chmod 755 -R pkgs/usr", "", false)

			// resolve dlpath
			replace_sharelib_ldpaths("pkgs/usr/local")

			runcmd("fakeroot -- tar zcfp ${mydir}/${tmpgz} usr/ .PKGINFO", os.real_path( "pkgs/"), false)
			runcmd("tar tf ${tmpgz}", "", false)
			runcmd("ls -lh ${tmpgz}", "", false)
			runcmd("mv ${tmpgz} ${pkg}-${ver}.darwin.amd64.pkg.tar.gz", "", false)

			vcp.info("cleanup pkgs/usr/local/ ...", "", false)
			runcmd("rm -rf pkgs/usr/local", "", false)
			runcmd("sudo rm -rf pkgs/usr/local", "", false)
			runcmd("rm -rf pkgs/nix/store/", "", false)
			runcmd("sudo rm -rf pkgs/nix/store/", "", false)
			runcmd("sudo rm -rf pkgs/nix/var/", "", false)
		}
	// demo()
}

fn addassignop<T>(v T, p voidptr) T {
	mut n := unsafe { *(&T(p)) }
	n += v
	unsafe { *(&T(p)) = n }
	return n
}
fn replace_sharelib_ldpaths(dir string) {
	mut spctx := 0
	os.walk_with_context(dir, voidptr(&spctx), fn (ctx voidptr, f string) {
		// vcp.info(f, os.is_dir(f), os.is_link(f))
		if os.is_link(f) {
			vcp.info(f, "=>", os.real_path(f))
		}
		if os.is_dir(f) || os.is_link(f) { return }
		if !check_binarch(f) { addassignop(1, ctx)
			// vcp.info(check_binarch(f), ctx, f)
		}
		replace_sharelib_ldpath(f)
	})
	// vcp.info("binarcherr", spctx, dir)
	vcp.falseprt(spctx==0, "binarch not match", spctx, dir)
}
fn replace_sharelib_ldpath(file string) {
	lines := runcmdv("otool -L ${file}")
	// vcp.info(lines)
	if lines.len < 1 { return }
	if lines[0].contains("is not an object file") { return }

	mut changed := false
	for i:=1; i < lines.len;i++ {
		line := lines[i].trim_space()
		if !line.starts_with("/nix/store/") { continue }
		vcp.info(i, "need resolve ldpath", line)

		libpath := line.all_before(" ")
		libbase := os.base(libpath)
		newpath := "@rpath/${libbase}"
		newpath2 := "/usr/local/lib/${libbase}"
		// install_name_tool -change
		runcmd("install_name_tool -change ${libpath} ${newpath} $file", "", false)
		changed = true
	}
	if changed {
		runcmd("otool -L ${file}", "", false)
	}
}

// Mach-O 64-bit executable x86_64
fn check_binarch(file string) bool {
	lines := runcmdv("file ${file}")
	filety := firstofv(lines)
	// vcp.info(filety,  filety.contains("executable"), filety.contains("x86_64") )
	if filety.contains("executable") && !filety.contains("x86_64") {
		return false
	}
	return true
}

// line: /nix/store/imhzscw3r1rd6x40ddc5wwknwdsz6x5r-par2cmdline-0.8.1
fn parse_nixstore_line(line string) (string, string, string) {
	hv := line.all_before("-")
	ver := line.all_after_last("-")	
	pkg := line.all_after("-").all_before_last("-")
	return hv, pkg, ver
}

fn genpkg_dot_srcinfo(pkgname string, pkgver string, hashval string, pkgsize i64) string {
	mut lines := []string{}
	lines = runcmdv("pacman -V")
	pacmanver := lines[1]
	lines = runcmdv("makepkg -V")
	makepkgver := lines[0]
	lines = runcmdv("fakeroot -v")
	fakerootver := lines[0]
	builddate := time.now()

	s := "# Generated by makepkg 4.0.3
# ${pacmanver}
# ${makepkgver}
# ${fakerootver}
# using fakeroot version 1.31
# Wed Oct 23 14:41:09 UTC 2024
# ${builddate.str()}
pkgname = ${pkgname}
pkgver = ${pkgver}-1
pkgdesc = Gives a fake root environment
url = ${hashval}
# builddate = 1729694468
builddate = ${builddate.unix()}
packager = Unknown Packager <pacnix@pacnix.org>
size = ${pkgsize}
arch = x86_64
license = GPL/GPL3/MIT/MIT3
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

fn get_match_store_paths(store_path_file string, kw string) []string{
	mode := 1 // 1 grep, 2 linebyline, 3 readfull
	return match mode {
		1 { get_match_store_paths_grep(store_path_file, kw)}
		2 { get_match_store_paths_linebyline(store_path_file, kw)}
		3 { get_match_store_paths_readfull(store_path_file, kw)}
		else {[]string{}}
	}
}

fn get_match_store_paths_linebyline(store_path_file string, kw string) []string{
	mut rcvals := []string{}
	// ("store-path-head200")! // about 11M
	mut fp := os.open(store_path_file) or {panic(err)}
	defer {fp.close()}
	
	mut buf := []u8{len:96}
	for i:=0; !fp.eof() ;i++ {
		rn := fp.read_bytes_with_newline(mut &buf) or {
		vcp.error(err.str()); break}
		line := buf[..rn].bytestr().trim_space_right()
		// vcp.info(i, line.len, line, kw)
		// vcp.info(i, rn, buf.len, line.len, line)
		if line.len>0 && line.contains(kw) && line != "" {
			vcp.info("got???", i, line.len, line)
			rcvals << line
		}
	}

	return rcvals
}
fn get_match_store_paths_readfull(store_path_file string, kw string) []string{
	vcp.info("not impl")	
	return []string{}
}

fn get_match_store_paths_grep(store_path_file string, kw string) []string{
	if kw.trim_space().len == 0 { return []string{} }
	stfile := store_path_file
	lines := runcmdv("grep ${kw} ${stfile}")
	return lines
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